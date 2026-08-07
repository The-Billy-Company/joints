Every terminal in the corpus now compiles: the `declined` population is zero.

The last one was markdown's `entity_reference`, the HTML entity table - 2,231
literal alternatives whose shared-prefix trie needs 5,991 DFA states against a
4,096 ceiling. It was the only automaton over that bound in thirty grammars, and
second place is scala at 2,945, so the ceiling was right for twenty-nine and
wrong for one. Fixed in irregex, where a lexer slate now names its own size
budget instead of inheriting one calibrated for a pattern somebody typed a second
ago.

`&amp;` used to lex as three tokens (`&`, a text run `amp`, `;`) because a
declined terminal never wins the row it should own. It is now one
`entity_reference`.

The three-axis board does not move - all thirty rows byte-identical against a
control arm on the same tree and the same oracle. markdown's damage is the 47
externally scanned terminals it is blind to, not this one, and that half is
unchanged. What did move is build time: markdown's slate is **2.85x faster**
(1,060 ms to 372 ms), because a refusal made `admit` bisect six levels deep to
name the culprit and discard every attempt on the way.
