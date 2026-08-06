# Changelog fragments

One file per change, written when the change lands rather than when the release
does. The sibling packages (`irregex`, `gist`, `relate`, `blast`) all keep their
history this way and a release action folds the directory into `CHANGELOG.md`,
so the shape here is theirs.

```text
+<a-sentence-in-kebab-case>.<type>.md
```

`type` is one of `added`, `changed`, `deprecated`, `removed`, `fixed`,
`security`. The stem is the headline read as a sentence, lowercase, hyphens for
spaces, no punctuation.

The body is prose, not a bullet. Say what was wrong, say what the rule is now,
and give the numbers you measured with the date or the run they came from. A
fragment that only names the file it touched is a `git log` entry with extra
steps; the reason these are worth writing is that they are the only place the
*argument* for a change survives after the diff has been read once.

Two habits worth copying from the siblings. Write down what the change costs and
where it goes the wrong way, in the same paragraph as the win, because an
average that hides its worst row is not a measurement. And when the bug lasted
because an instrument lied, say which instrument and what it said - that is
usually the more valuable half, and it is the half nobody else can reconstruct.
