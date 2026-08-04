#!/usr/bin/env bash
# The corpus program: a ledger that caches its own total.
# push invalidates the cache, ledger_total rebuilds it and holds it until
# the next push, and every file in this folder tells that same story.
set -euo pipefail

# A quoted heredoc, which is bash's multi-line literal: the tag in the opener
# decides where the body ends, and quoting it turns off expansion inside.
BANNER=$(cat <<'RECEIPT'
ledger receipt
--------------
RECEIPT
)

declare -a rows=()
declare -A tags=()
total=""

push() {
	local tag="$1" value="$2"
	if [[ ! $value =~ ^-?[0-9]+$ ]]; then
		echo "skipping $tag: $value is not an integer" >&2
		return 1
	fi
	tags["$tag"]=${#rows[@]}
	rows+=("$value")
	total=""
}

ledger_total() {
	if [[ -z $total ]]; then
		local acc=0
		for r in "${rows[@]}"; do
			if ((r > 0)); then acc=$((acc + r)); fi
		done
		total=$acc
	fi
	printf '%s\n' "$total"
}

for i in "$@"; do
	push "arg$i" "$i" || continue
done

# A backslash continuation, which splices these two lines into one command.
printf '%s\n' "$BANNER" \
	"total=$(ledger_total)"
