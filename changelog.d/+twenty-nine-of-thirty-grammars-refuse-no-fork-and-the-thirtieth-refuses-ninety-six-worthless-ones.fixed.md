`crowd`'s doc comment carried two denial counts - 46 refused forks in verilog,
4 in swift - from a sweep taken before the pair moved to 64/512. Both are now
wrong, and the sentence they supported ("8 stays because the cap is cheap") was
already known wrong. A corpus-wide census off the parse's own trace replaces
them: twenty-nine of thirty grammars deny **nothing**, and swift denies 80 of
987 splits, all of them the same state on the same token at byte 24283.

The pair is also separated for the first time, which tells you which fuse is
live. Holding one and raising the other, each arm its own binary and every board
against the frozen `limb` oracle: `crowd = 512` clears all 80 of swift's denials
and opens 96 more splits, while `skeins = 4096` leaves every denial standing. So
`crowd` is the limit and `skeins` is slack everywhere on today's board.

And the 96 readings `crowd = 512` opens are worth **zero square**. 512/512,
64/4096 and 512/4096 are byte-identical to 64/512 across all thirty grammars at
309,356 square without verilog, at 1.02x parse time and 1.00x peak RSS. 64/512
is the knee, not a waypoint: 4/4 costs 110,337 square bytes for 22% less time,
and there is nothing at all above.
