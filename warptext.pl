#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Warp modules
use Warp::Writer;

=head1 NAME

warptext.pl - Package a plain-text file in a Warp Encapsulation Text
Format (WEFT) package that can be processed with Warp tools.

=head1 SYNOPSIS

  warptext.pl < input.txt > output.weft

=head1 DESCRIPTION

This script reads a plain-text file from standard input.  It writes a
WEFT file to standard output that includes the plain-text file as well
as a Warp map file that indicates where the content words are located
within the plain-text file.

This script considers content words to be any sequences of one or more
consecutive codepoints in the input file that are not ASCII space, ASCII
tab, or the line break characters LF and CR.

The plain-text file MUST be in UTF-8.  (US-ASCII files are also OK,
because they are a strict subset of UTF-8.)  Line break style may be
either LF or CR+LF.  An optional UTF-8 byte order mark (BOM) is allowed
at the beginning of the file, but it is not copied into the WEFT file
and it is not considered to be part of any content word.

=cut

# ==================
# Program entrypoint
# ==================

# Make sure there are no program arguments
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# First off, set standard input to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
  die "Failed to change standard input to UTF-8, stopped";

# Read and process all lines of input
#
my $first_line = 1;
while (<STDIN>) {
  
  # If this is first line, and it begins with a Byte Order Mark, then
  # strip the Byte Order Mark
  if ($first_line and /^\x{feff}/u) {
    $_ = substr($_, 1);
  }
  
  # If this line ends with LF or CR+LF, then strip the line break
  if (/\r\n$/u) {
    # Strip CR+LF
    $_ = substr($_, 0, -2);
    
  } elsif (/\n$/u) {
    # Strip LF
    $_ = substr($_, 0, -1);
  }
  
  # Make sure no stray CR or LF characters left
  ((not /\r/u) and (not /\n/u)) or
    die "Stray line break characters, stopped";
  
  # First check if the whole line is whitespace
  if (/^[ \t]*$/u) {
    # Whole line is whitespace, so just a single substring containing
    # the whole line
    warp_write($_);
    
  } else {
    # At least one non-whitespace character, so first get what comes
    # after the last non-whitespace
    /([ \t]*)$/u;
    my $line_suffix = $1;
    
    # Strip the line suffix if it is not empty
    if (length $line_suffix > 0) {
      $_ = substr($_, 0, -(length $line_suffix));
    }
    
    # Parse the rest of the line as pairs of whitespace runs and
    # non-whitespace sequences, and add them to an array
    my @a;
    while (/([ \t]*)([^ \t]+)/gu) {
      push @a, ($1, $2);
    }
    
    # Now append the suffix
    push @a, ($line_suffix);
    
    # Write the line
    warp_write(@a);
  }
  
  # Clear the first line flag
  $first_line = 0;
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
