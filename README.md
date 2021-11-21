# Warp

Utilities for mapping words within a text or markup file and performing transformations on those words.

## Warp map file

Before Warp can be used on a text or markup file, a Warp map file must be created.  The Warp map file indicates where the textual content is within the file, excluding line breaks, whitespace, and any kind of markup tags.  Using the Warp map file makes Warp utilities independent of the specific kind of text or markup file they are operating on.  To add support for another kind of text or markup file, one must simply create a utility that generates a Warp map file for it.

A Warp map file is a US-ASCII text file with one record per line.  Blank or empty lines at the end of the map file should be ignored.  Each line has the same format:

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

For NL and W records, the first sequence of ASCII digits decodes to an integer _skip_ value, and the second sequence of ASCII digits decodes to an integer _read_ value.  Skip values count Unicode codepoints that are _not_ part of content words, while read values indicate the lengths of content words.

Skip values may have any unsigned integer value of zero or greater.  Read values must always be greater than zero, except in the last record of a line, where they must be zero.  NL and W records that have a read value of zero therefore always mark the end of a line in the input file.

### Encoding Warp map files

To encode a Warp map file, the input file that is being mapped must first be decoded into a sequence of Unicode codepoints.  Supplementary Unicode codepoints (Unicode codepoints with values that are greater than U+FFFF) must be represented by a single Unicode codepoint rather than with a pair of surrogate codepoints.  The input file must use UTF-8 encoding.

After the input file has been decoded into a sequence of Unicode codepoints, it must be split into a sequence of lines.  Each line before the last ends with some kind of line break marker.  The last line ends with the actual end of the input file.  Line break markers are _not_ included within the line data.  Lines may be empty (contain no codepoints) if the line break marker or end of file occurs right away.  Since the end of the file is always present in input, input files will always have at least one line, even if the input file is completely empty with no bytes of data.

The line break marker must either be an LF character, or a CR+LF sequence.  The two types of line breaks may be mixed within the same input file.  CR characters must not occur in input except immediately before an LF character.

The final low-level input decoding step is to omit any sequence of U+FEFF byte order mark codepoints that occur at the start of the first line in the file.  UTF-8 optionally has a byte order mark.  There shouldn't ever actually be more than one byte order mark codepoint at the start of the file, but a potential sequence of byte order marks is omitted for robustness, since byte order marks may be automatically filtered out or inserted by I/O libraries.

Once these low-level filtering tasks have been performed on the input file, the input file will be a sequence of one or more lines, each of which contains a sequence of zero or more Unicode codepoints, with line break markers and byte order marks left out of line data.

Each input line is then encoded into a sequence of one or more Warp map file records.  After the last input line has been encoded, an EOF record is written to finish the Warp map file.

The first Warp map file record in a line is always an NL record, and any subsequent records in a line are always W records.  The total number of records in each line is always one greater than the total number of content words in the line.

If there are no content words in the line, simply write an NL record that has the total number of codepoints in the line as the skip value and zero as the read value.

Otherwise, the skip value of the NL record will be number of codepoints in the line prior to the first content word, and the read value of the NL record will be the number of codepoints in the first content word.  For any additional content words after the first, add W records for each word.  Set the skip value of each W record to the number of codepoints between the previous content word and the start of this content word, and set the read value of each W record to the number of codepoints in each content word.  After all content words have been encoded this way, write one more W record that has a skip value containing the number of codepoints remaining on the line after the last content word, and a read value of zero.

Once all lines have been mapped in this fashion, write an EOF record to indicate the end of the Warp map file.

The specific definition of what counts as a content word is intentionally not defined here, except that content words must each have at least Unicode codepoint.  This allows there to be different Warp map file encoders for different types of files.  For example, a plain-text Warp map file encoder might consider everything in the file that is not whitespace to be part of content words, while an HTML Warp map file encoder might exclude whitespace as well as markup tags.

### Decoding input with Warp map files

Once a Warp map file has been generated for an input file, the input file can be decoded by Warp utilities using the input map.

First, the input file is decoded into a sequence of one or more lines, each of which is a sequence of zero or more codepoints, excluding line break markers and byte order marks.  For details of this process, see the previous section.

Each line is then split into a sequence of `(2*N + 1)` substrings, where N is the total number of content words in the line.  If the line has no content words, there is one substring.  If the line has one content word, there are three substrings.  If the line has two content words, there are five substrings, and so forth.

When there is a single substring in a line, it means there are no content words, and the entire content of the line is in that single substring.  The substring may be empty if the line is empty.

Otherwise, the second, fourth, sixth, and all even-number substrings are content words.  None of these content word substrings may be empty.  The first substring contains everything in the line before the first content word and the last substring contains everything in the line after the last content word.  Both first and last substrings may be empty.  All other odd-number substrings contain the codepoints that come between the content words, and all such substrings may be empty.

To decode the array of substrings from a line in an input file and a sequence of Warp map file records, do the following.  First, gather records from the Warp map file until a record is found that has a read value of zero, which marks the last record in the line.  The first gathered record must be an NL record, and any subsequent gathered records must be W records.  The sum of all skip and read counts of all records gathered for the line must be exactly equal to the number of codepoints in the line (excluding any line break marker and, if this is the first line, any sequence of byte order marks at the start of the line).

Next, convert the sequence of gathered records into a sequence of integers.  The first integer is the skip count of the first record, the second integer is the read count of the first record, the third integer is the skip count of the second record, the fourth integer is the read count of the second record, and so forth.  However, do _not_ include the zero-valued read count of the last record in this sequence of integers.

The sequence of integers can then be converted into the substring array by reading substrings sequentially from the input line.  Each integer value in the sequence indicates how many codepoints should be in the corresponding substring.

### Warp Encapsulation Format Text (WEFT)

For purposes of constructing text processing pipelines, it is much easier if the Warp map file and the input text file are packaged into a single file.  The Warp Encapsulation Format Text (WEFT) is a simple package that prefixes the Warp map file to the input file.

The first line of a WEFT file is just a signature:

    %WEFT;

The second line of a WEFT file counts how many lines of text are in the encapsulated Warp map file.  This must be an unsigned decimal integer value written in ASCII, with no preceding whitespace.

Following the second line are the lines of the Warp map file.  The total number of these lines must match the number of lines declared in the second line of the WEFT file.

After all the lines of the Warp map file have been written in the WEFT file, the lines of the input file are written into the WEFT file.  The input file then proceeds to the end of the WEFT file.

### Example WEFT file

Consider the following input file:

    <p>The quick brown <i>fox</i><br/>
    jumps over the <b>lazy</b> dog.</p>

Suppose we want to exclude the HTML tags in the Warp map.  The corresponding Warp map file would then be as follows:

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

If we package the Warp map file and the input file into a WEFT file, the result is as follows:

    %WEFT;
    12
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
