#!/usr/bin/env perl
use strict;
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;

=head1 NAME

unweft.pl - Unpack a Warp Encapsulation Text Format (WEFT) file and
output just the packaged input file.

=head1 SYNOPSIS

  unweft.pl < input.weft > output.txt

=head1 DESCRIPTION

This script reads a WEFT file from standard input.  The input text file
that is packaged within the WEFT file is then written to standard
output.

=cut

# ==================
# Program entrypoint
# ==================

# First off, set standard output to use UTF-8
#
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Make sure there are no program arguments
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Load the WEFT file
#
warp_accept();

# Echo each line to standard output
#
for(my $i = 1; $i <= warp_count(); $i++) {
  
  # Get an array of substrings for the line
  my @pl = warp_read();
  
  # Echo each substring
  for my $s (@pl) {
    print "$s";
  }
  
  # Write the line break
  print "\n";
}

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

