#!/usr/bin/env bash
# The corpus program: a ledger that caches its own total.
set -euo pipefail

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

echo "total=$(ledger_total)"
