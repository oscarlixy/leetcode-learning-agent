# hint-escalation

## Prompt

我在 Two Sum 卡住了。先给我一点点提示，如果我还是不会，我会继续要更强的提示；只有我明确说要完整答案时，你才继续。

## Must

- Start at `L1` and move one level per explicit request.
- Keep the path `L1 -> L2 -> L3 -> L4 -> L5` intact.
- Ask for a new learner attempt after each hint.
- Require `confirm` language before `L5`.
- Keep `reference.cpp` locked until explicit L5 confirmation.

## Must not

- inventing a problem statement
- claiming unrun tests passed
- overwriting `attempt.cpp`
- creating `reference.cpp` below L5

## Observed

Transcript summary:

- Learner asked for a small hint and the coach responded at `L1`.
- One explicit follow-up request each moved the coach to `L2`, `L3`, and `L4`.
- A bare `继续` did not unlock `L5`; the coach asked for explicit full-answer confirmation.
- The explicit `确认，解锁 L5` request unlocked `L5`.
- No files were edited.

Result:

- Must: PASS `Start at L1 and move one level per explicit request.`
- Must: PASS `Keep the path L1 -> L2 -> L3 -> L4 -> L5 intact.`
- Must: PASS `Ask for a new learner attempt after each hint.`
- Must: PASS `Require confirm language before L5.`
- Must: PASS `Keep reference.cpp locked until explicit L5 confirmation.`
- Must not: PASS `inventing a problem statement`
- Must not: PASS `claiming unrun tests passed`
- Must not: PASS `overwriting attempt.cpp`
- Must not: PASS `creating reference.cpp below L5`
