# Prediction 3 — the prefix half, and why the veto is the bug rather than the slate

Written **before the change compiles**, against baseline pin `prefix-before`
(tree `15fa62022c2d`, commit `f7ba40004+114`), folio set `.local/standing`,
instruments `research/keystroke/{probe,abide}.py`. Every row names its falsifier.

Baseline, this pin, this machine, so the after-arm is compared against a number
I took myself rather than the one in `RESULT-1`:

| grammar | open µs | µs/key | gain | lifts | read | prefix |
|---|---|---|---|---|---|---|
| swift | 37,257 | **35,675** | 1x | 0 | 3,628 | 1.00 |
| verilog | 60,654 | **58,796** | 1x | 0 | 8,951 | 1.00 |
| ocaml | 32,315 | **30,883** | 1x | 0 | 4,192 | 1.00 |
| scala | 4,137 | **4,575** | 1x | 0 | 1,277 | 1.00 |

`prefix = 1.00` on all four: the parse begins on the ground and re-reads the
file. And the trace says which of `alight`'s three questions did it — swift, at
an edit at 14,000:

```
holds: ring 56 at 13246 wanted public 13249..13255 got _implicit_semi 13246..13246 from state 2
holds: ring 55 at 12216 wanted where_keyword 12217..12222 got _implicit_semi 12216..12216 from state 2
holds: ring 54 at 11954 wanted public 11957..11963 got _implicit_semi 11954..11954 from state 2
holds: ring 53 at 11760 wanted extension 11764..11773 got stray from state 0
alight: declined - firm=14000 unseamed=0 unfit=0 unheld=4 lowest=11726
```

## What I read out of that before changing anything

`holds` builds its slate from one state's raw action row, `.kind != .err`.
`offer` — what the parse used — is `{sym : shiftable(top, sym)}` unioned over
every live reading, plus **every sprig's first terminal**. So the two sets are
not related by inclusion in either direction:

- `shiftable` ⊆ raw row (it returns false on an `.err` cell first thing), so
  `holds` is **wider** wherever a terminal's reduce chain dies below the top.
  `_implicit_semi` is that: swift's external scanner is handed the slate, so a
  terminal admitted to it that the parse never offered makes the *hand* answer
  differently, and a zero-width answer means the walk cannot even advance.
- sprig firsts ⊄ raw row — a rule-shaped extra is unreachable from the start
  symbol, so no state has a cell for it. `holds` is therefore also **narrower**
  than `offer` on the two grammars with a sprig, which is a soundness hole and
  not a speed one.

**The important structural reading is that the slate cannot be reconstructed
here at all.** `shiftable` follows the folds down the stack that is standing,
and `holds` runs before anything is mounted; it has one recorded state per
token and no stack under it. Reconstruction is not a small job that nobody did,
it is not available.

So I am not going to fix the slate. I am going to stop asking it to be a veto.

## The change

`holds` answers *"does the stretch between ring i−1 and ring i still lex the way
it was recorded"*, and the answer is used as a veto: four declines and the parse
falls to `ground` and re-reads the file. But the stretch a decline is about is
**exactly the stretch the ordinary loop re-reads if the parse stands on the ring
below it.** A decline is not a reason to abandon the tiling; it is an answer to
*which ring to mount*.

    holds(i) true   →  mount ring i, skip the stretch     (today, unchanged)
    holds(i) false  →  mount ring i−1, and let the loop derive the stretch

Two things fall out. `holds` becomes a fast path rather than a gate, so its
wide-slate false declines cost one stride of parsing instead of a whole file.
And the hole case needs nothing: scala re-lexes from 9,538 while the first
recorded token in the stretch starts at 9,902, and a walk that is no longer
asked about those 364 bytes does not have to know they are a hole — the loop
parses them.

### Why the fallback is sound, in the terms already in the file

The obligation for mounting ring *j* is that no token ending at or below
`r_j.at` had its extent changed, i.e. that no such token's scan read a byte at
or past `firm`. `holds(j)` discharges that for the tokens in `[r_{j-1}.at,
r_j.at)` and for **nothing below it** — the hundreds of tokens under
`r_{j-1}.at` are held by an assumption the header already states outright:

