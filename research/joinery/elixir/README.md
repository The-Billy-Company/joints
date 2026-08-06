# elixir — `arguments` where the oracle says `do_block`

Elixir was the corpus's widest row for *wrong* structure: **22,089 crooked bytes
over 46,089 built**, 48% of everything it places, with every token agreed and
every leaf in the right spot. A byte-indexed comparison scores it perfect
(`plumb` reads **0 askew**); only `rack.py`, which compares derivations, can see
it at all. It is also the one row of the seventeen that reach whole which fails
both interior questions, so it is the whole distance between "17 parse whole"
and "16 whole on all three axes".

Two results.

| | |
|---|---|
| [RESULT-1-split.md](RESULT-1-split.md) | The same-name split does not hold. It was read off the twenty *widest* runs and inverts when you ask all of them: elixir 0% → **37.6%**, scala 5% → **86.1%**. It survives as a claim about **bytes**, which is not what it was stated as. |
| [RESULT-2-do-block.md](RESULT-2-do-block.md) | The defect, and a repair that takes elixir to **zero crooked bytes** for +27 on swift — corpus −41.9%. It is two halves, one in the press and one in the parse loop, and **neither half does anything alone**. Both are landed. |

`every.py` is the instrument RESULT-1 rests on: the same-name split over every
run instead of the twenty widest, reusing `rack.bucket` rather than
re-implementing it.

```bash
python3 research/joinery/elixir/every.py --oracle=<tag>          # all thirty
python3 research/joinery/elixir/every.py elixir --oracle=<tag>   # one, with the tail
```

## The witness was already here

`research/joinery/specimen/elixir/do-block-on-inner-call.ex` — 21 bytes,
`defp f(x) do\n  x\nend`, with two controls beside it that a prior lane wrote
and that are the reason this repair is believable rather than lucky:

- `do-block-without-inner-call.ex` (`defp f do x end`) — one candidate for the
  block, so there is no choice to get wrong. **Green in every arm below except
  the one that only repairs the press**, which is how the first attempt was
  caught.
- `do-block-as-keyword-argument.ex` (`defp(f(x), do: x)`) — the same meaning
  desugared, same inner call, no `do` token. Always green.

`tool/specimen.py run --grammar=elixir` goes **4/5 → 5/5**; the witness has been
red since it was written.
