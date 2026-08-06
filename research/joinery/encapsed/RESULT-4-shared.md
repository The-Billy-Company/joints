# Result 4 — is the mechanism shared? The seam is; the change is not.

The brief asked whether one change moves four grammars, and said that if it
does, that leads the report. **It does not, and the honest answer needs the
distinction the question elides: a shared *seam* is not a shared *change*.**

Prediction 4 predicted "one change, one grammar moved, one grammar made
cheaper". That is right in shape and **wrong on two of its three legs**, and
the reframing that arrived mid-lane is why.

## What the mechanism actually is

php's four seated terminals are **one C function serving N terminals, where
the parameters that vary arrive by which terminal the parse state named**.
`scan_encapsed_part_string` takes `is_after_variable` and
`is_execution_string`; nothing remembers them; the state supplies them by
asking for `encapsed_string_chars_after_variable` rather than
`encapsed_string_chars`. That is `marrow.Family` — one walk, N rows of data —
and it is the third instance of it after elixir's twenty and julia's eight.

So the test for "shares the mechanism" is: *does the scanner answer this
terminal from the bytes at the cursor plus the identity of the terminal, with
nothing carried?* Not "is it a delimited span".

## Grammar by grammar, re-derived

| grammar | token | shares the mechanism? |
|---|---|---|
| **elixir** | `_newline_before_binary_operator` | **No** — see RESULT-5 |
| **bash** | `regex` | **Yes**, and I predicted no |
| **latex** | `_trivia_raw_env_verbatim` | **Yes**, and needs one widening |
| **C** | — | Not in the adjudicated set at all |

**elixir — no, and the 66,700-byte pair does not exist.** The lane that
interrupted me flagged this as potentially "by far the biggest single thing
available" and asked me to check it early. I did, before reading anything, and
predicted no. `scan_newline` calls `mark_end` immediately after the newline
and its trailing whitespace and then only *peeks* at the operator that
follows. Zero extent, no delimiter, no close. It is a break, not a span — a
`caesura`, which this tree already has a seam for. Full derivation in
RESULT-5.

**bash — yes, and prediction 4 got this wrong.** I predicted bash "shares the
category and not the mechanism; it wants the heredoc half of php's scanner,
which is precisely the half I am not seating." The token the adjudication
named is `regex`, not a heredoc, and bash's scanner declares
`REGEX`, `REGEX_NO_SLASH` and `REGEX_NO_SPACE` — **three terminals, one
function, dispatched on `valid_symbols`**, which is php's family shape exactly.
I reasoned from bash's heredoc stack, which is real and is a different part of
the same scanner, and never checked which token was doing the work. The
adjudication lane's warning — *don't trust a named terminal without
re-deriving it* — applies to the terminal I assumed as much as to the one I
was handed.

**latex — yes, exactly as predicted, and it names the one widening needed.**
`TRIVIA_RAW_ENV_VERBATIM` is `find_verbatim(lexer, "\\end{verbatim}", false)`:
a close hardcoded per terminal, no memory, eleven rows of the same walk. That
is a `Family` roster and nothing else. The one thing it needs that php did not
is a **string-valued close** — `marrow.Mark.shut` is a `u8`, which is enough
for `"` and `` ` `` and not for `\end{verbatim}`. That is a real, small,
named piece of work rather than a guess.

## So the finding, stated the way it should be

**One change, one grammar.** php's 40,995 bytes are php's alone, and nothing
in this diff moves bash, latex, elixir or C by a byte — proven, not asserted:
rack's without-php split is byte-identical on both arms.

What generalises is the **seam and its judgement**, and that is worth more than
it sounds. `marrow.Family` now has three instances and a rule with teeth,
written into the file: *same table, different walk*. Each family reuses the
`Part`/`Mark`/`Troupe` machinery and **none reuses another's walk**, because
each time a lane has been tempted to (julia under elixir's `matter`, and my own
draft under it too) the languages disagreed in three places. php makes the
third data point for that rule, and bash and latex are now two named,
mechanism-identified rows rather than two open questions — which is exactly the
"grammar made cheaper" prediction 4 got right, twice over instead of once.
