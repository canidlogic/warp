#!/usr/bin/env perl
use strict;
use sort "stable";
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;
use Warp::Writer;

# Non-core modules
use TeX::Hyphen;

# Core modules
use DB_File;
use Fcntl;
use File::Temp qw/ tmpnam /;
use Unicode::Collate;
use Unicode::Normalize;

=head1 NAME

warphyphen.pl - Transform a WEFT file by applying TeX hyphenation
patterns and/or special hyphenation word lists to content words.  Can
also generate a word list.

=head1 SYNOPSIS

  warphyphen.pl [options] < input.weft > output.weft

=head1 DESCRIPTION

This script reads WEFT input, transforms it, and outputs the transformed
WEFT results.  Content words are transformed by hyphenation, which is
controlled by options documented in the following section.  If no
options are provided, no hyphenation will be applied, but the output may
not be exactly the same as the input due to Unicode normalization
applied to certain content words.

Hyphenation is only applied to content words that contain at least one
codepoint in the Unicode class L (Letter).  None such content words may
contain the grave accent symbol, nor any ASCII space, tab, LF, or CR
character.  Unicode normalization to NFC is applied to such content
words, but not to anything else.

Before using this script, you should use C<warpword.pl> or a similar
script to make sure content words are cleanly divided by linguistic
words that contain at least one L-class codepoint, and non-linguistic
content that does not contain any L-class codepoint.

To use this script to generate a word list, use the C<-list> option by
itself.

Temporary databases are used, so this script should be able to handle
huge input files and huge word specialized hyphenation lists without
problem.  However, the C<-list> option requires that all keys be loaded
into memory at once to sort them properly.

=head2 Script options

=over 4

=item -load [path]

If provided, this option instructs the script to load the TeX
hyphenation patterns file given at the path C<[path]>.  If both a TeX
hyphenation pattern file and a special word list (C<-spec>) is provided,
the special word list is consulted before the TeX hyphenation patterns,
and used instead of the hyphenation patterns if the word is found
within.

=item -style [format]

By default, this script assumes that a TeX hyphenation pattern file
specified by the C<-load> option is in UTF-8 format.  If this is not the
case, use this C<-style> option to select a different pattern file
format.  The given C<[format]> parameter must be a case-sensitive match
for C<czech> C<german> or the default C<utf8>.  This option has no
effect if no hyphenation pattern file is specified.

B<Important:> The hyphenation pattern style refers to the encoding
method for text, I<not> the language used.  That is, German hyphenation
pattern files do I<not> necessarily use the C<german> style.

=item -list [path]

If provided, this option instructs the script to generate a hyphenated
word list and store it to the file at C<[path]>, overwriting any file
that may already be present.  The generated file will be a UTF-8 text
file with one word per line, and grave accents used to mark hyphenation
points.  Words are sorted first by length (longest words first; grave
accents not counted) and then alphabetically according to Unicode
Collation (grave accents ignored).

All words are sequences of one or more Unicode codepoints excluding
ASCII space, horizontal tab, CR, and LF.  The grave accent symbol always
is a marker of a hyphenation point.  Neither the first nor last
character will ever be a grave accent, and grave accents never appear
immediately before another grave accent.  Unicode will be normalized in
NFC form.

The word list is case sensitive, so a word is listed more than once, for
example, if it appears both in a capitalized and lowercase version.
Words that have no hyphenation added will still be in the word list,
appearing without any grave accents.  Exact duplicates will be dropped
from the word list.

=item -special [path]

If provided, this option instructs the script to load a specialized word
list to consult for hyphenation from the file at C<[path]>.  The format
of this word list is identical to the kind of list generated by the
C<-list> option except the records do not need to be sorted and
duplicates are allowed so long as they have the same hyphenation
pattern.  It is therefore possible to generate a word list with the
C<-list> option, manually apply hyphens with grave accents to the
generated list, and then use it with this C<-special> option to
hyphenate words.

If used together with the C<-load> option, the specialized word list has
priority, and the TeX hyphenation patterns will only be consulted for
words that do not appear on the specialized word list.

Words on the specialized word lists that do not have any grave accents
mean that the word should not be hyphenated.

B<Important:> matching to the specialized word list is case sensitive.
Therefore, certain words may need to appear more than once on the list
if they are used, for example, capitalized in some places and lowercase
in other places.

=back

=cut

# ==========
# Local data
# ==========

