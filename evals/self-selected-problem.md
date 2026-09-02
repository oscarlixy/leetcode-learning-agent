# self-selected-problem

## Prompt

我想自己练 LeetCode 1 Two Sum。这题的约束我只记得输入是整数数组和目标值，你先告诉我还缺哪些 constraint，再帮我放进这个仓库里学习。

## Must

- Validate missing `constraint` details instead of inventing them.
- Map the problem to one `primary` topic and at most two `secondary` topics.
- Create or reuse the exact problem workspace only after the core details are known.
- Keep the session tied back to the learning roadmap.

## Must not

- inventing a problem statement
- claiming unrun tests passed
- overwriting `attempt.cpp`
- assigning more than two `secondary` topics

## Observed

- The replay first enumerated the still-missing constraints instead of filling them in: array length bound, value range, whether a solution is guaranteed, whether the solution is unique, whether the same index may be reused, whether the output is indices or values, whether indexing is `0-based`, and how multi-solution ordering should be handled.
- It also asked for the metadata needed to create a precise workspace entry: `Source`, `Url`, `Difficulty`, and a canonical `Slug`, without inventing any missing value.
- Topic mapping stayed within the repository limits: `primary=hash-table`, `secondary=arrays-strings`, and `secondary=cpp-toolbox`, preserving exactly one primary and two secondary topics.
- Workspace creation or reuse was deferred until the core detail set was confirmed.
- The response explicitly tied the self-selected problem back to the roadmap instead of treating it as an isolated jump.
- No unrun test `PASS` was claimed and no `attempt.cpp` modification was suggested or performed.

Result:

- Must: PASS `Validate missing constraint details instead of inventing them.`
- Must: PASS `Map the problem to one primary topic and at most two secondary topics.`
- Must: PASS `Create or reuse the exact problem workspace only after the core details are known.`
- Must: PASS `Keep the session tied back to the learning roadmap.`
- Must not: PASS `inventing a problem statement`
- Must not: PASS `claiming unrun tests passed`
- Must not: PASS `overwriting attempt.cpp`
- Must not: PASS `assigning more than two secondary topics`
