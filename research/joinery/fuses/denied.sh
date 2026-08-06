#!/usr/bin/env bash
# Splits taken and splits refused, per grammar, off one pinned binary.
#
# `denied` is the only honest way to ask whether a fork cap is a limit on
# anything: a row at zero cannot pay for a higher cap whatever its value, and a
# row above zero is money the corner is leaving on the floor. The pair is read
# from the parse's own trace rather than rebuilt, so an arm costs a second.
#
#   OUTLINER_BIN=<pin> research/joinery/fuses/denied.sh
set -u
BIN="${OUTLINER_BIN:?set OUTLINER_BIN to a pin binary}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 2

printf '%-20s %8s %8s\n' grammar splits denied
while IFS='|' read -r gr src; do
  gr="${gr// /}"; src="${src// /}"
  [ -z "$gr" ] && continue
  case "$gr" in \#*) continue ;; esac
  name=$(basename "$gr" .json)
  out=$(OUTLINER_TRACE=quire timeout 600 "$BIN" parse "$gr" "$src" 2>&1 >/dev/null)
  s=$(printf '%s' "$out" | grep -c '^split:')
  d=$(printf '%s' "$out" | grep -c '^denied:')
  [ "$s" = 0 ] && [ "$d" = 0 ] && continue
  printf '%-20s %8s %8s\n' "$name" "$s" "$d"
done < .local/orchestrate/census.txt
