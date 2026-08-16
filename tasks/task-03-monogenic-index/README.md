# task-03-monogenic-index

For an integer `n >= 3`, let `A_n` be the set of integers `a` such that `x^n - a` is
irreducible over the rationals and, for every prime `p | n`, either `p` does not divide `a`
or `p` does not divide `v_p(a)`. For `a` in `A_n` with `|a| <= n`, put

    d(a,n) = [O_K : Z[alpha]],    K = Q[x]/(x^n - a),  alpha a root of x^n - a.

The agent writes a program computing the minimum and maximum of `d(a,n)` and how many `a`
attain each. It is graded on values of `n` it never sees.

## Why it is hard

Computing `O_K` directly is the obvious shortcut, so no computer-algebra package is
installed and none can be fetched. The agent has to derive the arithmetic structure of the
index.

That structure has a trap. Writing `disc(x^n - a) = d^2 * disc(K)` reduces the problem to
the field discriminant, and `v_p(d)` splits into two regimes:

- `t_p = v_p(a^(p-1) - 1) <= 1` — a closed form in `v_p(a)`, `n`, and `gcd(n, v_p(a))`;
- `t_p > 1`, which forces `v_p(a) = 0` and `p | n` — a truncated geometric sum in `p` of
  length `min(t_p - 1, v_p(n))`.

An implementation handling only the first regime is right for some `n` and wrong for
others.

The admissible set is a second trap: irreducibility needs `a` to avoid being a `p`-th power
for every `p | n`, *plus* `a` not of the form `-4b^4` when `4 | n` — an omission that only
bites for `n` divisible by four.

## Verifier

Ten values of `n` — 4, 9, 24, 45, 121, 128, 180, 210, 243, 256 — are baked into the verifier
image and never present in the agent container. They span `n` divisible by 4, odd prime
powers, a prime square whose prime does not divide `n`, powers of two and three, squarefree
`n` with four prime factors, and highly composite `n`, so a partial implementation fails on
a diagnosable subset rather than passing by luck.

`n = 300` is excluded: that value is published, so grading on it would reward lookup.

All four outputs are compared as exact integers. A JSON number or decimal string is
accepted; a float is rejected, since the maximum runs to hundreds of digits. Each `n` is
capped at 60 seconds.

## Running it

Under Harbor:

    harbor run -p . -a oracle      # scores 1.0
    harbor run -p . -a nop         # scores 0.0

Or without Harbor or Docker — the grading logic lives in `tests/test_compute.py`, not in
the harness:

    tests/run_standalone.sh path/to/candidate_compute.py

## Validation

| Case | Result |
| --- | --- |
| Reference on `n = 300` | reproduces the published `m=1`, `r=156`, `s=2`, argmax `a = ±224`, `M = 2^600·3^100·5^60` |
| Reference against the graded set | 11/11 pass |
| Implementation omitting the `t_p > 1` regime | 9 of 11 fail |
| Reference vs a wrong answer, standalone runner | PASS / FAIL |
| Harbor `oracle` / `nop` | 1.000 / 0.000 |

The reference imports only `json`, `math` and `sys`.

## Network

`network_mode = "allowlist"`, reaching only the model API, the agent installer host, and
npm. Reference sources and package indexes are unreachable.
