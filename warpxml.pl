#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Core modules
use Compress::Zlib;
use MIME::Base64;

# Warp modules
use Warp::Writer;

=head1 NAME

warpxml.pl - Package XML or HTML in a Warp Encapsulation Text Format
(WEFT) package that can be processed with Warp tools.

=head1 SYNOPSIS

  warpxml.pl < input.xml > output.weft
  
  warpxml.pl -begin tag < input.xml.fragment > output.weft

=head1 DESCRIPTION

This script reads an XML or HTML file or fragment from standard input.
It writes a WEFT file to standard output that includes the given input
lines as well as a Warp map that indicates where the content words are
located within the HTML or XML.

=head2 Handling fragments

By default, the script assumes that at the start of input we are not
inside any kind of markup.  This is appropriate if you are passing a
whole HTML or XML file to input, or if you are passing a fragment that
does not begin in the middle of some kind of markup tag.

(By "inside a markup tag" we mean actually inside the angle brackets.
This script does not parse the XML DOM, so it does not matter whether
or not the start of input is logically encapsulated within some
element.)

You can also tell this script to assume at the beginning of input that
it is in some specific location in parsing the input file.  This is
appropriate if you are processing a fragment that does not begin cleanly
outside of any markup.  However, you should never need to use this
feature on whole HTML or XML files or on fragments that begin cleanly.

To tell the script to begin in some specific location, add a `-begin`
parameter followed by a parameter describing the location to begin at.
The following table shows the location codes and their meanings:

   Location code |                       Meaning
  ===============+======================================================
       char      | (Default) Not inside any markup tag
       tag       | Inside a <> tag, but not in an attribute value
    tag-att-sq   | Inside a '' attribute value after the opening quote
    tag-att-dq   | Inside a "" attribute value after the opening quote
      comment    | Inside a <!-- --> comment
       CDATA     | Inside a <![CDATA[ ]]> section
      doctype    | Inside a <!DOCTYPE>, but not in an attribute value
  doctype-att-sq | Inside a '' attribute in <!DOCTYPE>, after the quote
  doctype-att-dq | Inside a "" attribute in <!DOCTYPE>, after the quote
        pi       | Inside a <? ?> processing instruction
     xml-decl    | Inside a <?xml ?> declaration

The location at the end of input does not matter and does not need to be
declared.

=head2 XML/HTML parsing notes

This script includes its own XML/HTML parser.  However, this is not a
full-blown XML or HTML parser.  Instead, it only includes features
needed for WEFT packaging and handling entity references in character
data.  In particular, just because an XML or HTML file passes through
this script without complaint does B<not> mean that the XML or HTML is
valid.

The input MUST be in UTF-8.  (US-ASCII files are also OK, because they
are a strict subset of UTF-8.)  Line break style may be either LF or
CR+LF.  An optional UTF-8 byte order mark (BOM) is allowed at the
beginning of input, but it is not copied into the WEFT file and it is
not considered to be part of any content word.  This script does not
parse any metadata within the file that marks the text encoding used, so
you are required to use UTF-8 or US-ASCII.

To determine where content words are, this script only considers raw
character data, excluding all markup.  Markup includes all tags,
attribute values within those tags, comments, CDATA sections, document
type declarations, XML declarations, and processing instructions.  Using
the location codes defined in the previous section, content words will
only be drawn from the C<char> location.

This script will consider, within the C<char> location, content words to
be sequences of one or more consecutive codepoints that are not ASCII
space, ASCII tab, or the line break characters LF and CR.  This script
will decode entities as much as possible and replace them with their
Unicode equivalents so that Warp tools do not need to handle complex
entity references.  The only entity references that will appear within
content words are the following:

   Entity reference | Meaning
  ==================+=========
        &amp;       |    &
        &lt;        |    <
        &gt;        |    >

These escapes are necessary to prevent ambiguity with mark-up.  The
ampersand, left angle bracket, and right angle bracket are I<always>
encoded with the entity references shown above within content words.

=head2 Entity reference handling

