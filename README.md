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

The symbol at the start of the line indicates the record type.  There are four types of records:

- `^` Beginning Of File (BOF) record
- `+` Next Line (NL) record
- `.` Word (W) record
- `$` End Of File (EOF) record

There must always be at least two records in a Warp map file.  The first record in a Warp map file must always be a BOF record, and the last record must always be an EOF record.  Between those two records is a sequence of zero or more NL and/or W records.

For the EOF record, both sequences of ASCII digits must decode to integer values of zero.

For BOF, NL, and W records, the first sequence of ASCII digits decodes to an integer that counts the number of Unicode codepoints on a line that are _not_ part of a content word.  This integer count may be zero.

For BOF, NL, and W records that occur immediately before a NL or EOF record, the second sequence of ASCII digits must decode to an integer value of zero.  In this case, the first sequence of ASCII digits counts the number of Unicode codepoints at the end of the line before the line break or End Of File that are _not_ part of a content word.  This count may be zero if the line is empty or if there are not Unicode codepoints between the end of the last content word and the line break.

For BOF, NL, and W records that occur immediately before a W record, the second sequence of ASCII digits must decode to an integer value that is greater than zero.  This second sequence of ASCII digits counts the number of Unicode codepoints within a content word that should be processed by Warp processors.

For the input text or markup file, the last line has the End Of File as its termination, while any previous lines have a line break code as their termination.  If the input file ends with a line break code, there will still be an empty line after this final line break code.  All input files must have at least one line, therefore.

The first line always begins with a BOF record in the Warp map file, while any subsequent lines always begin with NL records.  After the records of the last line recorded in the Warp map file, there is always an EOF record.

Each line of the input file is always represented by a sequence of one more records than there are content words in the line.  For a line with no content words, there will be one record; a line with one content word will have two records; and so forth.  Within a line, all records after the first will be W records.

To decode the meaning of a map file for a line, parse the sequence of integer values that occur in each record for the line into an array of integers, except leave out the last integer value.  Since each record has two integer values and there are `(N + 1)` records where N is the number of content words on the line, there will be `(2 * (N + 1) - 1)` integers in the array, which is equal to a total of `(2 * N) + 1` integers.

If the first integer of this array has index zero, then indices 1, 3, 5, etc. will represent content word lengths and indices 0, 2, 4, etc. will represent runs of non-content codepoints.  This has the following interpretation:

    Index 0 - # of codepoints before first word
    Index 1 - # of codepoints in first word
    Index 2 - # of codepoints between first and second words
    Index 3 - # of codepoints in second word
    ...

For example, consider the following line:

    <p>The quick brown <i>fox</i><br/>

If this is the first line of the file, we begin with a BOF record, while if this is not the first line of the file, we begin with a NL record.  We could encode this line as follows (starting with a BOF).  Comments have been added to show what each record describes in the line

    ^3,3   -> <p>,The
    .1,5   ->  ,quick
    .1,5   ->  ,brown
    .4,3   ->  <i>,fox
    .9,0   -> </i><br/>
