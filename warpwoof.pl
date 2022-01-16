#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;
use Warp::Writer;

=head1 NAME

warpwoof.pl - Translate ASCII escape sequences within WEFT words into
Unicode codepoints according to a Woof escape table.

=head1 SYNOPSIS

  warpwoof.pl -table escape.woof < input.weft > output.weft

=head1 DESCRIPTION

This script reads WEFT input, transforms it, and outputs the transformed
WEFT results.  Only content words are transformed by this script.
Within each content word, the script scans for ASCII escape sequences
matching sequences defined in the given Woof table.  These sequences are
then replaced with the Unicode codepoint(s) they map to.

=head2 Woof escape table format

The Woof escape table file format is the same as the Warp format used in
the Java version of Uniloom, except that the line breaking style is not
explicitly specified here, relying instead on Perl text input to handle
line break determination, and the rule that escapes may not contain both
uppercase and lowercase letters is abolished (which also means that case
normalization of escapes is no longer done).  The following
documentation is adapted from the Uniloom C<org.canid.warp.WarpFile>
module.

Woof files are US-ASCII plain-text files that are read line by line,
with any CR and/or LF line break characters stripped from the end of the
line.  Whitespace characters are space (SP) and horizontal tab (HT).  A
line that is empty or consists only of whitespace is a I<blank> line.
Blank lines are ignored.  A line for which the first non-whitespace
character is a C<#> is a comment line.  Comment lines are also ignored.

Lines that are neither blank nor comments may have a comment at the end
of the line that begins with a C<#> character.  However, since this
character can also be used as part of escape sequences, it only counts
as the start of a comment if it is preceded by at least one whitespace
character.  Otherwise, it is B<not> considered the start of a comment.
Comments at the end of lines are dropped before the line is processed
further.

There must be at least one non-blank, non-comment line in the Woof file.
The first such line is the header line.  If there are any further such
lines, they are record lines.

After any comment has been removed from the end of the line, both header
and record lines begin processing by dropping all whitespace characters,
so that only non-whitespace, non-comment characters remain on the line.

Header lines after this processing must consist of a single visible,
non-alphanumeric character or uppercase C<H>.  This is the escape
character that all Woof escapes defined by this file will begin with.
Use C<H> to stand for C<#>, which would otherwise be interpreted as a
comment.

Record lines after removing comments and whitespace have the following
format:

=over 4

=item 1.

One or more base-16 characters

=item 2.

Optionally, comma and one or more base-16 characters

=item 3.

Optionally, additional instances of the preceding item

=item 4.

Colon

=item 5.

One or more visible US-ASCII characters

=back

The sequences of base-16 characters form a sequence of Unicode
codepoints, which must be in range 0x0001 - 0x10ffff, and not include
any surrogates.  This sequence is what the escape should be replaced
with on output.  The same sequence can be used in multiple records in a
Woof file.
 
The sequence of visible US-ASCII characters are the escape sequence,
without the opening escape character (which was defined in the header
line).

The escape sequence defined in a record must be unique in the whole Woof
file (case sensitive).  Note that record lines store the value first and
the key last.  Also note that if the key begins with C<#>, this must be
immediately after the colon without any whitespace, to prevent it from
being mistaken for a comment.

Also, the escape sequence of a record must not be a substring of any
other key (starting at the first character), and no other key may be a
substring of it (starting at the first character).  This is because a
first-match policy is used, and if one key is a substring of another key
starting at the first character, the shorter key will always block the
longer one.

=cut

# ==========
# Local data
# ==========

# The visible, non-alphanumeric ASCII symbol that begins each escape.
#
# This is filled in by the parse_woof() routine.
#
my $escsym;

# The maximum length of an escape in the escape map, excluding the
# opening escape character.
#
# This is filled in by the parse_woof() routine.
#
my $escmax = 0;

# Hash table that maps escape sequences (without the opening escape
# character) to strings containing the Unicode codepoints the escape
# maps to.
#
# This is filled in by the parse_woof() routine.
#
my %escmap;

# ===============
# Local functions
# ===============

