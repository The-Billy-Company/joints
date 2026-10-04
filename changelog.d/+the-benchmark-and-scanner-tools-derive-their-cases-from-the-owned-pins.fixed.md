The benchmark and scanner tools copied the held-out grammar names and source
filenames, so a book or source pin could change without their corpora following
it. Both now derive the transcribed scanner cases from the committed books and
take their primary filenames and suffixes from the owned source pins. Alternate
script suffixes and the package's additional corpus roots remain explicit. The
benchmark's caret locator also asks the shared parse exchange for its forest,
so it receives the same scanner environment and artifact attribution as every
other parse measurement.
