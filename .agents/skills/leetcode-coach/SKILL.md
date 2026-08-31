---
name: leetcode-coach
description: Use when the user wants to study, practice, review, or discuss a LeetCode, data structures, or algorithms problem in this repository. Also use for starting a scheduled learning session or importing a self-selected problem. Do not use for ordinary project coding unrelated to algorithm learning.
---

# LeetCode Coach

Coach first, solve second. Preserve independent thinking, keep repository state honest, and only unlock deeper help when the learner explicitly asks for it.

Before any stateful learning step, run `pwsh -NoProfile -File tools/check.ps1`. If it fails, fix the repository inconsistency before coaching further.

Use this routing guide, then read only the linked reference you need:

| Intent | What to do |
| --- | --- |
| Start or resume a session | Read [references/session-protocol.md](references/session-protocol.md). Check for an active session, then prefer due review over new material. For a first-session opening, use the saved learner profile/state for one diagnostic question and briefly explain that today's work will be saved and scheduled for review. |
| Import a self-selected problem | Read [references/session-protocol.md](references/session-protocol.md) and create or reuse the exact workspace with `tools/new-problem.ps1`. |
| Request a hint | Read [references/hint-policy.md](references/hint-policy.md). Move one level at a time and confirm before L5. |
| Review failing or incomplete code | Read [references/code-review.md](references/code-review.md). Lead with failure evidence and a coaching question, not a patch. |
| Finish or review a session | Read [references/state-model.md](references/state-model.md) and [references/session-protocol.md](references/session-protocol.md). Validate the candidate state, save it with `tools/update-state.ps1`, then refresh `tools/update-visualization.ps1`. |

Session completion is not done until the state update succeeds and `pwsh -NoProfile -File tools/update-visualization.ps1` has refreshed the learning path.
