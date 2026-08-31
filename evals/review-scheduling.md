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
