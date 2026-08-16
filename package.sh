#!/bin/bash
# Package tasks for delivery: leak-check each task, then archive.
#
#   ./package.sh                      # all tasks
#   ./package.sh task-02-quadratic-fractional-ideal
#
# Produces dist/<task>.zip containing the task directory, plus dist/SHA256SUMS.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p dist

tasks=("$@")
if [ ${#tasks[@]} -eq 0 ]; then
  tasks=()
  for d in tasks/*/; do tasks+=("$(basename "$d")"); done
fi

fail=0
for t in "${tasks[@]}"; do
  dir="tasks/$t"
  [ -d "$dir" ] || { echo "no such task: $t" >&2; exit 1; }
  echo "==> $t"

  # 1. Build output must never ship: .lake/build holds compiled .olean/.ilean for
  #    every module built locally, including the oracle and the hidden grader,
  #    and environment/Dockerfile copies the project directory verbatim.
  if find "$dir" -type d -name .lake | grep -q .; then
    echo "    FAIL  .lake/ present — run: find $dir -type d -name .lake -exec rm -rf {} +" >&2
    fail=1; continue
  fi

  # 2. The agent image must not contain the grader or the reference proof.
  if find "$dir/environment" -iname '*erify*' | grep -q .; then
    echo "    FAIL  grader file under environment/" >&2
    fail=1; continue
  fi
  # Proof-route leak check, derived from the task rather than hardcoded: take the
  # lemma names the oracle declares, and fail if any of them appears in the agent
  # image. A name the agent is supposed to rediscover must not be sitting in its
  # container.
  oracle="$dir/solution/Submission.lean"
  if [ -f "$oracle" ]; then
    names=$(grep -oE '^(public )?(private )?(theorem|lemma) [A-Za-z_][A-Za-z0-9_.'"'"']*' "$oracle" \
              | awk '{print $NF}' | sort -u)
    # Names the agent is legitimately told (they appear in the shipped stub or the
    # read-only model) are not leaks — only oracle-internal helpers are.
    leaked=""
    for nm in $names; do
      grep -rqF "$nm" "$dir/environment" 2>/dev/null || continue
      told=0
      while IFS= read -r vis; do
        case "$vis" in *"/Submission.lean"|*"/Model.lean"|*"/Defs.lean") ;; *) continue ;; esac
        grep -qF "$nm" "$vis" 2>/dev/null && { told=1; break; }
      done < <(find "$dir/environment" -name '*.lean')
      [ "$told" -eq 1 ] || leaked="$leaked $nm"
    done
    if [ -n "$leaked" ]; then
      echo "    FAIL  oracle lemma names present in environment/:$leaked" >&2
      fail=1; continue
    fi
  fi

  # 3. Every shipped submission must still be the unsolved stub. Compare against
  #    the oracle: if they match, the reference proof was left in the agent image.
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    if ! grep -q '^  sorry' "$sub"; then
      echo "    FAIL  $(basename "$(dirname "$sub")")/Submission.lean is not the stub" >&2
      fail=1
    fi
    oracle="$dir/solution/Submission.lean"
    if [ -f "$oracle" ] && cmp -s "$sub" "$oracle"; then
      echo "    FAIL  shipped submission is byte-identical to the oracle" >&2
      fail=1
    fi
  done < <(find "$dir/environment" -name Submission.lean)
  [ $fail -eq 0 ] || continue

  # 3b. Language-agnostic: no file the verifier owns, and no file the oracle owns,
  #     may appear byte-identical anywhere in the agent image. This catches an
  #     expected-answers file or a reference implementation copied into the
  #     environment, which the Lean-specific name check above cannot see.
  #     tests/project/ is excluded: it is the shared read-only model, which is
  #     *required* to be byte-identical to the agent's copy (see check 4).
  while IFS= read -r secret; do
    [ -f "$secret" ] || continue
    while IFS= read -r vis; do
      [ -f "$vis" ] || continue
      if cmp -s "$secret" "$vis"; then
        echo "    FAIL  $(basename "$secret") from $(dirname "${secret#$dir/}") is present in environment/ as ${vis#$dir/}" >&2
        fail=1
      fi
    done < <(find "$dir/environment" -type f 2>/dev/null)
  done < <(find "$dir/tests" "$dir/solution" -type f 2>/dev/null | grep -v "^$dir/tests/project/")
  [ $fail -eq 0 ] || continue

  # 4. The agent and verifier images must share byte-identical model and build
  #    config. The grader proves its own restatement by applying the agent's
  #    theorem, which type-checks only against the same definitions; if the two
  #    copies drift, the verifier rejects honest proofs and the failure looks
  #    like a hard task rather than a broken one.
  while IFS= read -r b; do
    rel="${b#$dir/tests/project/}"
    a="$dir/environment/project/$rel"
    [ -f "$a" ] || continue
    case "$rel" in */Submission.lean|Submission.lean) continue ;; esac
    if ! diff -q "$a" "$b" >/dev/null; then
      echo "    FAIL  $rel differs between environment/ and tests/" >&2
      fail=1
    fi
  done < <(find "$dir/tests/project" -type f \( -name '*.lean' -o -name 'lakefile.toml' -o -name 'lean-toolchain' -o -name 'lake-manifest.json' \) 2>/dev/null)
  [ $fail -eq 0 ] || continue

  # 5. Author fields must be filled in before delivery.
  if grep -qE '^(author_name|author_email|relevant_experience|conflicts_of_interest) = ""$' "$dir/task.toml"; then
    echo "    WARN  task.toml has empty author/disclosure fields"
  fi

  rm -f "dist/$t.zip"
  ( cd tasks && zip -qr "../dist/$t.zip" "$t" -x '*/.lake/*' '*/__pycache__/*' '*.pyc' '*/.DS_Store' )
  echo "    ok    dist/$t.zip ($(du -h "dist/$t.zip" | cut -f1))"
done

[ $fail -eq 0 ] || { echo "packaging aborted" >&2; exit 1; }

( cd dist && shasum -a 256 ./*.zip > SHA256SUMS && cat SHA256SUMS )
