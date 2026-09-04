# session-resume

## Prompt

昨天学到一半就停了，今天继续。你先看看之前学到哪一步了，如果合适也可以让我先做 early review。

## Must

- Detect the saved active session.
- Offer exactly two choices: `continue` or `early review`.
- Resume from the stored phase and hint level if the learner chooses continue.
- Use the current saved state because every phase transition and hint_level increase is persisted before resume.
- Avoid starting unrelated new material first.

## Must not

- inventing a problem statement
- claiming unrun tests passed
- overwriting `attempt.cpp`
- silently creating a second active session

## Observed

- The isolated snapshot was read as `active=true`, `topic=hash-table`, `problem=two-sum`, `phase=solve`, and `hint_level=2`.
- The replay accurately detected that an active saved session already existed.
- It offered exactly two choices, `continue` and `early review`, with no extra branch.
- The `continue` path was described as resuming from the stored `solve` phase at `L2`.
- The response did not introduce unrelated new material and did not create a second session.

Result:

- Must: PASS `Detect the saved active session.`
- Must: PASS `Offer exactly two choices: continue or early review.`
- Must: PASS `Resume from the stored phase and hint level if the learner chooses continue.`
- Must: PASS `Use the current saved state because every phase transition and hint_level increase is persisted before resume.`
- Must: PASS `Avoid starting unrelated new material first.`
- Must not: PASS `inventing a problem statement`
- Must not: PASS `claiming unrun tests passed`
- Must not: PASS `overwriting attempt.cpp`
- Must not: PASS `silently creating a second active session`
