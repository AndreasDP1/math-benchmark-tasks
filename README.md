# Formal mathematics benchmark tasks

Terminal-Bench / Harbor-format tasks in mathematics, built so that verification is exact:
a Lean proof the kernel accepts under an axiom audit, or an integer that matches. No
tolerances, no LLM judge, no partial credit.

Each task is self-contained: an agent container with Lean and a pinned Mathlib, an
instruction, a reference (oracle) solution, and a verifier that runs in its own clean
container after the agent's is destroyed.

## Tasks

| Task | Deliverable | Oracle size | Est. expert time |
| --- | --- | --- | --- |
| [`task-02-quadratic-fractional-ideal`](tasks/task-02-quadratic-fractional-ideal/) | A fractional ideal of a quadratic ring is invertible iff it is projective of rank one | 874 lines, 20 lemmas | 35 h |

Each task directory has its own `README.md` covering the mathematics, why it is hard, the
verifier design, and validation evidence.
| [`task-03-monogenic-index`](tasks/task-03-monogenic-index/) | Extremal values and multiplicities of the index `[O_K : Z[alpha]]` for pure fields `Q(a^(1/n))`, graded on unseen `n` | reference is 120 lines, pure stdlib | 12 h |

## Requirements

- Docker with the `compose` plugin, on **x86_64**
- [Harbor](https://harborframework.com): `uv tool install harbor`
- ~40 GB free disk (each image bakes a full Mathlib build)

Images pin `--platform=linux/amd64` deliberately: Mathlib publishes its prebuilt `.olean`
cache only for x86_64 Linux, so an arm64 build silently falls back to compiling Mathlib
from source. On an Apple-silicon machine everything still runs, under emulation, slowly.

## Running a task

```bash
# the oracle must score 1.0 — this proves the task is solvable and the verifier works
harbor run -p tasks/<task-name> -a oracle

# the nop agent must score 0.0 — this proves the verifier isn't passing everything
harbor run -p tasks/<task-name> -a nop

# a real agent
harbor run -p tasks/<task-name> -a claude-code -m anthropic/claude-opus-5
```

First run builds the images and takes roughly 15–20 minutes on a native x86_64 host;
after that a trial is minutes. Reward is written to `/logs/verifier/reward.txt` inside the
verifier container and surfaced by Harbor as the trial's mean.

Results land in `jobs/<timestamp>/`. The agent's full trajectory is at
`jobs/*/<task>__*/agent/trajectory.json` and the artifact it produced — the only thing the
verifier sees — at `jobs/*/<task>__*/artifacts/`.

## What each task ships

```
tasks/<task-name>/
├── task.toml            config, metadata, resource limits, timeouts
├── instruction.md       exactly what the agent is told
├── environment/
│   ├── Dockerfile       agent container: Lean toolchain + pinned Mathlib
│   └── project/         the read-only model, plus the stub with `sorry`
├── solution/
│   ├── solve.sh         oracle: installs the reference proof, rebuilds
│   └── Submission.lean  the reference proof
└── tests/
    ├── Dockerfile       verifier container, built separately
    ├── Verify.lean      hidden grader — never in the agent image
    ├── test.sh          writes 1 or 0 to /logs/verifier/reward.txt
    └── test_verify.py   syntax scan, model-integrity check, build, axiom audit
```

## How the verifier resists cheating

The same four-layer design in every task:

1. **Syntax scan.** Strips comments *and* string-literal contents before matching, then
   rejects metaprogramming (`macro`, `elab`, `syntax`, global `notation`), compile-time
   execution (`run_cmd`, `#eval`, `initialize`), and native-trust escapes
   (`native_decide`, `@[implemented_by]`, `@[extern]`). Ordinary proof engineering —
   plain `set_option`, `local notation`, `deriving`, decidability instances — is allowed.
2. **Model integrity.** A submission that re-declares any fixed definition is rejected.
3. **Statement integrity.** The hidden grader states the intended theorem *itself* and
   proves it by applying the agent's. That application type-checks only against the same
   definitions with the same binders, so shadowing the model, adding a hypothesis, or
   weakening the statement to a tautology all fail with a type mismatch — not a pass.
   Each grader also proves a consequence the agent never sees.
4. **Axiom audit.** `collectAxioms` on each grader lemma must be a subset of
   `{propext, Classical.choice, Quot.sound}` — rejecting `sorry`, `native_decide`, and any
   user-declared axiom — preceded by a known-`sorry` canary that fails the build if the
   audit machinery itself was shadowed.

Every rejection path is exercised when a task is built: the untouched stub, a statement
weakened to a tautology, a smuggled extra hypothesis, and a proof from custom axioms all
fail; the oracle passes. Each task's own README records the results.

## Running a task without Harbor

Harbor provides container isolation, artifact transfer, and the `oracle`/`nop` agents. It
does not define what counts as a correct answer — that lives in each task's verifier. Where
a task ships `tests/run_standalone.sh`, the same checker can be run directly against a
candidate solution with no Harbor and no Docker:

    tasks/<task-name>/tests/run_standalone.sh path/to/candidate

## Repackaging

```bash
./package.sh                 # all tasks -> dist/<task>.zip + SHA256SUMS
./package.sh <task-name>     # one task
```

`package.sh` refuses to package when `.lake/` is present (it contains compiled copies of
the reference proof and the hidden grader, and `environment/Dockerfile` copies the project
directory verbatim), when the grader has leaked into `environment/`, when a shipped
submission is not the unsolved stub, or when the model has drifted between the agent and
verifier images. That last one matters: the grader proves its restatement by applying the
agent's theorem, so drift makes the verifier reject correct proofs, and that failure reads
as a hard task rather than a broken one.
