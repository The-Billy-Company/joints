#!/usr/bin/env bash
push() {
	local tag="$1" value="$2"
	if [[ -z $value ]]; then
		echo "skipping $tag" >&2
		return 1
	fi
}