This script has special support for entity references that may be found
in both HTML and XML files.  There are three types of entity reference.
A I<named entity reference> begins with an ampersand, then has a
predefined name, and finishes with a semicolon.  A I<decimal entity
reference> begins with an ampersand followed by a number sign followed
by a sequence of one or more decimal digits followed by a semicolon.  A
I<hex entity reference> begins with an ampersand followed by a number
sign followed by a letter C<x> followed by a sequence of one or more
base-16 digits followed by a semicolon.

For named entity references, this script supports the full range of
predefined names defined by the HTML5 specification.  Note that this
range is far more comprehensive than the tiny subset mandated by the
XML specification.  Named entity references almost always decode to a
single Unicode codepoint, but some entity references decode to a
sequence of more than one codepoint.

Decimal and hex entity references always decode to a single Unicode
codepoint with a value matching the numeric value given in the entity
escape code.

All entities will first be replaced by their corresponding Unicode
codepoint(s) by this script.  Then, any "unsafe" codepoints in the
resulting decoded string will be re-encoded as entities.  The following
table shows all possible unsafe codepoints and how they are re-encoded:

   Unsafe character | Re-encoded entity
  ==================+====================
          &         |       &amp;
          <         |       &lt;
          >         |       &gt;
          '         |       &apos;
          "         |       &quot;

All of the re-encoded entities given in the table above are supported by
the XML specification.  Therefore, even if the input file contains
entity references that are not supported by XML, the output from this
script will only include supported XML entities.

The single quote character is only considered unsafe in single-quoted
attributes and is left alone everywhere else.

The double quote character is only considered unsafe in double-quoted
attributes and is left alone everywhere else.

=head2 Entity locations

HTML/XML entities only occur in certain types of locations within the
HTML/XML file.  Using the location codes defined in an earlier section,
entities are never present in locations C<comment> C<CDATA> C<doctype>
C<doctype-att-sq> C<doctype-att-dq> C<pi> or C<xml-decl>.  If an
ampersand occurs within any of these locations, it is assumed to be a
literal ampersand by this script and it is B<not> interpreted as an
entity.

For the C<tag> location, this script will make sure that there is no
ampersand in this section, causing an error if there is.  (This location
does not include quoted attributes within the tag.)

For the remaining C<char> C<tag-att-sq> and C<tag-att-dq> locations,
entities are allowed and are processed by this script in the manner
described in the previous section.  The only difference between the
three section types is the set of characters considered "unsafe."  For
all three sections, the ampersand and angle brackets are unsafe.  For
quoted attributes, the quote character is also considered unsafe.

=head2 Output codepoint range

This script will make sure that everything included in the packaged
input in the output WEFT file will obey the XML character range and
avoid compatibility ranges defined in the XML specification.

Specifically, this script will allow any Unicode codepoint in range
[U+0000, U+10FFFF] B<except> for the following:

=over 4

=item C0 and C1 non-printing control codes

This includes all codepoints in range [U+0000, U+001F] and in range
[U+007F, U+009F] except for HT (U+0009), CR (U+000D), LF (U+000A), and
NEL (U+0085).

=item Surrogate codepoints

This includes all codepoints in range [U+D800, U+DFFF].  These are
unnecessary in UTF-8.  Use the supplemental codepoint directly instead.

=item Noncharacters

These are permanently undefined Unicode codepoints.  This includes the
range [U+FDD0, U+FDEF], the characters U+FFFE and U+FFFF, and any
supplemental character for which the sixteen least significant bits are
either FFFE or FFFF.

The U+FFFE codepoint is allowed, however, at the very start of input to
serve as an optional UTF-8 Byte Order Mark (BOM).  This script will
silently filter this codepoint out.

=back

=cut

# ============================
# Named entity reference table
# ============================

# The following string is the entities.txt in the entity directory, run
# through gzip, and then through base64.  See the README.md file in that
# directory for further information.
#
# Immediately after this declaration, we decode the base64 to binary and
# then decompress it so that later code can access the string just as it
# originally was in the entities.txt file.
#
my $ent_table = <<'EOD';
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
EOD

# Decode the base-64 into binary
#
$ent_table = decode_base64($ent_table);

# Decompress the binary back into the original text file
#
$ent_table = Compress::Zlib::memGunzip($ent_table) or
  die "Failed to decompress entity table, stopped";