# The specialized word list database.
#
# $spec_init indicates whether the database is initialized.  If it is
# not, none of the other variables are valid.
#
# $spec_dbpath is the path to the temporary file holding the word list
# database.  Only valid if $spec_init.
#
# %spec is the hash that is tied to the database.  Only valid if
# $spec_init.
#
# There is an END block that checks whether the database is initialized
# at the end of the program, and unties and deletes it if it is.
#
my $spec_init = 0;
my $spec_dbpath;
my %spec;
END {
  if ($spec_init) {
    untie %spec;
    unlink $spec_dbpath;
    $spec_init = 0;
  }
}

# The hyphenation word cache database.
#
# $cache_init indicates whether the database is initialized.  If it is
# not, none of the other variables are valid.
#
# $cache_dbpath is the path to the temporary file holding the cached
# word list database.  Only valid if $cache_init.
#
# %cache is the hash that is tied to the database.  Only valid if
# $cache_init.
#
# There is an END block that checks whether the database is initialized
# at the end of the program, and unties and deletes it if it is.
#
my $cache_init = 0;
my $cache_dbpath;
my %cache;
END {
  if ($cache_init) {
    untie %cache;
    unlink $cache_dbpath;
    $cache_init = 0;
  }
}

# The loaded TeX hyphenation pattern object.
#
# $hyp_init indicates whether the object is loaded.
#
# $hyp is the object, which is only valid if $hyp_init.
#
my $hyp_init = 0;
my $hyp;

# ===============
# Local functions
# ===============

# Build the specialized word list database.
#
# $spec_init must not already be set when this function is called.  The
# local data for the specialized word list database will be configured.
#
# The given file is read line by line.  UTF-8 is used, and if a Byte
# Order Mark (BOM) is present at the start of the first line, it is
# ignored.  Line breaks may be either LF or CR+LF.
#
# Lines that are empty or contain only tabs and spaces are ignored.  A
# word list file that is empty without any words is acceptable.
#
# Otherwise, lines are trimmed of leading and trailing whitespace before
# they are processed.  After trimming, the line is normalized to NFC
# form.  After that, no more spaces, tabs, CRs or LFs may remain on the
# line.  Furthermore, neither the first nor last codepoint may be the
# grave accent, and no grave accent may immediately follow another grave
# accent.
#
# The trimmed line with grave accents dropped is the key, while the
# trimmed line with grave accents turned into soft hyphens is the value.
# A key may be repeated more than once only if it has the exact same
# value each time.  Key matching is case sensitive.
#
# Parameters:
#
#   1 : string - path to the specialized word list file to parse
#
sub build_spec {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get argument and set type
  my $arg_path = shift;
  $arg_path = "$arg_path";
  
  # Check state
  ($spec_init == 0) or
    die "Specialized database already initialized, stopped";
  
  # Open the file for reading and in UTF-8 mode
  open(my $fh, "< :encoding(UTF-8)", $arg_path) or
    die "Failed to open specialized list '$arg_path', stopped";
  
  # Generate a temporary name for the database
  $spec_dbpath = tmpnam();
  
  # The order of words in the specialized database doesn't matter, so we
  # will just use a hash DB with the default comparison function; create
  # the database
  tie %spec, "DB_File", $spec_dbpath, O_RDWR|O_CREAT, 0666, $DB_HASH
    or die "Failed to create temporary database, stopped";
  
  # Set the initialization flag, so database is cleaned up on exit
  $spec_init = 1;
  
  # Read through each line of the list file and add records to the
  # specialized database
  while (my $s = readline($fh)) {
  
    # First trim leading and trailing whitespace
    $s =~ s/[ \t\r\n]*$//u;
    $s =~ s/^[ \t]*//u;
    
    # If result is empty, skip this line
    if (length $s < 1) {
      next;
    }
  
    # Normalize the line to NFC
    $s = NFC($s);
    
    # Make sure there are no whitespace or line break characters left
    (not ($s =~ /[ \t\r\n]/u)) or
      die "Internal whitespace in specialized file: '$s', stopped";
    
    # Make sure neither first nor last character is a grave accent, and
    # that no sequence of consecutive grave accents is present
    ((not ($s =~ /^`/u)) and (not ($s =~ /`$/u)) and
        (not ($s =~ /``/u))) or
      die "Invalid hyphenation syntax: '$s', stopped";
  
    # The key for this entry has all grave accents dropped, while the
    # value has all grave accents replaced with soft hyphens
    my $key = $s;
    my $val = $s;
    
    $key =~ s/`//ug;
    $val =~ s/`/\x{ad}/ug;
    
    # If key already exists is database, make sure the value is the
    # same; else, add the key and value pair to the database
    if (exists $spec{$key}) {
      # Key exists, check that value is equal
      ($spec{$key} eq $val) or
        die "Specialized key '$key' has multiple hyphenations, stopped";
      
    } else {
      # Key doesn't exist -- add it
      $spec{$key} = $val;
    }
  }
  
  # Close the specialized list file
  close($fh);
}

