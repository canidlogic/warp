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
line break determination.  The following documentation is adapted from
the Uniloom C<org.canid.warp.WarpFile> module.

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
line).  If there is at least one lowercase letter, no uppercase letters
may be present; and if there is at least one uppercase letter, no
lowercase letters may be present.

(The reason for the case restriction is to prevent confusion with
uppercase digraphs at the beginning of words, which might be either
capitalized or all-uppercase.  For example, suppose that the escape
sequence C<;ae> is mapped to lowercase digraph ae and the escape
sequence C<;AE> is mapped to uppercase digraph AE.  Consider then the
three words C<aether> C<Aether> and C<AETHER>.  To convert the first
two letters into a digraph, we would get C<;aether> C<;Aether> and
C<;AETHER>, where the C<;ae> escape should map to the lowercase digraph,
and both C<;Ae> and C<;AE> should map to the uppercase digraph.  Woof
normalizes escapes so that if there is at least one uppercase character,
everything will be uppercase.  This allows all three of the above
examples to work as expected, without oddities such as C<;AEther> or
C<;AeTHER>.)

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

# @@TODO:

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
    
    # Get the current content word
    my $cw = $pl[$j];
    
    # @@TODO:
    
    # Write the transformed content word back into the array
    $pl[$j] = $cw;
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