# ==========
# Local data
# ==========

# The entities table decoded into a hash structure.
#
# entities_init is zero if this hash hasn't been initialized yet.  Use
# the entities_init() function to initialize this hash if not already
# initialized.
#
# Once initialized, the keys in the entities hash will be the name of
# the entity, excluding the opening ampersand and the closing semicolon.
# The values will be references to arrays that store a sequence of one
# or more integers, defining which Unicode codepoint(s) the named entity
# decodes to.
#
my $entities_init = 0;
my %entities;

# ===============
# Local functions
# ===============

# Initialize the %entities variable if not already initialized.
#
sub entity_init {
  # Should have exactly zero arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";
  
  # Only proceed if not yet initialized
  unless ($entities_init) {
    
    # Match all records in the embedded entity table file and add them
    # to the entities hash
    while ($ent_table =~ /([A-Za-z0-9]+)=([0-9A-Fa-f,]+)/ug) {
      
      # Get the entity name and the codepoint sequence
      my $ent_name = $1;
      my @codeps   = split /,/, $2;
      
      # Decode each codepoint into a numeric value from base-16
      for(my $i = 0; $i <= $#codeps; $i++) {
        $codeps[$i] = hex($codeps[$i]);
      }
      
      # Add the record to the hash
      $entities{$ent_name} = \@codeps;
    }
    
    # Set the initialization flag
    $entities_init = 1;
  }
}

# Check whether a given numeric codepoint value is valid within an XML
# file.
#
# All Unicode codepoints in range [0, 0x10ffff] are valid EXCEPT:
#
#   - Control codes below 0x20 that are not HT, CR, or LF
#   - Control codes in range [0x7F, 0x9F] that are not NEL
#   - Surrogates in range [0xD800, 0xDFFF]
#   - Noncharacters in range [0xFDD0, 0xFDEF]
#   - Noncharacters 0xFFFE and 0xFFFF
#   - Supplemental noncharacters, which are codepoints above 0xFFFF that
#     have 0xFFFE or 0xFFFF as their sixteen least significant bits
#
# Parameters:
#
#   1 : integer - the numeric codepoint value to check
#
# Return:
#
#   1 if codepoint is valid, 0 if not
#
sub valid_codep {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get the argument and set argument type
  my $codep = int(shift);
  
  # Start with valid result
  my $result = 1;
  
  # Fail if outside Unicode range
  unless (($codep >= 0) and ($codep <= 0x10ffff)) {
    $result = 0;
  }
  
  # Fail if disallowed control code
  unless ((($codep >= 0x20) and ($codep <= 0x7e)) or
          ($codep > 0x9f) or
          ($codep == 0x9) or ($codep == 0xa) or ($codep == 0xd) or
          ($codep == 0x85)) {
    $result = 0;
  }
  
  # Fail if surrogate
  if (($codep >= 0xd800) and ($codep <= 0xdfff)) {
    $result = 0;
  }
  
  # Fail if in first non-character range
  if (($codep >= 0xfdd0) and ($codep <= 0xfdef)) {
    $result = 0;
  }
  
  # Fail if last two codepoints in BMP
  if (($codep == 0xfffe) or ($codep == 0xffff)) {
    $result = 0;
  }
  
  # Fail if last two codepoints of any supplemental plane
  if ($codep > 0xffff) {
    my $offs = $codep & 0xffff;
    if (($offs == 0xfffe) or ($offs == 0xffff)) {
      $result = 0;
    }
  }
  
  # Return result
  return $result;
}

