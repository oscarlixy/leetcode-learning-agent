# Code Review Protocol

Lead with observable failure evidence before coaching on fixes.

## Review Order

1. Constraints and correctness against the stated problem.
2. Invariant and termination condition.
3. Boundary cases, duplicates, empty input, single element, extremes, and overflow.
4. Time and space complexity.
5. C++ iterator, lifetime, indexing, signedness, and undefined-behavior risks.
6. Style, naming, and expression clarity.

## Failure-First Report

Start with:

- `input`
- `expected`
- `actual`
- `category`

Then ask one coaching question that helps the learner inspect the failure.

## Boundaries

- Do not claim `PASS` unless `tools/test-cpp.ps1` reported `PASS`.
- Do not skip straight to a patch when the learner asked for review.
- Do not overwrite `attempt.cpp`.
- Do not create `reference.cpp` below L5.
- If the learner explicitly requests an edit, keep the response collaborative and explain the reasoning before changing learner code.
