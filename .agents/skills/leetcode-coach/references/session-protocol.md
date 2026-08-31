# Session Protocol

Run `pwsh -NoProfile -File tools/check.ps1` before any stateful learning work.

## Start

- If `learner/active-session.json` has `active: true`, offer exactly two options: continue the current session or do an early review from the saved state.
- If there is no active session, prefer a due review where `next_review_at` is today or earlier before assigning new material.
- Use one main goal per session.
- For a first-session opening, ask exactly one diagnostic question that either asks about the learner's existing experience or asks them to explain an already-known concept from repository profile/state.
- That one opening question must introduce no new problem input/output, sample values, code snippet, or fabricated prompt.
- Allowed shape example: `Before we pick today's first exercise, what C++ STL containers or operations already feel comfortable to you, and which ones still feel fuzzy?`
- In that same opening, briefly tell the learner that today's session will be saved in the repository state and scheduled for review at the end.
- For a self-selected problem, create or reuse the workspace with:
  `pwsh -NoProfile -File tools/new-problem.ps1 -RepoRoot (Resolve-Path '.') -ProblemId $ProblemId -Slug $Slug -Title $Title -Source $Source -Url $Url -Difficulty $Difficulty -PrimaryTopicId $PrimaryTopicId -SecondaryTopicIds $SecondaryTopicIds`
  Set those variables from validated learner-provided metadata: `ProblemId`, `Slug`, `Title`, `Source`, `Url`, `Difficulty`, `PrimaryTopicId`, and at most two `SecondaryTopicIds`; do not hardcode a specific problem.

## Transition Map

- `start -> recall`: pick the active session, due review, or lowest-mastery unlocked topic.
- `recall -> concept`: after 3-5 minutes of one or two recall questions.
- `concept -> solve`: after 5-8 minutes of concept modeling, examples, and learner restatement.
- `solve -> review`: after 15-20 minutes of learner-led solving, testing, and debugging.
- `review -> schedule`: after 5-8 minutes of invariant, complexity, blocker, edge-case, and transfer reflection.
- After every phase transition, save `active-session.json` with `pwsh -NoProfile -File tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json`.

## Recall

- Ask one focused question first when the learner is brand new or rusty.
- For a first session, start from `diagnosis` instead of assigning a random full problem.
- Use a profile/state-grounded question about existing experience or an already-known concept, without adding invented inputs, outputs, values, code, or a fabricated mini exercise.

## Concept

- Use short examples, hand simulation, and invariants.
- Do not skip directly to a complete algorithm template.

## Solve

- Learner clarifies input, output, and boundaries.
- Learner states a baseline idea and target complexity.
- Learner edits `attempt.cpp`.
- Use `pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath problems/1-two-sum` when the workspace exists and testing helps.
- Report `PASS`, `FAIL`, or `SKIPPED` exactly as the tool reports. Never imply unrun tests passed.

## Review

- Use `review.md` to capture invariant, complexity, original blocker, edge cases, and transfer signal.
- If the learner stopped mid-session, keep the saved `phase` and `hint_level` aligned with what actually happened.
- Resume behavior depends on the current saved phase and hint level, so keep the active session current after each transition.

## Schedule

- Draft a candidate learner state update before announcing completion.
- Save it with `pwsh -NoProfile -File tools/update-state.ps1 -Kind state -CandidatePath learner/state.candidate.json`.
- Save any active-session update with `pwsh -NoProfile -File tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json`.
- Refresh the visualization with `pwsh -NoProfile -File tools/update-visualization.ps1`.
- Completion requires a valid state write and a fresh visualization.
