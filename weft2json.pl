#!/usr/bin/env perl
use strict;
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;

=head1 NAME

weft2json.pl - Reformat a WEFT input file in JSON.

=head1 SYNOPSIS

  weft2json.pl < input.weft > output.json

=head1 DESCRIPTION

This script reads a WEFT file from standard input and outputs a JSON
representation.  It is also useful for diagnostics, to see what is
contained within a WEFT.

The top-level JSON object will be an array.  This array contains one
array per line of the input file.  Each inner array contains strings
representing the parsed strings from the C<Warp::Reader> module.

Control codes as well as double quotes and backslashes are properly
escaped before being placed in the JSON strings.  Unicode that is not in
the control code range is passed directly into the strings, which is
allowed by JSON.  However, supplemental Unicode characters are split
into surrogate pairs, which are then escaped in the JSON string.

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

# Write the start of the outer JSON array
#
print "[\n";

# Package each line into an inner JSON array
#
for(my $i = 1; $i <= warp_count(); $i++) {
  
  # Get an array of substrings for the line
  my @pl = warp_read();
  
  # Write the start of the inner JSON array, but omit the opening line
  # break here, which will be written with the first element
  print "  [";
  
  # Encode each substring
  for(my $j = 0; $j <= $#pl; $j++) {
    
    # If j is divisible by two, insert a line break so that skip/read
    # substrings are paired on lines; else, insert a space
    if (($j % 2) == 0) {
      print "\n    ";
    } else {
      print " ";
    }
    
    # Get the current substring
    my $str = $pl[$j];
    
    # Escape backslash first
    $str =~ s/\\/\\\\/ug;
    
    # Escape double-quote
    $str =~ s/"/\\"/ug;
    
    # Escape special control codes that have dedicated escapes
    $str =~ s/\x{08}/\\b/ug;
    $str =~ s/\x{0c}/\\f/ug;
    $str =~ s/\x{0a}/\\n/ug;
    $str =~ s/\x{0d}/\\r/ug;
    $str =~ s/\x{09}/\\t/ug;
    
    # Escape 0x7f
    $str =~ s/\x{7f}/\\u007f/ug;
    
    # Supplementary characters must be split into surrogate pairs in
    # JSON and then escaped
    my @sup;
    while ($str =~ /([\x{10000}-\x{10ffff}])/gu) {
      my $si = pos $str;
      $si--;
      push @sup, ($si);
    }
    for(my $k = $#sup; $k >= 0; $k--) {
      # Get the supplemental codepoint
      my $codep = ord(substr($str, $sup[$k], 1));
      ($codep > 0xffff) or die "Invalid supplemental, stopped";
      
      # Convert to an offset in supplemental plane
      $codep = $codep - 0x10000;
      
      # Split into high ten bits and low ten bits
      my $hi = $codep >> 10;
      my $lo = $codep & 0x3ff;
      
      # Convert to surrogate codepoints
      $hi = $hi + 0xd800;
      $lo = $lo + 0xdc00;
      
      # Get JSON escape sequence
      my $je = sprintf("\\u%04x\\u%04x", $hi, $lo);
      
      # Replace supplemental with escape sequence
      substr($str, $sup[$k], 1) = $je;
    }
    
    # Escape any other control codes still present
    my @ccp;
    while ($str =~ /(\p{X_POSIX_Cntrl})/gu) {
      my $si = pos $str;
      $si--;
      push @ccp, ($si);
    }
    for(my $k = $#ccp; $k >= 0; $k--) {
      substr($str, $ccp[$k], 1) = sprintf(
                                    "\\u%04x",
                                    ord(substr($str, $ccp[$k], 1)));
    }
    
    # Print the escaped string in quotes
    print "\"$str\"";
    
    # If this is not the last element, insert a comma
    if ($j < $#pl) {
      print ",";
    }
  }
  
  # Write the end of the inner JSON array
  print "\n  ]";
  
  # If this is not the last line, add a comma and a line break; else,
  # just add a line break
  if ($i < warp_count()) {
    print ",\n";
  } else {
    print "\n";
  }
}

# Write the end of the outer JSON array
#
print "]\n";

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
