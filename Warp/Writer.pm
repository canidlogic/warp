package Warp::Writer;
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";
use parent qw(Exporter);

# Core modules
use File::Temp qw/ tempfile /;

# Symbols to export from this module
#
our @EXPORT = qw(
                warp_write
                warp_stream);

=head1 NAME

Warp::Writer - Module for writing WEFT output.

=head1 SYNOPSIS

  use Warp::Writer;
  
  # Write a substring array representing a line
  warp_write(@substrs);
  
  # When everything has been written, stream to output
  warp_stream();

=head1 DESCRIPTION

The C<Warp::Writer> module is intended for Warp utilities of the
I<filter> and I<source> types, which write a WEFT file to standard
output.  See the C<README.md> file for further information about the
Warp utility architecture.

=cut

# =================
# Local module data
# =================

# The total number of lines that have been written, or -1 if
# warp_stream() has been called already.
#
my $line_count = 0;

# The total number of Warp Map records that have been written.
#
my $rec_count = 0;

# The handle to the temporary file storing the Warp Map.
#
# Only defined if $line_count is greater than zero.
#
my $fh_map;

# The handle to the temporary file storing the cache of the packaged
# file within the WEFT.
#
# Only defined if $line_count is greater than zero.
#
my $fh_cache;

=head1 METHODS

=over 4

=item B<warp_write(LIST)>

Add another parsed line to the WEFT output.

This function may not be called after C<warp_stream> has been called.
Croaks on error.

The function parameters must be a list of at least one string, where the
total length of the parameter list is an odd number.  All parameters
must be strings.

If there is exactly one string parameter, it means there are no content
words in the line.  In this case, the lone string contains all
codepoints in the line (excluding the line break), none of which should
be transformed by Warp utilities.  The string may be empty if the line
is empty.

Otherwise, there are C<(2*N + 1)> string parameters, where C<N> is the
total number of content words on the line.  The first string (index
zero) contains all codepoints that occur before the first content word
in the line, and the last string (index C<2*N>) contains all codepoints
that occur after the last content word in the line, excluding the line
break.  Both of these strings may be empty.

For all other string parameters, a string with index C<(2*i + 1)> is the
content word with zero-based index C<i> in the parsed line.  Content
words always contain at least one Unicode codepoint.  On the other hand,
a string with index C<2*j> that is neither the first nor last element of
the array contains all the Unicode codepoints that come between the
content words with zero-based indices C<(j-1)> and C<j>.  Such strings
may be empty.

The lines are buffered in temporary files and are not actually written
to output by this function.  Once you have recorded all the lines with
this function, use C<warp_stream()> to write the complete WEFT file to
output.

=cut

sub warp_write {
  # Check state
  ($line_count >= 0) or die "Can't write after warp_stream(), stopped";
  
  # Must be at least one parameter and count of parameters must be odd
  (($#_ >= 0) and (($#_ % 2) == 0)) or 
    die "Parameter count must be odd, stopped";
  
  # Make sure each parameter is not a reference, convert each parameter
  # to a string, make sure that parameters with a zero-based index that
  # is odd are not empty, and make sure that no substring contains CR,
  # LF, or a surrogate
  for(my $i = 0; $i <= $#_; $i++) {
    (not ref($_[$i])) or die "Can't pass a reference, stopped";
    $_[$i] = "$_[$i]";
    if (($i % 2) == 1) {
      (length $_[$i] > 0) or die "Content word can't be empty, stopped";
    }
    (not ($_[$i] =~ /\r/u)) or
      die "Can't include CR in any substring, stopped";
    (not ($_[$i] =~ /\n/u)) or
      die "Can't include LF in any substring, stopped";
    (not ($_[$i] =~ /[\x{d800}-\x{dfff}]/u)) or
      die "Can't include surrogates use supplemental directly, stopped";
  }
  
  # If this is the very first line that is written, open the temporary
  # files
  if ($line_count == 0) {
    $fh_map = tempfile();
    (defined $fh_map) or die "Failed to create temporary file, stopped";
    
    $fh_cache = tempfile();
    (defined $fh_cache) or
      die "Failed to create temporary file, stopped";
    binmode($fh_cache, ":encoding(utf8)") or
      die "Failed to change temporary file to UTF-8, stopped";
  }
  
  # Write the Warp Map records for this line
  for(my $i = 0; $i <= $#_; $i = $i + 2) {
    # We are iterating by twos, and the length of the first element in
    # each pair is always the skip count
    my $skip_count = length $_[$i];
    
    # If this is not the last element, the second element of the pair
    # exists and its length is the read count; otherwise, set read count
    # to zero
    my $read_count = 0;
    if ($i < $#_) {
      $read_count = length $_[$i + 1];
    }
    
    # If this is the first element on the line we need an NL record;
    # else, we need a W record
    if ($i == 0) {
      print {$fh_map} "+";
    } else {
      print {$fh_map} ".";
    }
    
    # Output the skip count and read count followed by line break
    printf {$fh_map} "%d,%d\n", $skip_count, $read_count;
    
    # Update record count
    $rec_count++;
  }
  
  # Write all the substrings to the cache file, followed by a line break
  for my $s (@_) {
    print {$fh_cache} "$s";
  }
  print {$fh_cache} "\n";
  
  # Update the line count
  $line_count++;
}

=item B<warp_stream()>

Generate the full WEFT file and write it to standard output.

This function may only be called after at least one call to
warp_write().  After this function is called, it can't be called again,
nor may warp_write() be called again.

=cut

sub warp_stream {
  # Should have exactly zero arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";
  
  # Check state
  ($line_count > 0) or die "No lines to encode to WEFT, stopped";
  
  # First off, set standard output to use UTF-8
  binmode(STDOUT, ":encoding(utf8)") or
    die "Failed to change standard output to UTF-8, stopped";
  
  # Finish the map file by adding an EOF record
  print {$fh_map} "\$0,0\n";
  $rec_count++;
  
  # Write the WEFT header lines
  print "%WEFT;\n$rec_count,$line_count\n";
  
  # Rewind the Warp Map and write each map record
  seek($fh_map, 0, 0);
  for(my $i = 1; $i <= $rec_count; $i++) {
    # Read a line from the map file
    my $mline = readline($fh_map);
    (defined $mline) or die "Failed to read cached map line, stopped";
    
    # Write the line to output
    print "$mline";
  }
  
  # Rewind the cache file and write each line
  seek($fh_cache, 0, 0);
  for(my $i = 1; $i <= $line_count; $i++) {
    # Read a line from the cache file
    my $cline = readline($fh_cache);
    (defined $cline) or die "Failed to read cached line, stopped";
    
    # Write the line to output
    print "$cline";
  }
  
  # Set line count to -1 and release the temporary files
  $line_count = -1;
  close($fh_map);
  close($fh_cache);
}

=back

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

# Module ends with expression that evaluates to true
#
1;
