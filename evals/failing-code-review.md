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

## Observed

- Opening summary began with `input nums=[3,3], target=6`, `expected [0,1]`, `actual [0,0]`, and `category correctness+invariant`.
- The review identified the core bug as inserting the current element before checking its complement, which allows self-pairing and produces the duplicate-index result.
- The explanation prioritized correctness and invariant reasoning before any style commentary.
- Exactly one coaching question followed the failure summary.
- The replay stayed read-only: no patch was proposed or applied, `attempt.cpp` was not overwritten, no test `PASS` was claimed, and no problem statement details were invented.

Result:

- Must: PASS `Lead with input, expected, actual, and category.`
- Must: PASS `Review correctness and invariant before style.`
- Must: PASS `Ask one coaching question after the failure summary.`
- Must: PASS `Keep the review in coaching mode instead of patch mode.`
- Must not: PASS `inventing a problem statement`
- Must not: PASS `claiming unrun tests passed`
- Must not: PASS `overwriting attempt.cpp`
- Must not: PASS `applying an unsolicited patch to learner code`
