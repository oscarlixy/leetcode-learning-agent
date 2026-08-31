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