# Handle decoding and replacing any entity references within a given
# string.
#
# Croaks on error or if entity references are found in a location they
# are not allowed.
#
# The given location string must have one of the following values:
#
#   char
#   tag
#   tag-att-sq
#   tag-att-dq
#   comment
#   CDATA
#   doctype
#   doctype-att-sq
#   doctype-att-dq
#   pi
#   xml-decl
# 
# For the comment, CDATA, doctype, doctype-att-sq, doctype-att-dq, pi,
# and xml-decl locations, this function just returns the given string
# as-is without any processing.  Entities are not decoded in these
# locations, and the ampersand has no special meaning.
#
# For the tag location, this function simply checks that there is no
# ampersand in the string before returning it as-is.  Entity escapes are
# not allowed in tags, unless they are in a quoted attribute value.
#
# For the tag-att-sq location, tag-att-dq, and char locations, this
# function processes and decodes entities in the manner described below.
# The only difference between the three locations is which characters
# are considered "unsafe", as shown in the following table:
#
#     Location  | Unsafe characters
#   ============+==================
#       char    |     & < >
#    tag-att-sq |     & < > '
#    tag-att-dq |     & < > "
#
# Entity decoding in these three locations begins by parsing the input
# string into a sequence of raw characters and entities.  Raw character
# sequences may not contain any ampersand.  Entities must begin with an
# ampersand, followed by a sequence of one or more ASCII alphanumeric
# characters or # characters, and ending with a semicolon.
#
# The entire input is then transformed into a sequence of raw characters
# without any entities by translating each entity into the codepoint(s)
# it encodes.  For entities that begin with &# followed by a sequence of
# decimal digits and then the semicolon, the decimal digits decode to a
# numeric Unicode codepoint value.  For entities that begin with &#x
# or &#X followed by a sequence of base-16 digits and then the
# semicolon, the base-16 digits decode to a numeric Unicode codepoint
# value.  Numeric entities may never encode surrogate codepoint values
# or other values disallowed by XML.
#
# For all other entities, all the characters between the opening
# ampersand and the closing semicolon must be a case-sensitive match for
# an entity key in the named entity table that was embedded earlier in
# this script.  In this case, the entity maps to the sequence of one or
# more codepoints defined for the entity in that table.
#
# Finally, the transformed raw character sequence is scanned for
# "unsafe" characters.  The unsafe characters vary for the particular
# location, as shown in the table above.  Unsafe characters are replaced
# by an XML named entity as shown below:
#
#    Unsafe character | Replacement entity
#   ==================+====================
#           &         |       &amp;
#           <         |       &lt;
#           >         |       &gt;
#           '         |       &apos;
#           "         |       &quot;
#
# Note that the single-quote in the above table is only replaced when
# in the tag-att-sq location, and the double-quote in the above table is
# only replaced in the tag-att-dq location.
#
# Parameters:
#
#   1 : string - the string value to entity-decode
#
#   2 : string - the location that the given source string is from
#
# Return:
#
#   string - the entity-decoded string value
#
sub entity_decode {
  # Should have exactly two arguments
  ($#_ == 1) or die "Wrong number of arguments, stopped";
  
  # Get the arguments
  my $str = shift;
  my $loc = shift;
  
  # Set argument types
  $str = "$str";
  $loc = "$loc";
  
  # Check the location argument
  (($loc eq "char") or
    ($loc eq "tag") or
    ($loc eq "tag-att-sq") or
    ($loc eq "tag-att-dq") or
    ($loc eq "comment") or
    ($loc eq "CDATA") or
    ($loc eq "doctype") or
    ($loc eq "doctype-att-sq") or
    ($loc eq "doctype-att-dq") or
    ($loc eq "pi") or
    ($loc eq "xml-decl")) or die "Invalid location type, stopped";
  
  # Initialize %entities hash if necessary
  entity_init();
  
  # Begin with an empty result
  my $result = '';
  
  # Handling depends on location type
  if (($loc eq "char") or
        ($loc eq "tag-att-sq") or ($loc eq "tag-att-dq")) {
    
    # For the character location and the single-quoted and double-quoted
    # tag attribute locations, we first need to digest the given string
    # into the result, transferring raw character sequences as-is and
    # decoding entities into their corresponding codepoints
    while (length $str > 0) {
      
      # Transfer any sequence that does not contain ampersand from the
      # beginning of the string to the result
      if ($str =~ /^([^&]+)/u) {
        my $str_prefix = $1;
        $result = $result . $str_prefix;
        if (length $str_prefix < length $str) {
          $str = substr($str, length $str_prefix);
        } else {
          $str = '';
        }
      }
      
      # If the string is now empty, we are done with this loop
      if (length $str < 1) {
        last;
      }
      
      # If we got here, match the entity that is now at the beginning of
      # the string and drop it from the string
      ($str =~ /^&([A-Za-z0-9#]+);/u) or
        die "Invalid entity at start of '$str', stopped";

      my $etext = $1;
      if (length($etext) + 2 < length $str) {
        $str = substr($str, length($etext) + 2);
      } else {
        $str = '';
      }

      # Decode the specific type of entity to get a sequence of one or
      # more codepoints
      my @dca;
      if ($etext =~ /^#x([0-9A-Fa-f]+)$/ui) {
        # Base-16 numeric reference, add single codepoint
        push @dca, (hex($1));
        
      } elsif ($etext =~ /^#([0-9]+)$/u) {
        # Base-10 numeric reference, add single codepoint
        push @dca, (int($1));
        
      } else {
        # Must be a named entity -- check that it exists
        (exists $entities{$etext}) or
          die "Unrecognized named entity '$etext', stopped";
        
        # Copy its codepoint sequence
        push @dca, @{$entities{$etext}};
      }
      
      # Make sure all of the decoded codepoints are supported in XML
      for my $cp (@dca) {
        (valid_codep($cp)) or
          die "Entity '$etext' decodes to invalid codepoint, stopped";
      }
      
      # Append each decoded codepoint to the result string
      for my $cp (@dca) {
        $result = $result . chr($cp);
      }
    }
    
    # Escape characters that are always unsafe
    $result =~ s/&/&amp;/gu;
    $result =~ s/</&lt;/gu;
    $result =~ s/>/&gt;/gu;
    
    # In attributes, also escape the specific quote character
    if ($loc eq "tag-att-sq") {
      $result =~ s/'/&apos;/gu;
    
    } elsif ($loc eq "tag-att-dq") {
      $result =~ s/"/&quot;/gu;
    }
    
  } elsif ($loc eq "tag") {
    # For the tag location outside of attribute values, we just make
    # sure that there is no ampersand and then pass through as-is
    (not ($str =~ /&/u)) or
      die "Ampersand not allowed in tag unless quoted, stopped";
    $result = $str;
    
  } else {
    # For all other location types, we just pass the string through
    # without any processing
    $result = $str;
  }
  
  # Return result;
  return $result;
}

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
my $loc = "char";
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
  
  # Assign the string to a variable that will be broken down
  # progressively, define an array that will hold substrings for this
  # line, and define a "skip buffer" that will buffer codepoints that
  # will be skipped
  my $str = $_;
  my @a;
  my $skip = '';
  
  # Keep digesting the string until it is gone
  while (length $str > 0) {
  
    # Parsing depends on which location we are at
    if ($loc eq "char") {
      # We are in raw character data (the initial state) -- first we
      # want to extract a whole block up to but excluding the first < in
      # the remaining data if there is one, otherwise all the data if
      # there is no < block
      my $block;
      if ($str =~ /</ug) {
        # Found a <, determine block length excluding it
        my $block_len = pos($str) - 1;

        # Get the block, which might be empty
        if ($block_len > 0) {
          $block = substr($str, 0, $block_len);
        } else {
          $block = '';
        }

        # Remove the block from the remaining string data
        if ($block_len < length $str) {
          $str = substr($str, $block_len);
        } else {
          # Remaining data should at least include the <
          die "Unexpected, stop";
        }
      
      } else {
        # There is no <, so block is everything left in the string
        $block = $str;
        $str = '';
      }
      
      # Next step is to entity-decode the block
      $block = entity_decode($block, $loc);

      # Check if the whole block is whitespace
      if ($block =~ /^[ \t]*$/u) {
        # Whole block is whitespace, so just add it all to the skip
        # buffer
        $skip = $skip . $block;
        
      } else {
        # At least one non-whitespace character in block, so first get
        # what comes after the last non-whitespace
        $block =~ /([ \t]*)$/u;
        my $block_suffix = $1;
        
        # Strip the block suffix if it is not empty
        if (length $block_suffix > 0) {
          $block = substr($block, 0, -(length $block_suffix));
        }

        # Parse the rest of the block as pairs of whitespace runs and
        # non-whitespace sequences, and add them to the array
        while ($block =~ /([ \t]*)([^ \t]+)/gu) {
          # Add the opening whitespace to the skip buffer
          $skip = $skip . $1;
          
          # Push the skip buffer to the array, followed by the content
          # word
          push @a, ($skip, $2);
          
          # Clear the skip buffer
          $skip = '';
        }
        
        # Now add the block suffix to the skip buffer
        $skip = $skip . $block_suffix;
      }
      
      # If the remaining string data is not empty, we need to figure out
      # what kind of markup block is starting, add the opening marker of
      # that block to the skip buffer, and change the location
      # appropriately; otherwise, leave the location in character data
      if (length $str > 0) {
        
        # Determine what is starting, count the length of the opening
        # marker, and update the location
        my $opener_len;
        
        if ($str =~ /^<\?xml/uig) {
          # XML declaration <?xml ?>
          $opener_len = pos($str);
          $loc = "xml-decl";
          
        } elsif ($str =~ /^<\?/ug) {
          # Processing instruction <? ?>
          $opener_len = pos($str);
          $loc = "pi";
          
        } elsif ($str =~ /^<!DOCTYPE/uig) {
          # Document type declaration <!DOCTYPE >
          $opener_len = pos($str);
          $loc = "doctype";
          
        } elsif ($str =~ /^<!\[CDATA\[/uig) {
          # CDATA block <![CDATA[ ]]>
          $opener_len = pos($str);
          $loc = "CDATA";
          
        } elsif ($str =~ /^<!--/ug) {
          # Comment <!-- -->
          $opener_len = pos($str);
          $loc = "comment";
          
        } elsif ($str =~ /^</ug) {
          # Tag < >
          $opener_len = pos($str);
          $loc = "tag";
          
        } else {
          # Shouldn't happen
          die "Unexpected, stopped";
        }
        
        # Add the opener to the skip buffer
        $skip = $skip . substr($str, 0, $opener_len);
        if (length $str > $opener_len) {
          $str = substr($str, $opener_len);
        } else {
          $str = '';
        }
      }
     
    } elsif ($loc eq "tag") {
      # We are in a start, end, or empty-element tag, but not within any
      # attribute value; the opening < is NOT included in this location;
      # look for the start of a quoted attribute or the end of the tag
      # within this line
      if ($str =~ /'|"|>/ug) {
        # There is a termination character -- get everything on the line
        # up to *and including* this termination character
        my $t_len = pos($str);
        my $t_str = substr($str, 0, $t_len);
        if ($t_len < length $str) {
          $str = substr($str, $t_len);
        } else {
          $str = '';
        }
        
        # The last character of the tag text determines what the
        # location should be updated to
        if ($t_str =~ /'$/u) {
          # Single quote, so change to single-quoted attribute
          $loc = "tag-att-sq";
          
        } elsif ($t_str =~ /"$/u) {
          # Double quote, so change to double-quoted attribute
          $loc = "tag-att-dq";
          
        } elsif ($t_str =~ />$/u) {
          # End of tag, so change back to raw characters
          $loc = "char";
          
        } else {
          # Shouldn't happen
          die "Unexpected, stopped";
        }
        
        # Entity-decode the tag text (except for the last character) and
        # add it to skip buffer
        $t_str = entity_decode(substr($t_str, 0, -1), $loc)
                  . substr($t_str, -1);
        $skip = $skip . $t_str;
      
      } else {
        # The whole rest of the line is part of the tag and contains no
        # attribute values, so first of all entity-decode it
        $str = entity_decode($str, $loc);
        
        # Add the rest of the line to the skip buffer and leave the
        # location the same
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "tag-att-sq") {
      # We are in a single-quoted attribute within a start, end, or
      # empty-element tag; the opening quote is NOT included in this
      # location; look for the end of the single-quoted attribute in
      # this line
      if ($str =~ /'/ug) {
        # Attribute ends, pos stores index of first character after the
        # closing quote; add rest of attribute to the skip buffer after
        # entity-decoding it (except for last character) and change the
        # location back to tag, but outside any enclosed attribute
        my $at_len = pos($str);
        $skip = $skip . entity_decode(
                            substr($str, 0, $at_len - 1), $loc)
                          . substr($str, $at_len - 1, 1);
        if ($at_len < length $str) {
          $str = substr($str, $at_len);
        } else {
          $str = '';
        }
        $loc = "tag";
        
      } else {
        # Single-quoted attribute does not end within this line, so
        # entity-decode it and add the rest to the skip buffer and leave
        # the location the same
        $str = entity_decode($str, $loc);
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "tag-att-dq") {
      # We are in a double-quoted attribute within a start, end, or
      # empty-element tag; the opening quote is NOT included in this
      # location; look for the end of the double-quoted attribute in
      # this line
      if ($str =~ /"/ug) {
        # Attribute ends, pos stores index of first character after the
        # closing quote; add rest of attribute to the skip buffer after
        # entity-decoding it (except for last character) and change the
        # location back to tag, but outside any enclosed attribute
        my $at_len = pos($str);
        $skip = $skip . entity_decode(
                            substr($str, 0, $at_len - 1), $loc)
                          . substr($str, $at_len - 1, 1);
        if ($at_len < length $str) {
          $str = substr($str, $at_len);
        } else {
          $str = '';
        }
        $loc = "tag";
        
      } else {
        # Double-quoted attribute does not end within this line, so
        # entity-decode it and add the rest to the skip buffer and leave
        # the location the same
        $str = entity_decode($str, $loc);
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "comment") {
      # We are in a comment -- look for the end of the comment within
      # this line
      if ($str =~ /-->/ug) {
        # Comment ends, pos stores index of first character after the
        # end-comment marker; add rest of comment to the skip buffer and
        # change the location back to raw character data (comments are
        # not allowed within other markup, per the spec)
        my $cm_len = pos($str);
        $skip = $skip . substr($str, 0, $cm_len);
        if ($cm_len < length $str) {
          $str = substr($str, $cm_len);
        } else {
          $str = '';
        }
        $loc = "char";
        
      } else {
        # Comment does not end within this line, so transfer everything
        # remaining in the string to the skip buffer and leave the
        # location the same
        $skip = $skip . $str;
        $str = '';
      }
    
    } elsif ($loc eq "CDATA") {
      # We are in a CDATA section -- look for the end of the CDATA
      # within this line
      if ($str =~ /\]\]>/ug) {
        # CDATA ends, pos stores index of first character after the end
        # marker; add rest of CDATA to the skip buffer and change the
        # location back to raw character data
        my $cd_len = pos($str);
        $skip = $skip . substr($str, 0, $cd_len);
        if ($cd_len < length $str) {
          $str = substr($str, $cd_len);
        } else {
          $str = '';
        }
        $loc = "char";
        
      } else {
        # CDATA does not end within this line, so transfer everything
        # remaining in the string to the skip buffer and leave the
        # location the same
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "doctype") {
      # We are in a document type declaration, but outside of any
      # enclosed attribute values; the opening <!DOCTYPE is NOT included
      # in this location; look for the start of a quoted attribute or
      # the end of the document type declaration within this line
      if ($str =~ /'|"|>/ug) {
        # There is a termination character -- get everything on the line
        # up to *and including* this termination character
        my $dt_len = pos($str);
        my $dt_str = substr($str, 0, $dt_len);
        if ($dt_len < length $str) {
          $str = substr($str, $dt_len);
        } else {
          $str = '';
        }
        
        # The last character of the document type text determines what
        # the location should be updated to
        if ($dt_str =~ /'$/u) {
          # Single quote, so change to single-quoted attribute
          $loc = "doctype-att-sq";
          
        } elsif ($dt_str =~ /"$/u) {
          # Double quote, so change to double-quoted attribute
          $loc = "doctype-att-dq";
          
        } elsif ($dt_str =~ />$/u) {
          # End of tag, so change back to raw characters
          $loc = "char";
          
        } else {
          # Shouldn't happen
          die "Unexpected, stopped";
        }
        
        # Entity-decode the document type text (except for last
        # character) and add it to skip buffer
        $dt_str = entity_decode(substr($dt_str, 0, -1), $loc)
                      . substr($dt_str, -1);
        $skip = $skip . $dt_str;
      
      } else {
        # The whole rest of the line is part of the document type
        # declaration and contains no attribute values, so first of all
        # entity-decode it
        $str = entity_decode($str, $loc);
        
        # Add the rest of the line to the skip buffer and leave the
        # location the same
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "doctype-att-sq") {
      # We are in a single-quoted attribute of a document type
      # declaration; the opening quote is NOT included in this location;
      # look for the end of the single-quoted attribute in this line
      if ($str =~ /'/ug) {
        # Attribute ends, pos stores index of first character after the
        # closing quote; add rest of attribute to the skip buffer and
        # change the location back to document type declaration, but
        # outside any enclosed attribute (entities are not decoded
        # within document type declaration attributes)
        my $at_len = pos($str);
        $skip = $skip . substr($str, 0, $at_len);
        if ($at_len < length $str) {
          $str = substr($str, $at_len);
        } else {
          $str = '';
        }
        $loc = "doctype";
        
      } else {
        # Single-quoted attribute of document type declaration does not
        # end within this line, so add the rest to the skip buffer and
        # leave the location the same (entities are not decoded within
        # document type declaration attributes)
        $skip = $skip . $str;
        $str = '';
      }
    
    } elsif ($loc eq "doctype-att-dq") {
      # We are in a double-quoted attribute of a document type
      # declaration; the opening quote is NOT included in this location;
      # look for the end of the double-quoted attribute in this line
      if ($str =~ /"/ug) {
        # Attribute ends, pos stores index of first character after the
        # closing quote; add rest of attribute to the skip buffer and
        # change the location back to document type declaration, but
        # outside any enclosed attribute (entities are not decoded
        # within document type declaration attributes)
        my $at_len = pos($str);
        $skip = $skip . substr($str, 0, $at_len);
        if ($at_len < length $str) {
          $str = substr($str, $at_len);
        } else {
          $str = '';
        }
        $loc = "doctype";
        
      } else {
        # Double-quoted attribute of document type declaration does not
        # end within this line, so add the rest to the skip buffer and
        # leave the location the same (entities are not decoded within
        # document type declaration attributes)
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "pi") {
      # We are in a processing instruction; the opening <? is NOT
      # included in this location; look for the end of the processing
      # instruction in this line
      if ($str =~ /\?>/ug) {
        # Processing instruction ends, pos stores index of first
        # character after the closing; add rest of instruction to the
        # skip buffer and change the location back to raw character
        # (entities are not decoded within processing instructions)
        my $pi_len = pos($str);
        $skip = $skip . substr($str, 0, $pi_len);
        if ($pi_len < length $str) {
          $str = substr($str, $pi_len);
        } else {
          $str = '';
        }
        $loc = "char";
        
      } else {
        # Processing instruction does not end within this line, so add
        # the rest to the skip buffer and leave the location the same
        # (entities are not decoded within processing instructions)
        $skip = $skip . $str;
        $str = '';
      }
      
    } elsif ($loc eq "xml-decl") {
      # We are in an XML declaration; the opening <?xml is NOT
      # included in this location; look for the end of the declaration
      # in this line
      if ($str =~ /\?>/ug) {
        # XML declaration ends, pos stores index of first character
        # after the closing; add rest of the declaration to the skip
        # buffer and change the location back to raw character (entities
        # are not decoded within XML declarations)
        my $xd_len = pos($str);
        $skip = $skip . substr($str, 0, $xd_len);
        if ($xd_len < length $str) {
          $str = substr($str, $xd_len);
        } else {
          $str = '';
        }
        $loc = "char";
        
      } else {
        # XML declaration does not end within this line, so add the rest
        # to the skip buffer and leave the location the same (entities
        # are not decoded within XML declarations)
        $skip = $skip . $str;
        $str = '';
      }
    
    } else {
      # Unrecognized location
      die "Invalid location, stopped";
    }
  }
  
  # Finish the substring array by adding the skip buffer, even if the
  # skip buffer is currently empty
  push @a, ($skip);
  
  # Write the line
  warp_write(@a);
  
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
