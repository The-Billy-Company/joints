`joints query <scm> <file>` compiles a query against a pressed grammar and
streams what it matches - `--json` for a machine, `--captures` to name only the
ones you want, `--dead` for the patterns the compiler proved can never fire,
`--foreign` for the policy on a predicate we carry but cannot run. Exit 0 with
matches, 1 without, 2 on a refusal.

The verb is worth more as an oracle than as a door. tree-sitter ships the same
question on its own CLI, so [`tool/glance.py`](tool/glance.py) can ask both
engines the eighty-four harvested `.scm` files over the same sources and diff
the answers as multisets and as sequences. Everything below this line was found
by running it, and none of it was visible from the unit tests, which agreed with
the implementation because they were written from the same reading of the
notation.
