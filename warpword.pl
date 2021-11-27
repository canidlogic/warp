#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Warp modules
use Warp::Reader;
use Warp::Writer;

=head1 NAME

warpword.pl - Split linguistic content words from punctuation, numbers,
and symbols within a WEFT file.

=head1 SYNOPSIS

  warpword.pl < input.weft > output.weft

=head1 DESCRIPTION

This script reads WEFT input, transforms it, and outputs the transformed
WEFT results.  Content words are split if necessary so that actual
written words from a language are in separate content words from
punctuation, numbers, and symbols.  This makes later processes that
should only operate on actual written words more accurate.

In the output WEFT, content words that represent actual linguistic
content and content words that represent punctuation and other such
content can be distinguished in that actual linguistic content words
contain at least one codepoint in Unicode General Category L (Letter),
though note that Category L also contains ideographs and more than just
letters.

This script does not necessarily work correct for all written languages,
though it should cover most cases.  The following assumptions are made:

=over 4

=item Unicode L (Letter) class is always part of linguistic words.

The main assumption of this script is that any Unicode codepoints that
are in the General Category L (Letter) and that appear within content
words in the input WEFT should always be considered part of actual
written content words in a language.  The Unicode L class also includes
symbols such as ideographs that are not technically letters.

The only situations in which this assumption would not be valid would be
for codepoints in the L class used as punctuation, numerals, or other
symbolic use.  Even in this case, though, it is likely that this
mis-classification will be minor and not have signficant effect on the
results.

=item Each linguistic word begins with an L class codepoint.

Utilities further down the processing pipeline from this script should
be able to distinguish between content words that are actual linguistic
words and content words that are punctuation etc. simply by checking for
the presence of at least one L class codepoint within the content word.
Furthermore, the first codepoint will always be an L class codepoint
within linguistic content words.

The only situation in which this assumption wouldn't hold is for
languages that use punctuation symbols for extra consonants, numeric
digits or superscripted symbols for tone notation, and so forth.  For
some such languages, this script might still work well enough, but
careful consideration needs to be made.

=item Apostrophe and right single quotes have dual function.

Many written languages use the apostrophe (U+0027) and right single
quote (U+2019) marks both as punctuation and as a letter-like symbol,
depending on context.  When used as a letter-like symbol, they tend to
represent a contraction or a glottal stop.  In order to distinguish
between these two cases, this script assumes that apostrophe and right
single quote are functioning as letter-like when they are surrounded by
codepoints in the L (Letter) or M (Combining Mark) classes, and in all
other cases, they should be considered as punctuation.

There are likely to be edge cases involving these characters at the
start or end of words being mis-classified as punctuation rather than
letters, but in most cases this probably won't matter.

=item Linguistic words are sequences of L-, M-class, and apostrophe.

Within content words that appear in the input WEFT file, this script
will combine consecutive codepoints that are of L-class, M-class,
apostrophe, and right single quote into linguistic content words.
However, apostrophe and right single quote are only allowed when they
are functioning as letter-like symbols (see the previous assumption).
Everything else is considered to be non-linguistic content.

=back

=cut

# ==================
# Program entrypoint
# ==================

# Make sure no program arguments
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Read and parse WEFT input
#
warp_accept();

# Process each line
for(my $i = 1; $i <= warp_count(); $i++) {
  
  # Get an array of substrings for the line
  my @pl = warp_read();
  
  # We need to process any content words, which are at indices 1,3,5
  # and so forth; process in reverse order within the line so that
  # substitutions will not affect earlier index positions
  for(my $j = $#pl - 1; $j >= 1; $j = $j - 2) {
    
    # Get the current content word
    my $cw = $pl[$j];
    
    # Make sure the content word does not have any noncharacters from
    # the range [U+FDD0, U+FDD1] so that we can safely use those as
    # markers
    (not ($cw =~ /[\x{fdd0}-\x{fdd1}]/u)) or
      die "Input content word '$cw' contains noncharacters, stopped";
    
    # Replace any apostrophes that occur between two L- or M-class
    # codepoints with U+FDD0 noncharacter, and replace any right single
    # quotes that occur between two L- or M-class codepoints with U+FDD1
    # noncharacter, so that these two special codepoints represent the
    # apostrophe and right single quote in their letter-like use context
    $cw =~ s/([\pL\pM])'([\pL\pM])/$1\x{fdd0}$2/ug;
    $cw =~ s/([\pL\pM])\x{2019}([\pL\pM])/$1\x{fdd1}$2/ug;
    
    # Define an array that will hold the split elements that should
    # replace this content word
    my @plx;
    
    # Digest the content word
    while (length $cw > 0) {
      
      # Add any non-letter codepoints at the start of the content word
      # to the replacement array as-is, since linguistic words must
      # start with an L-class codepoint; prefix an empty array element
      # standing for the non-gap within this content word if the target
      # array is not empty
      if ($cw =~ /^([^\pL]+)/u) {
        my $prefix = $1;
        if ($#plx >= 0) {
          push @plx, ('');
        }
        push @plx, ($prefix);
        if (length $prefix < length $cw) {
          $cw = substr($cw, length $prefix);
        } else {
          $cw = '';
        }
      }
      
      # If content word is now empty, done with loop
      if (length $cw < 1) {
        last;
      }
      
      # Get the sequence of letters, combining marks, and apostrophes
      # and right single quotes that are letter-like function (which we
      # transformed to U+FDD0 and U+FDD1 earlier) at the start of the
      # content word
      $cw =~ /^([\pL\pM\x{fdd0}\x{fdd1}]+)/u;
      my $aw = $1;
      if (length $aw < length $cw) {
        $cw = substr($cw, length $aw);
      } else {
        $cw = '';
      }
      
      # Add the linguistic word to the transformed array, but prefix an
      # empty string representing the non-gap between the last content
      # word if the transformed array is not empty
      if ($#plx >= 0) {
        push @plx, ('');
      }
      push @plx, ($aw);
    }
    
    # Transformed array should have at least one element
    ($#plx >= 0) or die "Unexpected, stopped";
    
    # Go through the transformed array and replace U+FDD0 with an
    # apostrophe and U+FDD1 with a right single quote
    for(my $k = 0; $k <= $#plx; $k++) {
      $plx[$k] =~ s/\x{fdd0}/'/ug;
      $plx[$k] =~ s/\x{fdd1}/\x{2019}/ug;
    }
    
    # Splice the transformed array to replace the original array element
    splice @pl, $j, 1, @plx;
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
