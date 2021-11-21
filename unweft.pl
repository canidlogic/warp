#!/usr/bin/env perl
use strict;
use warnings FATAL => "utf8";

=head1 NAME

unweft.pl - Unpack a Warp Encapsulation Text Format (WEFT) file into the
packaged input file and optionally also extract the packaged Warp map
file.

=head1 SYNOPSIS

  unweft.pl < input.weft > output.txt
  unweft.pl -map mapfile.txt < input.weft > output.txt

=head1 DESCRIPTION

This script reads a WEFT file from standard input.  The input text file
that is packaged within the WEFT file is then written to standard
output.  If the C<-map> parameter is provided, then the Warp map file
that is packaged within the WEFT file is written to the given parameter
file path, overwriting any file that is currently there.

=cut

# ==================
# Program entrypoint
# ==================

# First off, set standard input and standard output to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
  die "Failed to change standard input to UTF-8, stopped";
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Handle parameter list
#
my $write_map = 0;
my $map_path;

if ($#ARGV == -1) {
  # No arguments, so we won't write the map file
  $write_map = 0
  
} elsif ($#ARGV == 1) {
  # Two arguments, so first argument must be -map
  ($ARGV[0] eq '-map') or
    die "Unrecognized argument '$ARGV[0]', stopped";
  
  # Store the map file path
  $write_map = 1;
  $map_path = $ARGV[1];
  
} else {
  die "Wrong number of parameters, stopped";
}

# First line of input needs to be the %WEFT; signature
#
my $sig_line = <STDIN>;
((defined $sig_line) and ($sig_line =~ /^%WEFT;[ \t]*(?:\r\n|\n)?$/u))
  or die "Failed to read WEFT signature, stopped";

# Second line of input needs to be an integer count of the number of
# lines in the map file
#
my $lcount = <STDIN>;
(defined $lcount) or
  die "Failed to read line count in WEFT file, stopped";
if ($lcount =~ /^([0-9]+)[ \t]*(?:\r\n|\n)?$/u) {
  $lcount = int($1);
} else {
  die "Failed to parse line count in WEFT file, stopped";
}

# If the map file was requested, create it now
#
my $fh_map;
if ($write_map) {
  open($fh_map, '> :encoding(UTF-8)', $map_path) or
    die "Failed to create map file '$map_path', stopped";
}

# Read all the lines from the map file; if the map file was requested,
# transfer the lines to the output map file
#
for(my $i = 0; $i < $lcount; $i++) {
  # Read a line from the packaged map file
  my $mline = <STDIN>;
  (defined $mline) or die "Failed to read map file line, stopped";
  
  # If requested, transfer to output map file
  if ($write_map) {
    print { $fh_map } "$mline";
  }
}

# If map file was requested, we can close it now
#
if ($write_map) {
  close($fh_map);
}

# Echo all remaining lines of input to standard output
#
while (<STDIN>) {
  print;
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

