# task-02-quadratic-fractional-ideal

Let `S` be a **quadratic ring** — a commutative ring whose additive group is free of
rank 2 over `ℤ` — with fraction algebra `K`. A **fractional ideal** of `S` is an
`S`-submodule of `K` of `ℤ`-rank 2. The agent must prove:

```lean
theorem invertible_iff_projective_rank_one
    [Algebra.IsQuadraticExtension ℤ S] (hK : IsFractionAlgebra S K)
    (I : Submodule S K) (hI : IsFractionalIdeal S K I) :
    (IsInvertible S K I ↔ IsProjectiveRankOne S K I) ∧
    (IsProjectiveRankOne S K I ↔
      ∃ J : Submodule S K, IsFractionalIdeal S K J ∧ I * J = 1)
```

The definition layer (`QRing/Defs.lean`, `QRing/Model.lean`, `QRing/QuadConjugation.lean`)
is supplied read-only. Everything else — an **874-line, 20-lemma development** — is deleted
and must be rebuilt.

## Why it is hard

Difficulty here is structural rather than a trick, and it does not depend on any single
obscure lemma the way a smaller task would.

*Projective of rank one ⟹ invertible* needs the local-global machinery for projective
modules: rank at every stalk, localization away from an element, a standard open cover, and
a Kaplansky-style argument that a projective module of `finrank` one over a local ring is
free of rank one. *Invertible ⟹ projective of rank one* needs the dual-basis construction
exhibiting `I` as a direct summand of a finite free module, a splitting argument showing the
kernel of a rank-one idempotent is subsingleton, and finiteness extracted from a
rank-at-stalk hypothesis.

Both halves bottom out in recent Mathlib API around `Module.rankAtStalk`,
`Module.Projective`, `PrimeSpectrum`, and the Picard group. Neither direction is a single
call, and the two named equivalences only collapse at the end because `IsInvertible` unfolds
definitionally to the existence of an inverse fractional ideal.


## Verifier design

- **Syntax scan** strips comments *and* string-literal contents before matching, then rejects
  metaprogramming, compile-time execution, and native-trust escapes. Ordinary proof
  engineering is allowed.
- **Model re-declaration check** rejects a submission redefining `IsProjectiveRankOne`,
  `IsInvertible`, `IsFractionalIdeal`, `zrank`, or `IsFractionAlgebra`.
- **Statement integrity.** The hidden grader states the intended theorem itself, plus a
  consequence the agent never sees (invertibility yields an actual inverse ideal), and proves
  each by *applying* the agent's theorem. Those applications type-check only against the same
  definitions with the same binders.
- **Axiom audit.** `collectAxioms` must be a subset of
  `{propext, Classical.choice, Quot.sound}`, preceded by a known-`sorry` canary certifying the
  audit machinery was not shadowed.

## Validation

Lean 4.33.0 / Mathlib v4.33.0.

| Case | Result |
| --- | --- |
| Oracle + grader | builds clean |
| Untouched stub | fails — `FORBIDDEN AXIOMS … [sorryAx]` |
| `#print axioms` on the oracle target | `[propext, Classical.choice, Quot.sound]` |
| Model identical across agent and verifier images | yes (enforced by `package.sh`) |

Under Harbor on a native x86_64 host: `oracle` scores 1.000, `nop` scores 0.000.
