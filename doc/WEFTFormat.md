# WEFT format

Warp Encapsulation Format Text (WEFT) is a simple file format for storing an input text file together with a Warp Map.  This allows Warp tools to be easily pipelined together by connecting the WEFT output of one Warp tool to the WEFT input of another Warp tool.

## Basic format

WEFT files are plain-text files.  They always use UTF-8 encoding.  Supplementary characters (Unicode codepoints with values above U+FFFF) must be properly encoded as a single UTF-8 entity, rather than separately encoding two surrogates in UTF-8.  There must __not__ be a UTF-8 Byte Order Mark (BOM) at the beginning of the WEFT file.

A WEFT file is a sequence of text lines.  Each text line must end with either a LF or with a CR+LF sequence.  CR characters may only be used immediately before an LF to indicate a line break.

## Header

The first line of a WEFT file is just a signature:

    %WEFT;

Whitespace characters (tab and space) are allowed after the semicolon of the signature.  However, there must not be any whitespace at the start of the signature line.

The second line of a WEFT file counts how many lines are in the packaged Warp Map, and how many lines are in the packaged input text file.  For example:

    365,12

This example declares that there are 365 lines in the Warp Map, and 12 lines in the input text file.  Whitespace characters (tab and space) are allowed at the end of this line, but not at the start of it, nor anywhere between the integers and the comma.  The integers must be unsigned sequences of one or more ASCII decimal digits.

## Warp Map

The first line of the packaged Warp Map is always the third line of the WEFT file, coming immediately after the two header lines described in the previous section.  The total number of lines in the Warp Map was declared in the header.  Each of these Warp Map lines must end with a line break (LF or CR+LF).

The Warp Map indicates where the textual content is within the packaged input file, excluding line breaks, whitespace, and any kind of markup or container tags.  The Warp Map makes Warp utilities independent of the specific kind of text or markup file they are operating on.  To add support for another kind of text or markup file, one must simply create a utility that generates a Warp Map for it and packages the input file together with the generated Warp Map within a WEFT file.

Each line of the Warp Map represents a record.  Each record has the same format:

1. One ASCII non-alphanumeric symbol
2. Sequence of one or more ASCII digits
3. One ASCII comma `,`
4. Sequence of one or more ASCII digits
5. Optionally, spaces and/or tabs at the end of the line

The symbol at the start of the line indicates the record type.  There are three types of records:

- `+` Next Line (NL) record
- `.` Word (W) record
- `$` End Of File (EOF) record

For the EOF record, both sequences of ASCII digits must decode to integer values of zero.  Neither integer field has any meaning for EOF records.

For NL and W records, the first sequence of ASCII digits decodes to an integer _skip_ value, and the second sequence of ASCII digits decodes to an integer _read_ value.  Skip values count Unicode codepoints that are _not_ part of content words, while read values indicate the lengths in codepoints of content words.

Skip values may have any unsigned integer value of zero or greater.  Read values must always be greater than zero, except in the last record of a line, where they must be zero.  NL and W records that have a read value of zero therefore always correspond to the end of a line in the input file.

### Encoding the Warp Map

Each line of the packaged input text file is encoded into a sequence of one or more Warp Map records.  After the last input line has been encoded, an EOF record is written to finish the Warp Map.

The first Warp Map record for an input line is always an NL record, and any subsequent records for the line are always W records.  The total number of records for each input line is always one greater than the total number of content words in the line.

If there are no content words in an input line, a single NL record is written that has the total number of codepoints in the line as the skip value and zero as the read value.

Otherwise, the skip value of the NL record will be number of codepoints in the input line prior to the first content word, and the read value of the NL record will be the number of codepoints in the first content word.  For any additional content words after the first, W records are added for each word.  Set the skip value of each W record to the number of codepoints between the previous content word and the start of the new content word, and set the read value of each W record to the number of codepoints in the new content word.  After all content words have been encoded this way, one more W record is written that has a skip value containing the number of codepoints remaining on the line after the last content word, and a read value of zero.

Unicode codepoints corresponding to the LF or the CR+LF line break are never included within the codepoint counts that are encoded in the Warp Map.

Once all input lines have been encoded in the Warp Map in this fashion, an EOF record is written to indicate the end of the Warp map file.

