#!/usr/bin/env perl
use strict;
use warnings FATAL => "utf8";

# Core modules
use File::Temp qw/ tempfile /;

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

# First off, set standard input and standard output to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
  die "Failed to change standard input to UTF-8, stopped";
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Make sure there are no program arguments
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Open a temporary file that will store the input lines that we read so
# we can echo them back later; set UTF-8 encoding on this file
#
my $fh_cache = tempfile();
(defined $fh_cache) or die "Failed to create temporary file, stopped";
binmode($fh_cache, ":encoding(utf8)") or
  die "Failed to change temporary file to UTF-8, stopped";

# Open a temporary file that will store the Warp map file and also start
# a record counter out at zero
#
my $fh_map = tempfile();
(defined $fh_map) or die "Failed to create temporary file, stopped";
my $rec_count = 0;

# Now read and process all lines of input, while also storing them into
# the temporary cache file
#
my $first_line = 1;
my $flag_lb = 0;
while (<STDIN>) {
  
  # If this is first line, and it begins with a Byte Order Mark, then
  # strip the Byte Order Mark
  if ($first_line and /^\x{feff}/u) {
    $_ = substr($_, 1);
  }
  
  # If this line ends with LF or CR+LF, then strip the line break and
  # set flag_lb
  $flag_lb = 0;
  if (/\r\n$/u) {
    # Strip CR+LF
    $_ = substr($_, 0, -2);
    $flag_lb = 1;
    
  } elsif (/\n$/u) {
    # Strip LF
    $_ = substr($_, 0, -1);
    $flag_lb = 1;
  }
  
  # Make sure no stray CR or LF characters left
  ((not /\r/u) and (not /\n/u)) or
    die "Stray line break characters, stopped";
  
  # Write the line to the cache file, append an LF if there was
  # originally a line break
  if ($flag_lb) {
    print {$fh_cache} "$_\n";
  } else {
    print {$fh_cache} "$_";
  }
  
  # First check if the whole line is whitespace
  if (/^[ \t]*$/u) {
    # Whole line is whitespace, so just a single NL record that has the
    # number of codepoints in the line
    my $ccount = length;
    print {$fh_map} "+$ccount,0\n";
    $rec_count++;
    
  } else {
    # At least one non-whitespace character, so first count what comes
    # after the last non-whitespace
    /([ \t]*)$/u;
    my $line_suffix = length($1);
    
    # Strip the line suffix if it is not empty
    if ($line_suffix > 0) {
      $_ = substr($_, 0, -($line_suffix));
    }
    
    # Parse the rest of the line as pairs of whitespace runs and
    # non-whitespace sequences, and emit the proper records
    my $first_record = 1;
    while (/([ \t]*)([^ \t]+)/gu) {
      # Get lengths of prefix and content word
      my $prefix_len = length($1);
      my $content_len = length($2);
      
      # Emit appropriate record
      if ($first_record) {
        print {$fh_map} "+$prefix_len,$content_len\n";
        $rec_count++;
      } else {
        print {$fh_map} ".$prefix_len,$content_len\n";
        $rec_count++;
      }
      
      # Clear the first_record flag
      $first_record = 0;
    }
    
    # We should have generated at least one record
    (not $first_record) or die "Parsing error, stopped";
    
    # Finish it off with a W record that stores the suffix length
    print {$fh_map} ".$line_suffix,0\n";
    $rec_count++;
  }
  
  # Clear the first line flag
  $first_line = 0;
}

# If first_line flag is still set, the file was empty with no lines, so
# add a blank line record to the map file; otherwise, if flag_lb is set,
# then add another blank line record to account for the line after the
# last line break
#
if ($first_line) {
  print {$fh_map} "+0,0\n";
  $rec_count++;

} elsif ($flag_lb) {
  print {$fh_map} "+0,0\n";
  $rec_count++;
}

# Now we can append the EOF record
#
print {$fh_map} "\$0,0\n";
$rec_count++;

# Begin with the WEFT header and count of records in the map file
#
print "%WEFT;\n$rec_count\n";

# Now rewind the map file and echo all the record lines
#
seek($fh_map, 0, 0);
for(my $i = 0; $i < $rec_count; $i++) {
  my $lr = readline($fh_map);
  print "$lr";
}

# We can now close the temporary map file
#
close($fh_map);

# We now need to echo the input file that we cached in the temporary
# file
#
seek($fh_cache, 0, 0);
while (readline($fh_cache)) {
  print;
}

# Close the temporary file
#
close($fh_cache);

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
