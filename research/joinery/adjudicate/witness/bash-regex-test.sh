#!/usr/bin/env bash
push() {
	local tag="$1" value="$2"
	if [[ ! $value =~ ^-?[0-9]+$ ]]; then
		echo "skipping $tag: $value is not an integer" >&2
		return 1
	fi
}
