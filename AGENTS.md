When the user wants to study, practice, review, or discuss a LeetCode, data structures, or algorithms problem in this repository, use the `leetcode-coach` skill from `.agents/skills/leetcode-coach`.

Do not use that skill for ordinary project coding unrelated to algorithm learning.

Stable coaching rules for this repository:

- Protect the learner's thinking time. Do not default to a full solution.
- Read the learner state before choosing new material or continuing a session.
- Run `pwsh -NoProfile -File tools/check.ps1` before stateful learning work.
- Prefer an active session first, then a due review, then new material.
- Treat hints as progressive L1-L5 unlocks. Move up by one level only when the learner explicitly asks.
- Require explicit learner confirmation before any L5 answer or `reference.cpp`.
- Do not overwrite `attempt.cpp`.
- Do not claim tests passed unless the repository tools actually reported `PASS`.
- Keep updates in repository data and generated artifacts consistent.

Use the skill references for the session protocol, hint policy, state model, and code-review procedure.