> What that leaves unproved is a token whose scan reaches beyond a whole ring's
> worth of text, which no tokenizer in the corpus does and none of them could
> do cheaply

Mounting `i−1` and re-deriving `[r_{i-1}.at, …)` rests on that same assumption
and on nothing else, one stride further from the edit than the place it is
already load-bearing. It is not a new licence; it is the existing one, used to
buy the thing it was already buying.

The two conditions that are *not* assumptions stay gates, because a ring that
fails them cannot be mounted at all: `seamed` (the old tiling has a boundary
here, so the spine can splice) and `fits` (the ring's watermarks lie inside the
tree on offer). A decline from either still descends.

### And the sprigs go in

One line, and it makes `holds`'s slate a proper superset of `offer`'s. It can
only make declines *more* common, never fewer, so it cannot be what any speed
number below is measuring — which is why it goes in the same change rather than
being saved for a prettier one.

## Predictions

| # | Prediction | Falsified by |
|---|---|---|
| P1 | All four of swift, verilog, ocaml, scala go `prefix = 1.00` → **`prefix < 0.75`** at the midpoint edit. This is the whole claim: the parse stops beginning on the ground. | any of the four still at `prefix > 0.9` |
| P2 | Swift's µs/key drops by **≥ 40%** from 35,675. The edit is at the file midpoint and cost is `(1 − p) × cold` once the resume stands, so the arithmetic says ~50% and I am leaving room for the tail being more expensive than the head. | < 40% |
| P3 | **No grammar gains a `lift`.** This change is the prefix half and touches neither `stoop` nor the forest gate, so `lifts` stays 0 on every mended grammar and unchanged on the clean ones. If lifts move, I am measuring two things. | any `lifts` delta on any grammar |
| P4 | `abide` stays at **its baseline count or better**, and in particular swift and verilog stay at 24/24. A resume that stands where the parse used to grind is either the same tree or a defect, and this is the whole reason the change is worth measuring. | any grammar losing ground on `abide` |
| P5 | The **clean 13 barely move**: no change > 15% either way on go, javascript, python, json, css, toml, embedded-template. `holds` already succeeds there (their `prefix` is 0.08–0.27), so the fallback never fires and the sprig line is the only thing they see. | > 15% on any of them |
| P6 | `unheld` stays **> 0** on swift in the trace. The decline is not being fixed; it is being demoted. A trace showing `unheld=0` means the slate changed underneath me and the measurement is of something else. | `unheld = 0` on swift |
| P7 | The clean grammars whose warm parses mend — java, rust, typescript, lua, at 5 or 6 accepted of 24 — **do** move, because from their second edit they are forests with a dropped resume for the same reason swift is. `RESULT-2`'s P1 died on exactly this conflation and I am predicting the other side of it out loud. | none of java/rust/typescript/lua moving > 15% |
| P8 | **`read` falls further than time does** on the four. A resumed parse declines tokens; the tail it still reads is the expensive half of the file on a grammar whose cost is superlinear in stack depth, so the token ratio will beat the microsecond ratio. If time falls *more* than `read`, something other than reuse got cheaper and I go looking for it. | µs falling by a larger factor than `read` on any of the four |

## What I expect to be wrong about

**P5.** The sprig line widens the slate on every grammar that has a sprig, and
if one of the clean 13 has one, its `holds` may start declining where it used to
hold — which under the new fallback costs a stride rather than the file, so it
would show as a small regression rather than a large one. I have not looked up
which grammars have sprigs, deliberately: I would rather be caught by the
measurement than tune the prediction to it.

**P2's magnitude, in the direction of it being too small.** Four rings are tried
today and every one of them pays a re-lex walk before the parse gives up and
re-reads the file anyway. The fallback fires on the *first* decline, so swift
stops paying three of the four walks as well as the cold parse, and that is a
saving the `(1 − p)` arithmetic does not account for.

## What would make me revert

`abide` losing a single grammar-keystroke it holds today. The previous lane's
20x forest win is out of the tree because it cost four grammars on this guard,
and a 2x is worth less than that was.