The specific definition of what part of the input line counts as a content word is intentionally not defined here, except that content words must each have at least Unicode codepoint.  This allows there to be different Warp Map encoders for different types of files.  For example, a plain-text Warp Map encoder might consider everything in the file that is not whitespace to be part of content words, while an HTML Warp Map encoder might exclude whitespace as well as markup tags.

### Decoding the Warp Map

The content words within the packaged input file can be identified by decoding the packaged Warp Map.  This allows Warp utilities to transform content words within any kind of plain-text or markup file, without knowing any of the specifics of how the format is structured.

Each line of the packaged input file is split into a sequence of `(2*N + 1)` substrings, where N is the total number of content words in the line.  If the line has no content words, there will be one substring.  If the line has one content word, there will be three substrings.  If the line has two content words, there will be five substrings, and so forth.

When an input line is decoded into a single substring, it means there are no content words on that line, and the entire content of the line is contained in that single substring.  The substring may be empty if the line is empty.

Otherwise, the second, fourth, sixth, and all even-number substrings are content words.  None of these content word substrings may be empty.  The first substring contains everything in the line before the first content word and the last substring contains everything in the line after the last content word.  Both first and last substrings may be empty.  All other odd-number substrings contain the codepoints that come between the content words, and all such substrings may be empty.

To use the Warp Map to decode an array of substrings from a input line, do the following.  First, gather records from the Warp Map until a record is found that has a read value of zero, which marks the last record in the line.  The first gathered record must be an NL record, and any subsequent gathered records must be W records.  The sum of all skip and read counts of all records gathered for the line must be exactly equal to the number of codepoints in the line (excluding any LF or CR+LF line break codepoints).

Next, convert the sequence of gathered records into a sequence of integers.  The first integer is the skip count of the first record, the second integer is the read count of the first record, the third integer is the skip count of the second record, the fourth integer is the read count of the second record, and so forth.  However, do _not_ include the zero-valued read count of the last record in this sequence of integers.

The sequence of integers can then be converted into the substring array by reading substrings sequentially from the input line.  Each integer value in the sequence indicates how many codepoints should be in the corresponding substring.

## Packaged input

The first line of the packaged input text file occurs immediately after the last line of the packaged Warp Map.  The total number of lines of packaged input equals the number of input file lines declared in the WEFT header.  Each of these lines must end with an LF or CR+LF line break, including the last line.

No UTF-8 Byte Order Mark (BOM) is allowed at the start of the packaged input file.  If a BOM was present at the start of the original input file, it must be dropped before the input file is packaged into WEFT.

Any data that occurs in the WEFT file after the last line of the packaged input file will be ignored by WEFT decoders.

The records in the packaged Warp Map must correspond to a number of input lines equal to the number of lines in the packaged input file.  Furthermore, the total count of codepoints within each line of the packaged input file (excluding the LF or CR+LF line break) must equal the total number of codepoints counted in the Warp Map records for the line.  Otherwise, the Warp Map is out of sync with the input file, and the WEFT file is incorrect.

### Example WEFT file

Consider the following input file:

    <p>The quick brown <i>fox</i><br/>
    jumps over the <b>lazy</b> dog.</p>

Suppose we want to exclude the HTML tags in the Warp Map.  The corresponding Warp Map file would then be as follows:

    +3,3
    .1,5
    .1,5
    .4,3
    .9,0
    +0,5
    .1,4
    .1,3
    .4,4
    .5,4
    .4,0
    $0,0

The following anotations show which content word each record selects:

    +3,3   -> The
    .1,5   -> quick
    .1,5   -> brown
    .4,3   -> fox
    .9,0
    +0,5   -> jumps
    .1,4   -> over
    .1,3   -> the
    .4,4   -> lazy
    .5,4   -> dog.
    .4,0
    $0,0

The resulting WEFT file is then as follows:

    %WEFT;
    12,2
    +3,3
    .1,5
    .1,5
    .4,3
    .9,0
    +0,5
    .1,4
    .1,3
    .4,4
    .5,4
    .4,0
    $0,0
    <p>The quick brown <i>fox</i><br/>
    jumps over the <b>lazy</b> dog.</p>

Note that the last line in the WEFT file is _required_ to have a line break at the end of it.
