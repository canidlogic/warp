#!/usr/bin/env perl
use strict;

# Non-core modules
use JSON::Tiny qw(decode_json);

=head1 NAME

MapEntities.pl - Transform a JSON source file containing named character
references into a character entity decoding table.

=head1 SYNOPSIS

  MapEntities.pl < input.json > output.txt
  
=head1 DESCRIPTION

Given a JSON listing of named character references, produce an index
file that maps named character references to codepoint sequences.

The JSON source file is available from the HTML5 specification.  See the
C<README.md> in this directory for more about the generated character
entity database.

The top-level element in the source JSON must be a JSON object, where
the keys are strings containing a named entity name.  The key strings
include both the opening ampersand and the closing semicolon.

The name within the key string, excluding the opening ampersand and
closing semicolon, must be a sequence of one or more US-ASCII
alphanumeric characters.  Names are case-sensitive.

Keys whose name does not end with a semicolon (which are included in the
source JSON for legacy compatibility) are not included, after being
verified to be a strict alias of a key whose name has the semicolon.

The mapped value of each key in the top-level JSON object must be
another JSON object.  One of its properties must be named C<codepoints>
and its associated value must be a JSON array of one or more integers.
These integers are the codepoints that the named entity maps to.  If
there is more than one, the named entity maps to a sequence of
codepoints.  Supplementary character codepoints must be represented by
a single integer, rather than as a surrogate pair.

The generated map file is in US-ASCII format and has one record per
line.  The line begins with a sequence of one or more US-ASCII
alphanumeric characters that define the name of the entity (case
sensitive).  This name does not include the opening ampersand or closing
semicolon.

After the name comes an equals sign, and then a sequence of one or more
integer codepoint values represented in base-16 with comma separators
between the elements.

No whitespace may be used within record lines, except optionally at the
end of the line.

=cut

# ==================
# Program entrypoint
# ==================

# Make sure there are no program arguments
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# First off, set standard input to use raw binary
#
binmode(STDIN, ":raw") or
  die "Failed to change standard input to binary, stopped";

# Slurp the entire standard input as a byte string
#
undef $/;
my $raw_input = readline(STDIN);
(defined $raw_input) or die "Failed to read input, stopped";

# Decode JSON
#
my $js = decode_json($raw_input);

# Make sure top-level element is a JSON object
#
(ref($js) eq 'HASH') or
  die "Top-level JSON must be object, stopped";

# Get a list of all the keys in the JSON object and sort them
#
my @jsk = sort keys %$js;

# Go through all the keys, and for each corresponding hash value,
# replace the hash value with a reference to an array of integer
# codepoint values, checking the arrays along the way
#
for my $k (@jsk) {
  # Check that value is reference to hash
  (ref($js->{$k}) eq 'HASH') or
    die "JSON map value for $k must be JSON object, stopped";
  
  # Check that the referenced hash has a codepoints property
  (exists $js->{$k}->{'codepoints'}) or
    die "JSON map value for $k missing codepoints property, stopped";
  
  # Check that the codepoints property is an array reference
  (ref($js->{$k}->{'codepoints'}) eq 'ARRAY') or
    die "JSON codepoints property for $k must be an array, stopped";
  
  # Replace the value with the codepoints property
  $js->{$k} = $js->{$k}->{'codepoints'};
  
  # Get length of codepoints array and make sure it is not empty
  my $alen = scalar @{$js->{$k}};
  ($alen > 0) or
    die "Codepoints array for $k may not be empty, stopped";
  
  # Make sure each codepoint is an integer in Unicode codepoint range,
  # excluding surrogates and nul
  for(my $i = 0; $i < $alen; $i++) {
    ($js->{$k}->[$i] =~ /^[0-9]+$/u) or
      die "Codepoints array contains invalid value for $k, stopped";
    
    my $v = int($js->{$k}->[$i]);
    
    (($v > 0) and ($v <= 0x10ffff) and
        (($v < 0xd800) or ($v > 0xdfff))) or die
"Codepoints for $k includes surrogates or out-of-range values, stopped";
        
    $js->{$k}->[$i] = $v;
  }
}

# Go through the key list and build a list of keys that should be
# filtered out
#
my @filter_key;
for my $k (@jsk) {
  
  # If this key does not end in a semicolon, make sure it has an alias
  # with a semicolon that has the same mapping, and then add the key to
  # the filtered key list
  if (not ($k =~ /;$/u)) {
    # Check for alias
    (exists $js->{$k . ';'}) or
      die "Legacy key $k is missing alias, stopped";
    
    # Make sure mapped values have same length
    (scalar @{$js->{$k}} == scalar @{$js->{$k . ';'}}) or
      die "Legacy key $k has incompatible alias, stopped";
    
    # Make sure mapped codepoint values are the same
    for(my $i = 0; $i < scalar @{$js->{$k}}; $i++) {
      ($js->{$k}->[$i] == $js->{$k . ';'}->[$i]) or
        die "Legacy key $k has incompatible alias, stopped";
    }
    
    # Add the legacy key to the filter list
    push @filter_key, ($k);
  }
}

# Drop all filtered keys from the hash and rebuild the sorted key list
#
for my $k (@filter_key) {
  delete $js->{$k};
}
@jsk = sort keys %$js;

# Generate output
#
for my $k (@jsk) {
  
  # Print the key name, without the opening ampersand and closing
  # semicolon, after checking it is a sequence of one or more ASCII
  # alphanumerics
  ($k =~ /^&([A-Za-z0-9]+);$/u) or
    die "Key $k has invalid name, stopped";
  print "$1=";
  
  # Print the codepoints in base-16
  for(my $i = 0; $i < scalar @{$js->{$k}}; $i++) {
    # If not first element, print comma separator
    if ($i > 0) {
      print ",";
    }
    
    # Print the codepoint in base-16
    printf "%x", $js->{$k}->[$i];
  }
  
  # Print the line break
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
