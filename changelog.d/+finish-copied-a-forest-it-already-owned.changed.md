Two ends of the parse were paying for buffers that already held the answer.
`finish` copied `nodes` and `kids` into fresh allocations for the `Quire`;
they are the parse's own working arrays, wanted by nobody after the handoff,
so the lists now donate their buffers and the copy is gone. And `bind` walked
the whole tree to apply marks when everything below a watermark (`bound`) was
restored whole by `remount`, parents already written - the walk now stops at
the watermark instead of re-visiting what it could not change.

Neither is subtle and neither needed to be: together they were the difference
between a cold parse that ends when the last token shifts and one that ends
after a full-tree lap and a multi-megabyte memcpy nobody reads.
