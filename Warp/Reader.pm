package Warp::Reader;
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";
use parent qw(Exporter);

# Core modules
use File::Temp qw/ tempfile /;

# Symbols to export from this module
#
our @EXPORT = qw(
                warp_accept
                warp_count
                warp_read);

=head1 NAME

Warp::Reader - Module for reading and moving through WEFT input.

=head1 SYNOPSIS

  use Warp::Reader;
  
  # Read and parse WEFT input
  warp_accept();
  
  # Process each line
  for(my $i = 1; $i <= warp_count(); $i++) {
    
    # Get an array of substrings for the line
    my @pl = warp_read();
    
    # Process the parsed line
    ...
  }

=head1 DESCRIPTION

The C<Warp::Reader> module is intended for Warp utilities of the
I<filter> and I<target> types, which accept a WEFT file on standard
input.  See the C<README.md> file for further information about the Warp
utility architecture.

=cut

# =================
# Local module data
# =================

# The total number of input lines, or -1 if warp_accept() has not been
# called yet.
#
# If it doesn't have the special value -1, it must be an integer greater
# than zero.
#
my $line_count = -1;

# The total number of input lines that have been read with warp_read().
#
my $read_count = 0;

# The handle to the temporary file storing the Warp Map.
#
# Only defined if $line_count is greater than zero AND $read_count is
# less than $line_count.
#
# After the Warp Map is read into this temporary file, the temporary
# file is rewound.  The current position is therefore always on the next
# line (record) to read.
#
my $fh_map;

=head1 METHODS

=over 4

=item B<warp_accept()>

Parse the WEFT input and prepare to read parsed input lines.  This
function must be called before C<warp_count()> and C<warp_read()> can be
used.  Croaks on error.

Clients should not directly read from standard input if they use this
function, so that this module can see the entire standard input stream.
This function may not be called more than once.

=cut

sub warp_accept {
  # Should have exactly zero arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";
  
  # Check state
  ($line_count == -1) or die "Can only use warp_accept() once, stopped";
  
  # First off, set standard input to use UTF-8
  binmode(STDIN, ":encoding(utf8)") or
    die "Failed to change standard input to UTF-8, stopped";
  
  # First line of input needs to be the %WEFT; signature
  my $sig_line = <STDIN>;
  
  ((defined $sig_line) and ($sig_line =~ /^%WEFT;[ \t]*(?:\r\n|\n)?$/u))
    or die "Failed to read WEFT signature, stopped";
  
  # Second line of input needs to be a declaration line containing an
  # integer count of the number of lines in the map file and an integer
  # count of the number of lines in the packaged input file
  my $dline = <STDIN>;
  my $map_lines;
  my $pin_lines;
  
  (defined $dline) or
    die "Failed to read declaration line in WEFT file, stopped";
  
  if ($dline =~ /^([0-9]+),([0-9]+)[ \t]*(?:\r\n|\n)?$/u) {
    $map_lines = int($1);
    $pin_lines = int($2);
  
  } else {
    die "Failed to parse declaration line in WEFT file, stopped";
  }
  
  # Check that we have at least one line in the map file and at least
  # one line in the packaged input file
  ($map_lines > 0) or
    die "Packaged WEFT map file may not be empty, stopped";
  ($pin_lines > 0) or
    die "Packaged WEFT input file may not be empty, stopped";
  
  # Open a temporary file that will store the Warp Map
  $fh_map = tempfile();
  (defined $fh_map) or die "Failed to create temporary file, stopped";
  
  # Copy all the Warp Map records into the temporary file, checking
  # along the way that each line has the proper format, that the first
  # record is NL, that the last record is EOF, that all other records
  # are either NL or W; also, count the total number of NL records that
  # are encountered
  my $nl_count = 0;
  for(my $i = 1; $i <= $map_lines; $i++) {
    
    # Read a line from the packaged map file
    my $mline = <STDIN>;
    (defined $mline) or
      die "Failed to read line $i from the packaged map file, stopped";
    
    # Determine the type of line, and update NL record count
    if ($mline =~ /^\+[0-9]+,[0-9]+[ \t]*(?:\r\n|\n)?$/u) {
      # NL record, make sure it's not the last record
      ($i < $map_lines) or
        die "Last record in packaged map file must be EOF, stopped";
      
      # Increase the count of NL records
      $nl_count++;
      
    } elsif ($mline =~ /^\.[0-9]+,[0-9]+[ \t]*(?:\r\n|\n)?$/u) {
      # W record, make sure it's not the first record
      ($i > 1) or
        die "First record in packaged map file must be NL, stopped";
      
      # Make sure it's not the last record
      ($i < $map_lines) or
        die "Last record in packaged map file must be EOF, stopped";
      
    } elsif ($mline =~ /^\$0+,0+[ \t]*(?:\r\n|\n)?$/u) {
      # EOF record, make sure it's the last record
      ($i == $map_lines) or
        die "EOF record may only be last in packaged map file, stopped";
      
    } else {
      # Unknown record type
      die "Line $i in packaged map file has invalid format, stopped";
    }
    
    # Write the line to the temporary file
    print {$fh_map} "$mline";
  }
  
  # Make sure that the number of NL records in the map file matches the
  # number of lines in the input file
  ($nl_count == $pin_lines) or
    die "Count of lines in packaged map mismatches input, stopped";
  
  # Rewind the temporary file
  seek($fh_map, 0, 0);
  
  # Set the rest of the module state
  $line_count = $pin_lines;
  $read_count = 0;
}

