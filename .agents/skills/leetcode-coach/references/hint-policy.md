# Hint Policy

Hints are progressive. `hint_level` starts at 0 and increases by one step only after an explicit learner request for more help. A failed test run does not auto-escalate.

After every hint_level increase, save `active-session.json` with `pwsh -NoProfile -File tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json` so resume state stays current.

| Level | Agent may provide | Agent must not provide |
| --- | --- | --- |
| L1 | Restate key constraints, point out missed boundaries, ask for a manual trace | A specific algorithm template |
| L2 | Point to the relevant topic, ask the learner to inspect input structure or operation order | The key state, core data structure choice, or full steps |
| L3 | Give the critical invariant, state definition, or core data structure | Full pseudocode or code |
| L4 | Give a pseudocode skeleton, key loop structure, and verification checkpoints | A submission-ready implementation |
| L5 | Give the full derivation, reference implementation, alternatives, and complexity analysis | Overwriting the learner's original attempt |

After every hint, ask for a new learner attempt before offering another level.

## L5 Gate

- L5 requires explicit learner confirmation such as "Yes, unlock L5" or an equally direct request for the full answer.
- Do not jump to L5 because the learner sounds frustrated.
- Do not create `reference.cpp` until that explicit confirmation has been given and the session records `hint_level` 5.

## L5 Persistence Transaction

After explicit learner confirmation, complete these steps in order:

1. Set active-session `hint_level` to 5 and save it with `pwsh -NoProfile -File tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json`.
2. Set the exact workspace's problem `highest_hint_level_used` to 5. Also update honest lifecycle fields (`attempt_count`, problem `status`, and `last_attempted_at`) when an attempt occurred, then validate and atomically save with `pwsh -NoProfile -File tools/update-problem.ps1 -ProblemPath $ProblemPath -CandidatePath "$ProblemPath/meta.candidate.json"`.
3. Only then create `reference.cpp`, leaving `attempt.cpp` byte-for-byte learner-owned, and run `pwsh -NoProfile -File tools/check.ps1`.

If either save fails, do not create `reference.cpp`. Repair the candidate and retry the same ordered transaction; never weaken the explicit learner-confirmation gate.

## File Boundaries

- `attempt.cpp` cannot be overwritten or replaced by the coach.
- If the learner explicitly asks for edits inside `attempt.cpp`, keep the change collaborative and scoped to the requested line of work.
- `reference.cpp` is only for an explicitly unlocked L5 path.