# Parse a given Woof escape table file and fill in the local data
# variables $escsym $escmax and %escmap.
#
# Parameters:
#
#   1 : string - the path to the Woof escape table
#
sub parse_woof {
  # Check number of parameters
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter and set type
  my $arg_path = shift;
  $arg_path = "$arg_path";
  
  # Open the Woof table file
  open(my $fh, "<", $arg_path) or
    die "Failed to open '$arg_path', stopped";
  
  # Read the file line-by-line
  my $header = 0;
  while ($_ = readline($fh)) {
    
    # If this line is empty or blank, skip it
    if (/^[ \t\r\n]*$/) {
      next;
    }
    
    # If this line is a comment line, skip it
    if (/^[ \t]*#/) {
      next;
    }
  
    # We have a header or record line, so begin by stripping out any
    # CR or LF characters
    s/[\r\n]//g;
  
    # Strip out any comment -- but # is only a comment if it is preceded
    # by whitespace
    s/[ \t]#.*$//g;
    
    # Drop any whitespace
    s/[ \t]//g;
  
    # Process line
    if (not $header) {
      # Header line, so begin by setting header flag
      $header = 1;
      
      # Should be exactly one character
      (length($_) == 1) or
        die "Invalid Woof header line, stopped";
      
      # Replace "H" with "#"
      if ($_ eq 'H') {
        $_ = '#';
      }
      
      # Make sure we got a non-alphanumeric ASCII character
      (/^\p{POSIX_Graph}$/) or
        die "Invalid Woof escape symbol, stopped";
      (not /^\p{POSIX_Alnum}$/) or
        die "Invalid Woof escape symbol, stopped";
      
      # Store the escape symbol
      $escsym = $_;
      
    } else {
      # Record line -- check syntax
      (/^[0-9A-Fa-f]+(?:,[0-9A-Fa-f]+)*:\p{POSIX_Graph}+$/) or
        die "Invalid Woof record line '$_', stopped";
      
      # Get the value and key fields
      /^([^:]+):(.+)$/;
      my $val = $1;
      my $key = $2;
      
      # Split the value on commas
      my @cpv = split /,/, $val;
      
      # Convert each array element to a string containing the codepoint
      # value
      for(my $i = 0; $i <= $#cpv; $i++) {
        # Get the string element
        my $c = $cpv[$i];
        
        # Convert to numeric value
        $c = hex($c);
        
        # Check range of numeric value, that it is in Unicode range and
        # is not a surrogate
        ((($c >= 0) and ($c < 0xd800)) or
            (($c > 0xdfff) and ($c <= 0x10ffff))) or
          die "Invalid codepoint '$cpv[$i]' specified in Woof, stopped";
        
        # Store the string representation consisting of the single
        # codepoint back in the array
        $cpv[$i] = chr($c);
      }
      
      # Concatenate all the array elements together to get the result
      # string
      $val = join "", @cpv;
      
      # Check that key not already defined
      (not exists $escmap{$key}) or
        die "Woof key '$key' defined multiple times, stopped";
      
      # Check that key is not subkey of another key and no other key is
      # a subkey of key
      for my $k (keys %escmap) {
        if (length($k) > length($key)) {
          (not ($key eq substr($k, 0, length($key)))) or
            die "Woof key '$key' is subkey of '$k', stopped";
          
        } elsif (length($k) < length($key)) {
          (not ($k eq substr($key, 0, length($k)))) or
            die "Woof key '$k' is subkey of '$key', stopped";
        }
      }
      
      # Add the mapping to the escape table
      $escmap{$key} = $val;
      
      # Update maximum key length
      if (length($key) > $escmax) {
        $escmax = length($key);
      }
    }
  }
  
  # We should have at least read the header
  ($header) or die "Woof table lacks header line, stopped";
  
  # Close the Woof table file
  close($fh);
}

# ==================
# Program entrypoint
# ==================

# Define variables to hold program arguments
#
my $arg_table = undef;

# Process program arguments
#
for(my $i = 0; $i <= $#ARGV; $i++) {
  my $opt_name = $ARGV[$i];
  if ($opt_name eq '-table') {
    ($i < $#ARGV) or die "-table requires parameter, stopped";
    $i++;
    $arg_table = $ARGV[$i];
    (-f $arg_table) or die "Can't find '$arg_table', stopped";
    
  } else {
    die "Unrecognized option '$opt_name', stopped";
  }
}

# Check that we got a table argument
#
(defined $arg_table) or
  die "Missing required -table parameter, stopped";

# Parse the Woof table file
#
parse_woof($arg_table);

# Get the base-16 string representation of the escape character so we
# can interpolate it reliably within regular expressions
#
my $hescsym = sprintf "%x", ord($escsym);

# Read and parse WEFT input
#
warp_accept();

# Process each line
#
for(my $i = 1; $i <= warp_count(); $i++) {
  
  # Get an array of substrings for the line
  my @pl = warp_read();
  
  # We need to process any content words, which are at indices 1,3,5
  # and so forth
  for(my $j = 1; $j <= $#pl; $j = $j + 2) {
    
    # Get the current content word and store a copy for diagnostic
    # messages
    my $cw = $pl[$j];
    my $cw_original = $cw;
    
    # Transformed content word starts out empty
    my $tcw = '';
    
    # Digest the content word while it contains escape characters
    while ($cw =~ /^([^\x{$hescsym}]*)(\x{$hescsym}.*)$/u) {
    
      # Transfer the prefix to the transformed content word as-is and
      # remove the prefix from the content word so the content word
      # starts out with the escape symbol
      $tcw = $tcw . $1;
      $cw  = $2;
    
      # Must be at least two characters remaining in the content word,
      # which are the escape character and the first character of the
      # escape
      (length($cw) >= 2) or
        die "Invalid content word '$cw_original', stopped";
      
      # Drop the initial escape character
      $cw = substr($cw, 1);
      
      # The matching length is the minimum of the remaining length of
      # the content word and the maximum escape length
      my $mlen = length($cw);
      if ($escmax < $mlen) {
        $mlen = $escmax;
      }
      
      # Look for a match in the escape table, up to the maximum escape
      # length or the remaining length in the content word (whichever is
      # shorter) and set $flen to the match length if found
      my $flen = 0;
      for(my $k = 1; $k <= $mlen; $k++) {
        if (exists $escmap{substr($cw, 0, $k)}) {
          $flen = $k;
          last;
        }
      }
      
      # Make sure we found a match
      ($flen > 0) or
        die "Invalid content word '$cw_original', stopped";
    
      # Transfer the escaped string to the transformed content word
      $tcw = $tcw . $escmap{substr($cw, 0, $flen)};
      
      # Drop the rest of the escape from the digesting content word
      if ($flen >= length($cw)) {
        $cw = '';
      } else {
        $cw = substr($cw, $flen);
      }
    }
    
    # Append anything remaining in the content word to the transformed
    # content word
    $tcw = $tcw . $cw;
    
    # Write the transformed content word back into the array
    $pl[$j] = $tcw;
  }
  
  # Write the transformed line to output
  warp_write(@pl);
}

# Stream the WEFT to output
#
warp_stream();

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 Multimedia Data Technology Inc.

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
