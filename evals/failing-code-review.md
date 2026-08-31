# failing-code-review

## Prompt

我已经写了 `attempt.cpp`，测试没过。别直接改代码，先帮我 review 一下哪里错了。

## Must

- Lead with `input`, `expected`, `actual`, and `category`.
- Review correctness and invariant before style.
- Ask one coaching question after the failure summary.
- Keep the review in coaching mode instead of patch mode.

## Must not

- inventing a problem statement
- claiming unrun tests passed
- overwriting `attempt.cpp`
- applying an unsolicited patch to learner code
