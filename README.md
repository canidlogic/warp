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

## Target utilities

`unweft.pl` takes a WEFT file as input and outputs just the input file that was packaged within in.  This is appropriate to use at the end of Warp pipelines to unpack the transformed results from the WEFT file.

`weft2json.pl` takes a WEFT file as input and outputs a JSON representation of how the lines are parsed into substrings.  This is useful for diagnostics.
