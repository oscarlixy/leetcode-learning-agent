# State Model

Use the repository JSON files as the only structured source of truth. Repeat exact field names instead of paraphrasing them.

## `state.json`

- Root fields: `schema_version`, `current_topic_id`, `updated_at`, `topics`
- Per-topic fields: `mastery`, `status`, `last_studied_at`, `next_review_at`, `sessions_completed`, `best_independent_result`, `highest_hint_level_used`, `error_tags`
- `mastery` stays within 0-4.
- `highest_hint_level_used` stays within 0-5.
- `status` uses the repository values `unseen`, `learning`, `review`, `mastered`.

## `active-session.json`

- Fields: `schema_version`, `active`, `session_id`, `started_at`, `topic_id`, `problem_slug`, `phase`, `hint_level`, `last_updated_at`
- `phase` uses `recall`, `concept`, `solve`, `review`, `complete`.
- Resume from saved `phase` and `hint_level`; do not silently create a second active session.

## Scheduling Rules

Default review intervals are 1, 3, 7, 14, and 30 days.

- Needed L4 or L5 to finish: cap `mastery` at 2 and schedule the next review in 1 day.
- Finished under L1-L3 and can explain correctness: `mastery` may be 2 and the next review is in 3 days.
- Solved a standard problem independently: `mastery` may be 3 and the next review is in 7 or 14 days based on explanation quality and stability.
- Solved a variant independently and explained the boundary of the method: `mastery` may be 4 and the next review is in 30 days.
- Failed a due review: set `status` to `review`, reset the interval to 1 day, and lower `mastery` by at most one level.

Do not invent a separate review queue. Derive it from `next_review_at`.

## Write Sequence

- Validate and save state with `pwsh -NoProfile -File tools/update-state.ps1 -Kind state -CandidatePath learner/state.candidate.json`.
- Validate and save the active session with `pwsh -NoProfile -File tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json`.
- Refresh the visualization with `pwsh -NoProfile -File tools/update-visualization.ps1`.

Do not declare the session complete until the state write succeeds and the visualization is fresh.
