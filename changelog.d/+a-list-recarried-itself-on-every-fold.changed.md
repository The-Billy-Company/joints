`reduce` built every production the same way: copy the popped perches' runs out
of `borne` into `born`, apply fields and aliases, mint, carry the result back.
For a left-recursive list - which is what every `statement*` in every grammar
lowers to - the accumulated run rode that round trip on every fold, so a list
priced at O(n²) in its own length, and the profile showed the parse spending
its time in `memmove` under `fold`.

In a lone parse the round trip writes every byte onto itself: `borne` is a
strict stack, so a popped perch's lead and own runs already tile its top in
exactly the order the copy-out would visit them. The fast path proves that
tiling with a cursor check, refuses on any alias (the one recipe that edits a
run) or any gap (a grafted stack, a fork's interleavings), and otherwise
applies fields in place and mints over the children where they lie. The
copying path is unchanged and still takes everything the check refuses.

Worth 92.8 ns/byte from 97.3 on the cpp corpus, and the shape is the point:
the one mint that finally claims a list is now the only time its run moves.