=item B<warp_count()>

Return the total number of input lines that are present in the input
WEFT file.  There will always be at least one line, and the value will
always be an integer.

This function may only be used after C<warp_accept()> has been called.

=cut

sub warp_count {
  # Should have exactly zero arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";
  
  # Check state
  ($line_count > 0) or die "Forgot to call warp_accept(), stopped";
  
  # Return the count
  return $line_count;
}

=item B<warp_read()>

Parse the next input line from the WEFT input file as an array of
substrings.

You must call C<warp_accept()> before using this function.  You should
call this reading function exactly once for each input line.  Use the
C<warp_count()> function to determine how many input lines there are.
Internal state will automatically be cleaned up when the last input line
is read.  Croaks on error, including if this function is called more
times than there are input lines.

The return value is an array of one or more strings.  When all the
strings are concatenated, the result contains all the Unicode
codepoints in the line I<excluding the line break>.

If there is exactly one string in the return array, it means there are
no content words in the line to process.  In this case, the lone string
contains all codepoints in the line (excluding the line break), none of
which should be transformed by Warp utilities.  The string may be empty
if the line is empty.

Otherwise, there are C<(2*N + 1)> strings in the return array, where
C<N> is the total number of content words on the line.  The first string
(index zero) contains all codepoints that occur before the first content
word in the line, and the last string (index C<2*N>) contains all
codepoints that occur after the last content word in the line, excluding
the line break.  Both of these strings may be empty.

For all other strings in the return array, a string with index
C<(2*i + 1)> is the content word with zero-based index C<i> in the
parsed line.  Content words always contain at least one Unicode
codepoint.  On the other hand, a string with index C<2*j> that is
neither the first nor last element of the array contains all the Unicode
codepoints that come between the content words with zero-based indices
C<(j-1)> and C<j>.  Such strings may be empty.

=cut

sub warp_read {
  # Should have exactly zero arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";
  
  # Check state
  ($line_count > 0) or die "Forgot to call warp_accept(), stopped";
  ($read_count < $line_count) or 
    die "Called warp_read() too many times, stopped";
  
  # Gather all Warp Map records for this line into an array of integers;
  # also count the total number of codepoints on the input line (minus
  # the line break) according to the Warp Map
  my @a;
  my $read_more = 1;
  my $code_count = 0;
  while ($read_more) {
    
    # Read the next Warp Map record
    my $wmline = readline($fh_map);
    (defined $wmline) or die "Failed to read Warp Map record, stopped";
    
    # Parse the record into fields
    my $field_type;
    my $field_skip;
    my $field_read;
    
    if ($wmline =~ /^(.)([0-9]+),([0-9]+)[ \t]*(?:\r\n|\n)?$/u) {
      $field_type = "$1";
      $field_skip = int($2);
      $field_read = int($3);
      
    } else {
      die "Failed to parse Warp Map record, stopped";
    }
    
    # If this is the first record we are gathering, make sure it is an
    # NL record; else, make sure it is an NL or W record
    if ($#a == -1) {
      ($field_type eq '+') or die "Warp Map syntax error, stopped";
      
    } else {
      (($field_type eq '+') or ($field_type eq '.')) or
        die "Warp Map syntax error, stopped";
    }
    
    # Update the codepoint count
    $code_count = $code_count + $field_skip + $field_read;
    
    # Always add the skip value to the array
    push @a, ($field_skip);
    
    # Only add the read value to the array if it is non-zero
    if ($field_read > 0) {
      push @a, ($field_read);
    }
    
    # If read value is zero, don't gather any further records
    if ($field_read == 0) {
      $read_more = 0;
    }
  }
  
  # Read the next line of the packaged input file
  my $iline = <STDIN>;
  (defined $iline) or die "Failed to read packaged input line, stopped";
  
  # Strip CR+LF or LF line break if present
  if ($iline =~ /\r\n$/u) {
    # Strip CR+LF
    $iline = substr($iline, 0, -2);
    
  } elsif ($iline =~ /\n$/u) {
    # Strip LF
    $iline = substr($iline, 0, -1);
  }
  
  # After the line break has now been dropped, make sure the length in
  # codepoints of the input line equals the codepoint count derived from
  # the records in the map file
  ($code_count == length($iline)) or
    die "Warp Map line count mismatches input line length, stopped";
  
  # Replace each integer in the array with the appropriate substring
  # from the input line
  my $sp = 0;
  for(my $j = 0; $j <= $#a; $j++) {
    if ($a[$j] == 0) {
      $a[$j] = '';
    } else {
      my $new_sp = $sp + $a[$j];
      $a[$j] = substr($iline, $sp, $a[$j]);
      $sp = $new_sp;
    }
  }
  
  # Increase read count
  $read_count++;
  
  # If this was the last line, read the final EOF record from the Map
  # file
  if ($read_count >= $line_count) {
    my $eof_line = readline($fh_map);
    (defined $eof_line) or die "Failed to read EOF record, stopped";
    ($eof_line =~ /^\$0+,0+[ \t]*(?:\r\n|\n)?$/u) or
      die "Missing valid EOF record, stopped";
  }
  
  # If this was the last line, we can now close the temporary file
  if ($read_count >= $line_count) {
    close($fh_map);
  }
  
  # Return the parsed substring array
  return @a;
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
