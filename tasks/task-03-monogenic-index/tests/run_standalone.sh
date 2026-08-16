#!/usr/bin/env bash
# Run this task's verifier against a candidate solution, without Harbor or Docker.
#
#   tests/run_standalone.sh path/to/candidate_compute.py
#
# Exits 0 and prints PASS if the candidate matches the reference on every hidden
# value of n; exits 1 and prints FAIL otherwise. This is the same checker Harbor
# runs — the grading logic lives in test_compute.py, not in the harness.
set -uo pipefail
CAND="${1:?usage: run_standalone.sh path/to/compute.py}"
[ -f "$CAND" ] || { echo "no such file: $CAND" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/answer"
cp "$CAND" "$WORK/answer/compute.py"
cp "$HERE/expected.json" "$WORK/"
sed -e "s|/root/answer/compute.py|$WORK/answer/compute.py|" \
    -e "s|cwd=\"/root\"|cwd=\"$WORK\"|" \
    "$HERE/test_compute.py" > "$WORK/test_compute.py"

python3 -m pytest "$WORK/test_compute.py" -q
RC=$?
[ "$RC" -eq 0 ] && echo "PASS (reward 1)" || echo "FAIL (reward 0)"
exit $RC