# Process a linguistic word by inserting soft hyphens.
#
# The given parameter must not contain any whitespace, line breaks, or
# grave accents, and not be empty.  It will be normalized to NFC by this
# function.
#
# First, this function initializes the hyphenated word cache database if
# not already initialized.  Then, it checks whether the given word is
# in the cache.  If it is, then it returns the cached hyphenation for
# the word.
#
# Otherwise, the next step is to consult the specialized word list
# database, if it exists.  If the word is in that database, the
# specialized hyphenation is used, and this specialized hyphenation
# record is copied into the cache database.
#
# Failing that, if a TeX hyphenation pattern is loaded, it will be used
# to hyphenate the given word, and the generated hyphenation will be
# added to the cache database.
#
# If all else fails, no hyphens will be added to the word and this
# decision will be added to the cache database.
#
# Parameters:
#
#   1 : string - the alphabetic word to process
#
# Return:
#
#   string - the hyphenated word
#
sub proc_word {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get argument and set type
  my $w = shift;
  $w = "$w";
  
  # Normalize to NFC
  $w = NFC($w);
  
  # Make sure the word is not empty and it does not contain any
  # whitespace or line breaks or grave accents
  (length $w > 0) or die "Empty word, stopped";
  (not ($w =~ /[ \t\r\n`]/u)) or die "Invalid word: '$w', stopped";
  
  # Initialize hyphenation word cache database if needed
  if ($cache_init == 0) {
    # Generate a temporary name for the database
    $cache_dbpath = tmpnam();
    
    # The order of words in the cache database doesn't matter, so we
    # will just use a hash DB with the default comparison function;
    # create the database
    tie %cache, "DB_File", $cache_dbpath, O_RDWR|O_CREAT, 0666, $DB_HASH
      or die "Failed to create temporary database, stopped";
    
    # Set the initialization flag, so database is cleaned up on exit
    $cache_init = 1;  
  }
  
  # The match_found flag starts out clear and define variable for result
  my $match_found = 0;
  my $result;
  
  # If the word is cached, use the cached record
  if (($match_found == 0) and (exists $cache{$w})) {
    $match_found = 1;
    $result = $cache{$w};
  }
  
  # If we haven't found a match and the specialized database is defined,
  # check for the word in the specialized database, adding it also to
  # the cache if found
  if (($match_found == 0) and $spec_init) {
    if (exists $spec{$w}) {
      $match_found = 1;
      $result = $spec{$w};
      $cache{$w} = $result;
    }
  }
  
  # If we still haven't found a match and the TeX pattern is defined,
  # use the pattern to hyphenate the word, adding the result to the
  # cache
  if (($match_found == 0) and $hyp_init) {
    my @loc = $hyp->hyphenate($w);
    $result = $w;
    for(my $i = $#loc; $i >= 0; $i--) {
      substr($result, $loc[$i], 0) = "\x{ad}";
    }
    $match_found = 1;
    $cache{$w} = $result;
  }
  
  # If we are still without a result, just assume no hyphenation, and
  # add that decision to the cache
  if ($match_found == 0) {
    $match_found = 1;
    $result = $w;
    $cache{$w} = $result;
  }
  
  # Return the result
  return $result;
}

# Write a wordlist representing everything currently in the hyphenation
# cache to a text file at the given location.
#
# The text file will have one word per line, with hyphenation points
# indicated with grave accents.
#
# The words in the text file will be sorted such that longer words come
# before shorter words.  Words of the same length are sorted
# alphabetically according to the Unicode Collation Algorithm.  Grave
# accents representing hyphenation points are NOT counted for purposes
# of sorting by length or alphabetically.
#
# Parameters:
#
#   1 : string - path to the word list file to generate
#
sub gen_wordlist {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get argument and set type
  my $arg_path = shift;
  $arg_path = "$arg_path";
  
  # Get a list of all the keys
  my @keylist;
  if ($cache_init) {
    @keylist = keys %cache;
  }
  
  # Sort all keys according to Unicode collation algorithm
  my $col = Unicode::Collate->new();
  my @sorted = $col->sort(@keylist);
  
  # Now sort all keys by length -- since we required a stable sort in
  # the feature list at the beginning of this script, this has the
  # effect of sorting first by length and then by Unicode collation
  my @wl = sort { length($b) <=> length($a) } @sorted;
  
  # Open the word list file
  open(my $fh, "> :encoding(UTF-8)", $arg_path) or
    die "Failed to create word list file '$arg_path', stopped";
  
  # Write the cached entries to the list file in proper order, with soft
  # hyphens replaced by grave accents
  for my $k (@wl) {
    my $v = $cache{$k};
    $v =~ s/\x{ad}/`/ug;
    print {$fh} "$v\n";
  }
  
  # Close word list file
  close($fh);
}

# ==================
# Program entrypoint
# ==================

# Define variables to hold program option results
#
my $has_path = 0;
my $has_list = 0;
my $has_spec = 0;

my $tex_path;
my $tex_style = "utf8";
my $list_path;
my $spec_path;

# Parse options
#
for(my $i = 0; $i <= $#ARGV; $i++) {
  
  # Interpret specific option
  if ($ARGV[$i] eq '-load') {
    # Must be another argument
    ($i < $#ARGV) or die "-load option requires parameter, stopped";
    
    # Consume next argument and store it
    $i++;
    $has_path = 1;
    $tex_path = $ARGV[$i];
    
    # Check that pattern file exists
    (-f $tex_path) or
      die "Can't find pattern file '$tex_path', stopped";
    
  } elsif ($ARGV[$i] eq '-style') {
    # Must be another argument
    ($i < $#ARGV) or die "-style option requires parameter, stopped";
    
    # Consume next argument and store it
    $i++;
    $tex_style = $ARGV[$i];
    
    # Check that style is recognized
    (($tex_style eq 'utf8') or
        ($tex_style eq 'czech') or ($tex_style eq 'german')) or
      die "Unrecognized TeX pattern style '$tex_style', stopped";
    
  } elsif ($ARGV[$i] eq '-list') {
    # Must be another argument
    ($i < $#ARGV) or die "-list option requires parameter, stopped";
    
    # Consume next argument and store it
    $i++;
    $has_list = 1;
    $list_path = $ARGV[$i];
    
  } elsif ($ARGV[$i] eq '-special') {
    # Must be another argument
    ($i < $#ARGV) or die "-special option requires parameter, stopped";
    
    # Consume next argument and store it
    $i++;
    $has_spec = 1;
    $spec_path = $ARGV[$i];
    
    # Check that specialized file exists
    (-f $spec_path) or
      die "Can't find specialized list file '$spec_path', stopped";
    
  } else {
    die "Unrecognized option '$ARGV[$i]', stopped";
  }
}

# If we were given a specialized word list, load the specialized
# database
#
if ($has_spec) {
  build_spec($spec_path);
}

# If we were given a TeX hyphenation pattern file, load it
#
if ($has_path) {
  ($hyp = new TeX::Hyphen 'file' => $tex_path, 'style' => $tex_style)
    or die "Failed to load TeX pattern file '$tex_path', stopped";
  $hyp_init = 1;
}

# Read and parse WEFT input
#
warp_accept();

# Process each line
for(my $i = 1; $i <= warp_count(); $i++) {
  
  # Get an array of substrings for the line
  my @pl = warp_read();
  
  # We need to hyphenate content words, which are at indices 1,3,5 and
  # so forth
  for(my $j = 1; $j <= $#pl; $j = $j + 2) {

    # Get the current content word
    my $cw = $pl[$j];
    
    # If this content word does not have any L-class codepoint within
    # it, skip processing for it
    if (not ($cw =~ /\pL/u)) {
      next;
    }
    
    # We have a linguistic content word, so hyphenate it
    $cw = proc_word($cw);
    
    # Replace the current content word with the transformed content word
    $pl[$j] = $cw;
  }
  
  # Write the transformed line to output
  warp_write(@pl);
}

# Generate word list if requested
#
if ($has_list) {
  gen_wordlist($list_path);
}

# Stream the WEFT to output
#
warp_stream();

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut
