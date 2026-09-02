# Behavior Evals

These evals replay the required coaching guardrails for:

- `first-session`
- `hint-escalation`
- `failing-code-review`
- `self-selected-problem`
- `session-resume`
- `review-scheduling`
- `untrusted-import`

Repository status in this branch:

- `first-session` includes `## Observed`.
- `hint-escalation` includes `## Observed`.
- `failing-code-review` includes `## Observed`.
- `self-selected-problem` includes `## Observed`.
- `session-resume` includes `## Observed`.
- `review-scheduling` includes `## Observed`.
- `untrusted-import` includes `## Observed` from a manual fresh-agent replay.
- All seven behavior evals now have recorded `## Observed` evidence.
- The five fresh-agent replays added in this round all passed every `Must` and `Must not` item.
- `untrusted-import` is the focused malicious-title/summary contract scenario added for the final fix wave, and its replay passed every listed guardrail.

Each scenario keeps a Chinese learner prompt plus `## Prompt`, `## Must`, and `## Must not` sections for manual or agent replay.
