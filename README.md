# Warp

Utilities for mapping words within a text or markup file and performing transformations on those words.

There are three kinds of Warp utilities:  _sources_, _filters_, and _targets_.  All three types of Warp utilities use the WEFT format to communicate with each other.  See `WEFTFormat.md` in the `doc` directory for a specification of the format.

Source utilities do not accept WEFT input but generate WEFT output.  They are used for transforming different types of input files into WEFT files so that they can be processed with Warp utilities.

Filter utilities accept WEFT input, perform some kind of transformation on the content, and generate transformed WEFT output.

Target utilities accept WEFT input but do not generate WEFT output.  They are used for transforming WEFT files back into various kinds of data files.

The recommended practice is to transform text with a pipeline.  The first program in the pipeline is a source utility that packages the pipeline input into WEFT.  Subsequent programs in the pipeline are then filter utilities that perform various transformations on the text, using WEFT to pass the text along from utility to utility.  Finally, the last program in the pipeline is a target utility that takes the transformed WEFT and generates a transformed output file in the proper format.

To develop new Warp utilities, the `Warp::Reader` and `Warp::Writer` Perl modules are provided in the `Warp` directory.  See the documentation within those scripts for further information.

## Source utilities

`warptext.pl` takes a plain-text file as input and packages it appropriately in a WEFT file.  This source utility should only be used for unstructured plain-text files that do not have any kind of markup.  Anything in the plain-text file that is not whitespace or a line break is taken to be textual content that should be subject to Warp transformations.

`warpxml.pl` takes an XML or HTML file or fragment as input and packages it appropriately in a WEFT file.  It also decodes entity escapes and simplifies them as much as possible.  Markup tags are excluded from textual content in the Warp Map.  See the script documentation for further information.

## Filter utilities

`warpword.pl` transforms WEFT by splitting content words into content words that carry actual linguistic words, and content words that carry other things, such as punctuation, numbers, and symbols.  This transformation makes it easier for later scripts in the pipeline to apply operations only to linguistic words.  Content words that are linguistic in the output of this script will have at least one codepoint that is in Unicode General Category L.

`warphyphen.pl` transforms WEFT by applying hyphenation.  It can also be used to generate word lists.  Hyphenation can be based on a word list with hyphenation points marked by grave accents, or a TeX hyphenation pattern file, or a combination of both.  You must first use `warpword.pl` or a similar script to split content words into linguistic and non-linguistic content.  See the script documentation for further information.

## Target utilities

`unweft.pl` takes a WEFT file as input and outputs just the input file that was packaged within in.  This is appropriate to use at the end of Warp pipelines to unpack the transformed results from the WEFT file.

`weft2json.pl` takes a WEFT file as input and outputs a JSON representation of how the lines are parsed into substrings.  This is useful for diagnostics.
