#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;
use Warp::Writer;

# Non-core modules
use TeX::Hyphen;

=head1 NAME

warphyphen.pl - Transform a WEFT file by applying TeX hyphenation
patterns to content words.

=head1 SYNOPSIS

  warphyphen.pl -load patterns.tex [options] < input.weft > output.weft

=head1 DESCRIPTION

This script reads WEFT input, transforms it, and outputs the transformed
WEFT results.  Content words are transformed by hyphenating them
according to a given TeX pattern file.

The C<-load> option is required, which must be followed by another
parameter that is the path to the TeX hyphenation patterns file to load.
This script will assume that the hyphenation pattern file is using UTF-8
format.  If that is not the case, you can use the C<-style> option
followed by a parameter selecting the hyphenation pattern file type.
The supported styles are C<czech> C<german> and C<utf8> (the default).

Optionally, you can specify the C<-list> option followed by the path to
a word list file to generate.  If the given file path already exists, it
will be overwritten.  The word list will contain all unique alphabetic
words that were found within the content words of the file, along with
the hyphenation points marked by grave accents.  Sorting order is
longest word first, and alphabetization only after sort order is
applied.

Optionally, you can specify the C<-special> option followed by the path
to a special hyphenation word list file.  This file contains one
alphabetic word per line, with hyphenation points marked with grave
accents.  If a word is present without any grave accents, it means that
there are no hyphenation points in the alphabetic word.  Words can be
given in any order in this list file.

B<IMPORTANT:> Matching in the special word list is I<case-sensitive>.
This means that you may have to provide multiple versions of the same
word (lowercase, capitalized, all-caps, etc.).  The word list generated
by the C<-list> option is also case-sensitive.  There are complexities
involving case transformation, so making this script case-insensitive
would involve accounting for a number of edge cases.  It is much more
reliable to have matching be case sensitive.

When a special hyphenation word list is given, this script will first
look up alphabetic words to see if they match anything in the special
word list.  If so, then the TeX patterns are not applied and instead the
special hyphenation pattern is used.  Otherwise, the TeX patterns are
applied.

=cut

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

# Make sure we at least got the path to the pattern file
#
($has_path) or die "Must provide a pattern file with -load, stopped";

# Read and parse WEFT input
#
warp_accept();

# @@TODO:

# @@TODO: generate word list if requested

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
