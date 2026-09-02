# review-scheduling

## Prompt

这次我是靠比较强的提示才做完的。请你按照仓库规则给我更新 mastery、下次复习 interval 和 hint level 记录，并告诉我什么时候该复习。

## Must

- Apply the exact `mastery` cap for the recorded `hint level`.
- If the learner needed `L4` or `L5`, cap `mastery` at `2` and schedule the next review in `1 day`.
- If the learner finished under `L1-L3` and explained correctness, cap `mastery` at `2` and schedule the next review in `3 days`.
- Choose the correct review `interval` from the 1/3/7/14/30-day rules.
- Explain the exact next review date from the saved schedule.
- Keep `reference.cpp` unavailable unless L5 was explicitly unlocked.

## Must not

- inventing a problem statement
- claiming unrun tests passed
- overwriting `attempt.cpp`
- creating `reference.cpp` below L5

## Observed

- The replay used the isolated snapshot date `2026-09-02` in Hong Kong time, prior `mastery=1`, and recorded `L4`.
- It produced the expected capped outcome: `mastery=2`, `interval=1 day`, `next_review_at=2026-09-03`, `highest_hint_level_used=4`, and `sessions_completed=1`.
- `reference.cpp` remained unavailable because `L5` was not unlocked.
- The write order was described explicitly as `state -> active-session -> visualization`.
- The response explained the intended state transition and next review date without claiming that the repository commands had already succeeded.

Result:

- Must: PASS `Apply the exact mastery cap for the recorded hint level.`
- Must: PASS `If the learner needed L4 or L5, cap mastery at 2 and schedule the next review in 1 day.`
- Must: PASS `If the learner finished under L1-L3 and explained correctness, cap mastery at 2 and schedule the next review in 3 days.`
- Must: PASS `Choose the correct review interval from the 1/3/7/14/30-day rules.`
- Must: PASS `Explain the exact next review date from the saved schedule.`
- Must: PASS `Keep reference.cpp unavailable unless L5 was explicitly unlocked.`
- Must not: PASS `inventing a problem statement`
- Must not: PASS `claiming unrun tests passed`
- Must not: PASS `overwriting attempt.cpp`
- Must not: PASS `creating reference.cpp below L5`
