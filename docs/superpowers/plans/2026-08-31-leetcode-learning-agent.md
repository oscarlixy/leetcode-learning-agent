# LeetCode Learning Agent Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Codex-native, C++-focused LeetCode learning harness that enforces Socratic coaching, persists mastery and review state, validates its own files, and generates an interactive learning-path view.

**Architecture:** Keep durable policy in `AGENTS.md` and a repository skill, structured truth in versioned JSON, human reflection in Markdown, and repeatable mechanics in dependency-free PowerShell modules and entry scripts. Treat the visualization as a deterministic projection of curriculum and learner state, never as another state store.

**Tech Stack:** Codex `AGENTS.md`, Agent Skills (`SKILL.md` plus references), PowerShell 7 with Windows PowerShell 5.1-compatible syntax where practical, JSON Schema Draft 2020-12 documents, C++20, HTML/CSS/vanilla JavaScript, Git.

**Spec:** `docs/superpowers/specs/2026-08-31-leetcode-learning-agent-design.md`

## Global Constraints

- Default language is C++20; the harness must not install a compiler or any other dependency automatically.
- A learning session targets 30–45 minutes and exactly one primary learning objective.
- The teaching mode is Socratic with five progressive hint levels; L5 requires explicit learner confirmation.
- Never overwrite a learner file such as `problems/1-two-sum/attempt.cpp`; create `reference.cpp` only after L5 is recorded.
- JSON is the sole structured source of truth; Markdown and HTML are derived or narrative artifacts.
- Core operation must not depend on OpenAI API, LeetCode API, web scraping, Python, Node.js, CMake, Pester, a database, or a web server.
- Missing compiler means `SKIPPED`, not `PASS` or `FAIL`, and the agent must say that code was not executed.
- All timestamps use timezone-aware ISO 8601 strings; review dates use `YYYY-MM-DD`; learner timezone is `Asia/Hong_Kong`.
- PowerShell writes learner state through a validated same-directory temporary file and preserves the previous valid state as `learner/state.backup.json`.
- The curriculum is a directed acyclic graph and the initial scope is the 15 approved foundation nodes.

## Planned File Map

| Path | Responsibility |
| --- | --- |
| `AGENTS.md` | Stable repository-wide coaching contract and skill routing |
| `README.md` | Learner-facing setup, commands, session examples, and limitations |
| `.agents/skills/leetcode-coach/SKILL.md` | Trigger rules, orchestration, and non-negotiable coaching guardrails |
| `.agents/skills/leetcode-coach/references/*.md` | Focused session, hint, state, and C++ review protocols |
| `schemas/*.schema.json` | Version 1 machine-readable contracts |
| `curriculum/roadmap.json` | Foundation knowledge graph and completion criteria |
| `learner/*.json` | Profile, durable mastery, active session, and last valid backup |
| `problems/_template/*` | C++ problem workspace template |
| `tools/lib/Validation.psm1` | Parse and validate all harness documents and graph references |
| `tools/lib/JsonStore.psm1` | Same-directory atomic JSON replacement and backup |
| `tools/lib/ProblemWorkspace.psm1` | Validate and create a problem workspace without overwrite |
| `tools/lib/Compiler.psm1` | Detect compiler, build invocation, run with timeout, classify result |
| `tools/lib/Visualization.psm1` | Compute input hash and generate/freshness-check learning path |
| `tools/*.ps1` | Thin command entry points for doctor, creation, update, checks, tests, and visualization |
| `visualization/*` | Interactive template and generated current learning path |
| `tests/harness/*` | Dependency-free PowerShell unit and integration tests |
| `tests/fixtures/cpp/pass/*` | Compiler-runner sample that passes when a compiler is available |
| `evals/*` | Human/Codex behavior scenarios with explicit required and forbidden behavior |
| `sessions/.gitkeep` | Versioned destination for future session notes |

---

### Task 1: Versioned Data Contracts and Initial Learning State

**Files:**
- Create: `tests/harness/TestSupport.ps1`
- Create: `tests/harness/run-tests.ps1`
- Create: `tests/harness/Validation.Tests.ps1`
- Create: `tools/lib/Validation.psm1`
- Create: `schemas/profile.schema.json`
- Create: `schemas/roadmap.schema.json`
- Create: `schemas/state.schema.json`
- Create: `schemas/active-session.schema.json`
- Create: `schemas/problem.schema.json`
- Create: `curriculum/roadmap.json`
- Create: `learner/profile.json`
- Create: `learner/state.json`
- Create: `learner/state.backup.json`
- Create: `learner/active-session.json`
- Create: `sessions/.gitkeep`

**Interfaces:**
- Consumes: Approved field names and mastery semantics from the design spec.
- Produces: `Read-JsonDocument(Path)`, `Assert-ProfileDocument(Document)`, `Assert-RoadmapDocument(Document)`, `Assert-StateDocument(Document, Roadmap)`, `Assert-ActiveSessionDocument(Document, Roadmap, ProblemsRoot)`, `Assert-ProblemDocument(Document, Roadmap)`, and `Get-RoadmapNodeIds(Roadmap)` exported by `Validation.psm1`.

- [ ] **Step 1: Create the dependency-free test runner and failing contract tests**

Create `tests/harness/TestSupport.ps1` with exact assertion behavior:

```powershell
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Throws {
    param([scriptblock]$Script, [string]$MessagePattern)
    try { & $Script } catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "Exception did not match [$MessagePattern]: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected exception matching [$MessagePattern]"
}
```

Create `tests/harness/run-tests.ps1` so it accepts optional `-TestFile`, runs matching `*.Tests.ps1` files in separate child scopes, prints lines such as `PASS Validation.Tests.ps1` or `FAIL Validation.Tests.ps1: mastery out of range`, and exits 1 when any file fails.

Create `Validation.Tests.ps1` to import `tools/lib/Validation.psm1`, parse the four initial JSON files, and assert:

```powershell
$roadmap = Read-JsonDocument "$RepoRoot/curriculum/roadmap.json"
$profile = Read-JsonDocument "$RepoRoot/learner/profile.json"
$state = Read-JsonDocument "$RepoRoot/learner/state.json"
$active = Read-JsonDocument "$RepoRoot/learner/active-session.json"

Assert-ProfileDocument $profile
Assert-RoadmapDocument $roadmap
Assert-StateDocument $state $roadmap
Assert-ActiveSessionDocument $active $roadmap "$RepoRoot/problems"
Assert-Equal 15 $roadmap.nodes.Count 'Roadmap node count mismatch.'
Assert-Equal 'diagnosis' $state.current_topic_id 'Initial topic must be diagnosis.'

$badState = $state | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$badState.topics.diagnosis.mastery = 5
Assert-Throws { Assert-StateDocument $badState $roadmap } 'mastery'

$cyclic = $roadmap | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$cyclic.nodes[0].prerequisites = @('dynamic-programming')
Assert-Throws { Assert-RoadmapDocument $cyclic } 'cycle'
```

- [ ] **Step 2: Run the contract test and confirm the missing module/data failure**

Run:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Validation.Tests.ps1
```

Expected: exit 1 because `tools/lib/Validation.psm1` or the initial JSON documents do not exist.

- [ ] **Step 3: Add all five JSON schemas with closed version 1 contracts**

Each schema must declare:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version"],
  "properties": {
    "schema_version": { "const": 1 }
  }
}
```

Extend each file with every required property and enum from spec section 5. Use `null` unions for inactive or never-studied values. In `roadmap.schema.json`, require node objects with `id`, `title`, `stage`, `objectives`, `completion_criteria`, `prerequisites`, and `recommended_problems`. In `state.schema.json`, require topic state objects with mastery range 0–4, hint range 0–5, unique `error_tags`, and no additional fields.

- [ ] **Step 4: Create the 15-node roadmap and aligned initial learner documents**

Use these stable node IDs in this order:

```text
diagnosis
complexity
cpp-toolbox
arrays-strings
linked-list
stack-queue
hash-table
sorting-binary-search
recursion-backtracking
binary-tree
heap-priority-queue
bfs-dfs
graph
greedy
dynamic-programming
```

Encode prerequisites so every advanced node is reachable and the graph remains acyclic. At minimum: `complexity <- diagnosis`, `cpp-toolbox <- diagnosis`, linear structures require both `complexity` and `cpp-toolbox`, `binary-tree <- recursion-backtracking`, `bfs-dfs <- stack-queue + recursion-backtracking`, `graph <- bfs-dfs`, and `dynamic-programming <- arrays-strings + recursion-backtracking`.

Use this exact initial curriculum content; `local:` entries are concept exercises rather than copied LeetCode statements:

| Node | Objective | Completion criterion | Recommended problems |
| --- | --- | --- | --- |
| `diagnosis` | Calibrate STL reading, tracing, and basic complexity | Explain common STL operations and trace a simple loop | `local:cpp-reading`, `local:loop-tracing` |
| `complexity` | Relate input size to operations and extra storage | Derive time/space complexity and identify the bottleneck | `local:complexity-table`, `local:nested-loop-analysis` |
| `cpp-toolbox` | Use core C++ containers and avoid lifetime hazards | Select a fitting STL container and explain iterator/overflow risks | `local:stl-container-choice`, `local:iterator-safety` |
| `arrays-strings` | Learn traversal, two pointers, windows, and prefix information | State a loop invariant and handle empty/singleton boundaries | `26:remove-duplicates-from-sorted-array`, `344:reverse-string` |
| `linked-list` | Learn pointer rewiring, sentinels, and fast/slow pointers | Draw pointer changes and handle empty/head/tail cases | `206:reverse-linked-list`, `141:linked-list-cycle` |
| `stack-queue` | Connect restricted order to parsing and traversal | Explain why LIFO or FIFO matches the problem | `20:valid-parentheses`, `232:implement-queue-using-stacks` |
| `hash-table` | Trade space for lookup, counting, and deduplication | Explain the meaning of each key/value and the space cost | `1:two-sum`, `242:valid-anagram` |
| `sorting-binary-search` | Use ordering to reduce search and prove interval updates | Maintain a search-interval invariant without dead loops | `704:binary-search`, `75:sort-colors` |
| `recursion-backtracking` | Model subproblems, choice trees, undo, and pruning | Define base case, state, choice, and rollback | `78:subsets`, `46:permutations` |
| `binary-tree` | Learn traversals and top-down/bottom-up aggregation | Choose traversal order and explain returned subtree information | `104:maximum-depth-of-binary-tree`, `94:binary-tree-inorder-traversal` |
| `heap-priority-queue` | Maintain only the currently most important elements | Choose min-heap or max-heap for a Top-K invariant | `215:kth-largest-element-in-an-array`, `703:kth-largest-element-in-a-stream` |
| `bfs-dfs` | Compare level expansion with path exploration | Define state, neighbors, visited rule, and termination | `200:number-of-islands`, `994:rotting-oranges` |
| `graph` | Learn adjacency, connectivity, dependencies, and basic paths | Choose a graph representation and traversal from edge properties | `207:course-schedule`, `1971:find-if-path-exists-in-graph` |
| `greedy` | Justify local choices with invariants or exchange arguments | Explain why the choice cannot discard an optimum | `455:assign-cookies`, `55:jump-game` |
| `dynamic-programming` | Derive state and transition from repeated recursion | State semantics, transition, base values, order, and answer location | `70:climbing-stairs`, `198:house-robber` |

Initialize every topic to:

```json
{
  "mastery": 0,
  "status": "unseen",
  "last_studied_at": null,
  "next_review_at": null,
  "sessions_completed": 0,
  "best_independent_result": false,
  "highest_hint_level_used": 0,
  "error_tags": []
}
```

Set `current_topic_id` to `diagnosis`, set `active` to `false`, and use null for every inactive session field. Make `state.backup.json` initially identical to `state.json`.

- [ ] **Step 5: Implement strict validation and graph-cycle detection**

`Validation.psm1` must:

- Parse UTF-8 JSON with `ConvertFrom-Json -Depth 100` and wrap parse errors with the file path.
- Check required properties with `PSObject.Properties.Name` rather than truthiness, so `false`, `0`, and null remain valid values.
- Reject unknown schema versions, invalid enums, out-of-range mastery/hint values, duplicate node IDs, missing prerequisite IDs, cycles, state/roadmap node mismatches, and invalid date formats.
- Treat a null inactive-session field as valid only when `active` is false; require all session references when `active` is true.
- Export only the seven interfaces named above.

Cycle detection must use three states (`unvisited`, `visiting`, `visited`) and throw a message containing the repeated node ID and the word `cycle`.

- [ ] **Step 6: Run the contract test and the whole initial suite**

Run:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Validation.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
```

Expected: both commands exit 0 and report `PASS Validation.Tests.ps1`.

- [ ] **Step 7: Commit the contract foundation**

```powershell
git add schemas curriculum learner sessions tests/harness tools/lib/Validation.psm1
git commit -m "feat: add learning data contracts"
```

---

### Task 2: Atomic Learner-State and Active-Session Updates

**Files:**
- Create: `tests/harness/JsonStore.Tests.ps1`
- Create: `tools/lib/JsonStore.psm1`
- Create: `tools/update-state.ps1`
- Modify: `tools/lib/Validation.psm1`

**Interfaces:**
- Consumes: Task 1 validation functions and version 1 learner documents.
- Produces: `Write-JsonAtomic(Path, Value, Validation, BackupPath)`, `Save-LearnerDocument(Kind, CandidatePath, RepoRoot)`, and CLI forms `tools/update-state.ps1 -Kind state -CandidatePath learner/state.candidate.json` and `tools/update-state.ps1 -Kind active-session -CandidatePath learner/active-session.candidate.json`.

- [ ] **Step 1: Write failing tests for valid replacement and invalid rollback**

Create a unique test directory under `[System.IO.Path]::GetTempPath()`, copy `curriculum/roadmap.json` and `learner/` into it, and clean up only that resolved directory in `finally`.

The test must:

```powershell
$before = Get-Content -Raw $statePath
$candidate = Read-JsonDocument $statePath
$candidate.topics.diagnosis.mastery = 1
$candidate.topics.diagnosis.status = 'learning'
$candidate.updated_at = '2026-08-31T12:00:00+08:00'
$candidate | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 $candidatePath

Save-LearnerDocument -Kind state -CandidatePath $candidatePath -RepoRoot $TestRoot
$saved = Read-JsonDocument $statePath
Assert-Equal 1 $saved.topics.diagnosis.mastery 'Valid state was not saved.'
Assert-Equal $before (Get-Content -Raw "$TestRoot/learner/state.backup.json") 'Backup did not preserve the prior state.'

$invalid = Read-JsonDocument $statePath
$invalid.topics.diagnosis.mastery = 9
$invalid | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 $invalidPath
$stable = Get-Content -Raw $statePath
Assert-Throws { Save-LearnerDocument -Kind state -CandidatePath $invalidPath -RepoRoot $TestRoot } 'mastery'
Assert-Equal $stable (Get-Content -Raw $statePath) 'Invalid update changed state.json.'
```

Add an active-session case that saves `active: true`, `phase: solve`, an existing topic, and no problem slug; null problem slug is valid for concept-only sessions.

- [ ] **Step 2: Run the state-store test and verify it fails**

Run:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile JsonStore.Tests.ps1
```

Expected: exit 1 because `JsonStore.psm1` and `Save-LearnerDocument` do not exist.

- [ ] **Step 3: Implement same-directory atomic JSON replacement**

`Write-JsonAtomic` must serialize with `ConvertTo-Json -Depth 100`, write a UTF-8 no-BOM temporary file beside the destination, invoke the supplied validation scriptblock against the re-read temporary document, and then:

```powershell
if (Test-Path -LiteralPath $Path) {
    [System.IO.File]::Replace($tempPath, $Path, $BackupPath, $true)
} else {
    [System.IO.File]::Move($tempPath, $Path)
}
```

Always delete a surviving temporary file in `finally`. Reject a destination, backup, or candidate path that resolves outside `RepoRoot`. Do not accept wildcard paths.

`Save-LearnerDocument` must validate `state` against the roadmap and validate `active-session` against roadmap/problem references before invoking `Write-JsonAtomic`. For `state`, use `learner/state.backup.json`; for active session, omit a backup because durable progress remains in `state.json` and session notes.

- [ ] **Step 4: Add the thin CLI wrapper**

`tools/update-state.ps1` must set `$ErrorActionPreference = 'Stop'`, resolve the repository root from the script directory when `-RepoRoot` is absent, import `Validation.psm1` and `JsonStore.psm1`, call `Save-LearnerDocument`, print `UPDATED state` or `UPDATED active-session`, and exit 1 with a concrete line such as `ERROR mastery must be between 0 and 4` on failure.

- [ ] **Step 5: Run focused and full tests**

Run:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile JsonStore.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
```

Expected: both exit 0; the invalid candidate leaves the valid state byte-for-byte unchanged.

- [ ] **Step 6: Commit atomic state updates**

```powershell
git add tests/harness/JsonStore.Tests.ps1 tools/lib/JsonStore.psm1 tools/lib/Validation.psm1 tools/update-state.ps1
git commit -m "feat: add atomic learner state updates"
```

---

### Task 3: Safe Problem Workspace Creation

**Files:**
- Create: `tests/harness/ProblemWorkspace.Tests.ps1`
- Create: `tools/lib/ProblemWorkspace.psm1`
- Create: `tools/new-problem.ps1`
- Create: `problems/_template/meta.json`
- Create: `problems/_template/attempt.cpp`
- Create: `problems/_template/tests.cpp`
- Create: `problems/_template/review.md`

**Interfaces:**
- Consumes: Task 1 roadmap/problem validation and Task 2 atomic JSON writer.
- Produces: `New-ProblemWorkspace(RepoRoot, ProblemId, Slug, Title, Source, Url, Difficulty, PrimaryTopicId, SecondaryTopicIds)` returning the created absolute directory path; CLI with matching named parameters.

- [ ] **Step 1: Write failing creation, reference, and no-overwrite tests**

Build a safe temporary repository fixture with copies of the roadmap and problem template. Assert that:

```powershell
$problemParameters = @{
    RepoRoot = $TestRoot
    ProblemId = '1'
    Slug = 'two-sum'
    Title = 'Two Sum'
    Source = 'leetcode'
    Url = 'https://leetcode.com/problems/two-sum/'
    Difficulty = 'easy'
    PrimaryTopicId = 'hash-table'
    SecondaryTopicIds = @('arrays-strings')
}
$created = New-ProblemWorkspace @problemParameters

Assert-True (Test-Path "$created/attempt.cpp") 'attempt.cpp was not created.'
Assert-True (Test-Path "$created/tests.cpp") 'tests.cpp was not created.'
$meta = Read-JsonDocument "$created/meta.json"
Assert-Equal 'hash-table' $meta.primary_topic_id 'Primary topic mismatch.'
Assert-Equal 1 $meta.secondary_topic_ids.Count 'Secondary topics mismatch.'
Assert-True (-not (Test-Path "$created/reference.cpp")) 'Reference must not exist initially.'

Set-Content -LiteralPath "$created/attempt.cpp" -Value '// learner work' -Encoding utf8
Assert-Throws { New-ProblemWorkspace @problemParameters } 'already exists'
Assert-Equal '// learner work' (Get-Content -Raw "$created/attempt.cpp").Trim() 'Existing attempt was overwritten.'
```

Also reject a slug containing path separators, an unknown primary topic, more than two secondary topics, duplicate topics, and a source outside `leetcode|local`.

- [ ] **Step 2: Run the workspace test and verify it fails**

Run:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile ProblemWorkspace.Tests.ps1
```

Expected: exit 1 because `New-ProblemWorkspace` is unavailable.

- [ ] **Step 3: Create the C++20 problem template**

`attempt.cpp` must contain a compilable instructional shell without an algorithm answer:

```cpp
#include <algorithm>
#include <cstdint>
#include <deque>
#include <limits>
#include <map>
#include <queue>
#include <set>
#include <stack>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using namespace std;

class Solution {
public:
    // Write the LeetCode method signature and your implementation here.
};
```

`tests.cpp` must include `attempt.cpp`, define `int main()`, and contain comments showing where the learner adds assertions without embedding a solution. `review.md` must ask for invariant, complexity, original blocker, edge cases, and transfer signal. `meta.json` is a valid neutral template whose values are replaced before final validation.

- [ ] **Step 4: Implement validated create-without-overwrite behavior**

Normalize slug to lowercase ASCII letters, digits, and single hyphens; reject input rather than silently changing a nonconforming slug. Resolve a destination such as `problems/1-two-sum` from `ProblemId` and `Slug`, and verify it is a child of the resolved problems root. Create into a sibling staging directory, populate and validate `meta.json`, then move the complete staging directory to the final path. If the final path exists, throw before writing anything. Clean only the exact staging directory in `finally`.

- [ ] **Step 5: Add and exercise the CLI wrapper**

`tools/new-problem.ps1` forwards named parameters, prints a concrete line such as `CREATED C:\temp\leetcode-harness-tests\problems\1-two-sum`, and prints a concrete failure such as `ERROR problem workspace already exists` with exit 1. Run the CLI once against a temporary `-RepoRoot`; do not create a sample problem in the real `problems/` directory.

- [ ] **Step 6: Run focused and full tests**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile ProblemWorkspace.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
```

Expected: both exit 0 and the no-overwrite assertion passes.

- [ ] **Step 7: Commit problem scaffolding**

```powershell
git add problems/_template tests/harness/ProblemWorkspace.Tests.ps1 tools/lib/ProblemWorkspace.psm1 tools/new-problem.ps1
git commit -m "feat: add safe problem workspaces"
```

---

### Task 4: Compiler Diagnosis and C++ Test Runner

**Files:**
- Create: `tests/harness/Compiler.Tests.ps1`
- Create: `tests/fixtures/cpp/pass/attempt.cpp`
- Create: `tests/fixtures/cpp/pass/tests.cpp`
- Create: `tools/lib/Compiler.psm1`
- Create: `tools/doctor.ps1`
- Create: `tools/test-cpp.ps1`

**Interfaces:**
- Consumes: A problem directory containing `tests.cpp`, optionally including `attempt.cpp`.
- Produces: `Find-CppCompiler(CandidateCommands)`, `Get-CppCompileCommand(Compiler, SourcePath, OutputPath)`, `Invoke-CppProblemTest(ProblemPath, TimeoutSeconds, CompilerPath)` returning `{ Status, Compiler, ExitCode, Output, DurationMs }`; CLI output beginning with `PASS`, `FAIL`, or `SKIPPED`.

- [ ] **Step 1: Write failing deterministic compiler-selection and command tests**

Test compiler absence without depending on the developer machine:

```powershell
$none = Find-CppCompiler -CandidateCommands @('leetcode-compiler-that-does-not-exist')
Assert-Equal $null $none 'Missing compiler must return null.'

$gnu = [pscustomobject]@{ Family = 'gnu'; Path = 'g++' }
$gnuCommand = Get-CppCompileCommand $gnu 'C:/work/tests.cpp' 'C:/work/tests.exe'
Assert-True ($gnuCommand.Arguments -contains '-std=c++20') 'GNU command lacks C++20.'
Assert-True ($gnuCommand.Arguments -contains '-Wall') 'GNU command lacks warnings.'

$msvc = [pscustomobject]@{ Family = 'msvc'; Path = 'cl.exe' }
$msvcCommand = Get-CppCompileCommand $msvc 'C:/work/tests.cpp' 'C:/work/tests.exe'
Assert-True ($msvcCommand.Arguments -contains '/std:c++20') 'MSVC command lacks C++20.'
Assert-True ($msvcCommand.Arguments -contains '/W4') 'MSVC command lacks warnings.'
```

Call `Invoke-CppProblemTest` with an explicitly missing compiler path and assert `Status = SKIPPED`, `ExitCode = 0`, and output mentioning compiler installation.

- [ ] **Step 2: Run the compiler test and verify it fails**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Compiler.Tests.ps1
```

Expected: exit 1 because `Compiler.psm1` is absent.

- [ ] **Step 3: Implement compiler detection and command construction**

Detection order is `cl.exe`, `clang++.exe`, `g++.exe`, unless tests pass explicit candidates. Produce family-specific arguments:

```text
MSVC: /nologo /std:c++20 /W4 /EHsc $SourcePath /Fe:$OutputPath
Clang/GCC: -std=c++20 -Wall -Wextra -Wpedantic $SourcePath -o $OutputPath
```

Use `System.Diagnostics.ProcessStartInfo` with `UseShellExecute = false`, redirected stdout/stderr, and argument lists rather than interpolated shell commands. Kill the process tree after `TimeoutSeconds`. Compile failures, runtime failures, timeouts, and assertion failures return `FAIL`; no compiler returns `SKIPPED`; successful compile and zero-exit execution return `PASS`.

Place build output under the problem directory `.build/` and never delete learner source. The runner may replace its own explicit executable in `.build/`.

- [ ] **Step 4: Add doctor and test entry scripts**

`doctor.ps1` prints one line per capability and ends with `READY` when a compiler exists or `LIMITED` when learning can continue without execution. `test-cpp.ps1` accepts `-ProblemPath`, optional `-TimeoutSeconds` defaulting to 5, and optional `-CompilerPath` for deterministic tests; print the result status first and exit 1 only for `FAIL`.

- [ ] **Step 5: Add a trivial passing fixture and run available paths**

`tests/fixtures/cpp/pass/attempt.cpp`:

```cpp
int add(int a, int b) { return a + b; }
```

`tests/fixtures/cpp/pass/tests.cpp`:

```cpp
#include <cassert>
#include "attempt.cpp"
int main() {
    assert(add(2, 3) == 5);
    return 0;
}
```

Run:

```powershell
pwsh -NoProfile -File tools/doctor.ps1
pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath tests/fixtures/cpp/pass
pwsh -NoProfile -File tests/harness/run-tests.ps1
```

Expected on the current machine: doctor ends with `LIMITED`, the C++ fixture reports `SKIPPED`, and the PowerShell suite passes. On a machine with a compiler, doctor ends with `READY` and the fixture reports `PASS`.

- [ ] **Step 6: Commit compiler tooling**

```powershell
git add tests/harness/Compiler.Tests.ps1 tests/fixtures/cpp tools/lib/Compiler.psm1 tools/doctor.ps1 tools/test-cpp.ps1
git commit -m "feat: add C++ environment diagnostics"
```

---

### Task 5: Deterministic Interactive Learning-Path Visualization

**Files:**
- Create: `tests/harness/Visualization.Tests.ps1`
- Create: `tools/lib/Visualization.psm1`
- Create: `tools/update-visualization.ps1`
- Create: `visualization/learning-path.template.html`
- Create: `visualization/learning-path.html`

**Interfaces:**
- Consumes: `curriculum/roadmap.json` and `learner/state.json` validated by Task 1.
- Produces: `Get-LearningPathInputHash(RoadmapPath, StatePath)`, `Update-LearningPathVisualization(RepoRoot)`, `Test-LearningPathVisualizationFresh(RepoRoot)`, and a self-contained generated HTML file with embedded JSON and `data-input-hash`.

- [ ] **Step 1: Write failing generation and stale-detection tests**

In a temporary repo fixture, copy roadmap, state, and the visualization template. Assert:

```powershell
$output = Update-LearningPathVisualization -RepoRoot $TestRoot
Assert-True (Test-Path $output) 'Visualization was not generated.'
Assert-True (Test-LearningPathVisualizationFresh $TestRoot) 'Fresh visualization reported stale.'

$html = Get-Content -Raw $output
Assert-True ($html -match 'data-input-hash="[a-f0-9]{64}"') 'Input hash is missing.'
Assert-True ($html -match 'dynamic-programming') 'Roadmap nodes were not embedded.'

$state = Read-JsonDocument "$TestRoot/learner/state.json"
$state.topics.diagnosis.mastery = 1
$state | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 "$TestRoot/learner/state.json"
Assert-True (-not (Test-LearningPathVisualizationFresh $TestRoot)) 'Changed state was not detected.'
```

- [ ] **Step 2: Run the visualization test and verify it fails**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Visualization.Tests.ps1
```

Expected: exit 1 because `Visualization.psm1` is absent.

- [ ] **Step 3: Implement stable hashing and deterministic data embedding**

Compute SHA-256 of the exact roadmap bytes and state bytes, join their lowercase hashes with `:`, then SHA-256 that UTF-8 string. Escape `<`, `>`, `&`, U+2028, and U+2029 in embedded JSON so learner data cannot terminate the script element.

The template exposes exactly two replacement markers:

```text
__LEARNING_PATH_INPUT_HASH__
__LEARNING_PATH_DATA_JSON__
```

Fail if either marker is missing or appears more than once. Write generated HTML using a same-directory temporary file and move it over the prior generated file only after confirming the output contains the computed hash and both data roots.

- [ ] **Step 4: Build the accessible interactive template**

The generated page must:

- Group nodes into the approved four visual stages: foundation, linear structures, sorting/recursion/trees, and graph/composite search.
- Display text plus shape/status for unseen, learning, review, and mastered; do not rely on color alone.
- Mark `current_topic_id` and any `next_review_at` on or before the current Hong Kong date.
- Let keyboard and pointer users select a node to see objectives, completion criteria, mastery 0–4, next review, and recommended problems.
- Use responsive CSS that becomes a single column by 360px, contains no external network resources, and has no editable controls.
- Treat every inserted learner string as text via `textContent`, never `innerHTML`.

- [ ] **Step 5: Generate the checked-in initial visualization and run tests**

```powershell
pwsh -NoProfile -File tools/update-visualization.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Visualization.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
```

Expected: generation prints `UPDATED visualization/learning-path.html`; both test commands exit 0.

- [ ] **Step 6: Commit visualization generation**

```powershell
git add visualization tools/lib/Visualization.psm1 tools/update-visualization.ps1 tests/harness/Visualization.Tests.ps1
git commit -m "feat: visualize the learning path"
```

---

### Task 6: Repository-Wide Consistency Check

**Files:**
- Create: `tests/harness/Check.Tests.ps1`
- Create: `tools/check.ps1`
- Modify: `tools/lib/Validation.psm1`

**Interfaces:**
- Consumes: All contracts, problem workspaces, active session, learner state, and visualization freshness interfaces from Tasks 1–5.
- Produces: CLI `tools/check.ps1` and testable form `tools/check.ps1 -RepoRoot C:\temp\leetcode-harness-tests`, printing individual `OK` lines followed by `CHECK PASS`, or individual `ERROR` lines followed by `CHECK FAIL` and exit 1.

- [ ] **Step 1: Write failing end-to-end consistency cases**

Create a minimal valid repository fixture and run `tools/check.ps1 -RepoRoot $TestRoot` as a child PowerShell process. Assert exit 0 and `CHECK PASS`. Then independently mutate the fixture and assert exit 1 for each case:

```text
state mastery = 8                         -> message contains mastery
roadmap prerequisite references missing  -> message contains prerequisite
problem primary topic unknown             -> message contains primary_topic_id
active session topic unknown              -> message contains topic_id
reference.cpp with hint level 4           -> message contains reference.cpp
state changed after visualization build   -> message contains visualization
```

After each mutation, rebuild a clean fixture so one failure cannot mask another.

- [ ] **Step 2: Run the consistency test and verify it fails**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Check.Tests.ps1
```

Expected: exit 1 because `tools/check.ps1` is absent.

- [ ] **Step 3: Implement aggregated checks without partial mutation**

`check.ps1` is read-only. It must:

1. Parse and validate profile, roadmap, state, backup, and active session.
2. Enumerate only direct child directories of `problems/`, excluding `_template`.
3. Validate every `meta.json` and exact topic references.
4. Reject `reference.cpp` unless `highest_hint_level_used` equals 5.
5. Confirm an active problem slug resolves to exactly one workspace.
6. Confirm the generated visualization hash is fresh.
7. Accumulate all errors so a learner can fix them in one pass.

Use imported module functions; do not duplicate field-validation code in the CLI.

- [ ] **Step 4: Run focused and full checks**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile Check.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
pwsh -NoProfile -File tools/check.ps1
```

Expected: tests exit 0 and the real repository ends with `CHECK PASS`.

- [ ] **Step 5: Commit consistency checks**

```powershell
git add tests/harness/Check.Tests.ps1 tools/check.ps1 tools/lib/Validation.psm1
git commit -m "feat: validate harness consistency"
```

---

### Task 7: Codex Coaching Skill, Repository Contract, and Behavior Evals

**Files:**
- Create: `tests/harness/SkillContract.Tests.ps1`
- Create: `AGENTS.md`
- Create: `.agents/skills/leetcode-coach/SKILL.md`
- Create: `.agents/skills/leetcode-coach/references/session-protocol.md`
- Create: `.agents/skills/leetcode-coach/references/hint-policy.md`
- Create: `.agents/skills/leetcode-coach/references/state-model.md`
- Create: `.agents/skills/leetcode-coach/references/code-review.md`
- Create: `evals/README.md`
- Create: `evals/first-session.md`
- Create: `evals/hint-escalation.md`
- Create: `evals/failing-code-review.md`
- Create: `evals/self-selected-problem.md`
- Create: `evals/session-resume.md`
- Create: `evals/review-scheduling.md`

**Interfaces:**
- Consumes: Every tool and data contract completed in Tasks 1–6.
- Produces: Implicit/explicit `leetcode-coach` skill activation, five documented learning workflows, and behavior scenarios with `must`/`must_not` assertions.

- [ ] **Step 1: Load the skill-authoring guidance before editing the project skill**

Invoke and fully follow both available authoring skills:

```text
skill-creator
superpowers:writing-skills
```

Use their current validation scripts and structure rules where they are stricter than this plan. Do not package a plugin; this is a repository-scoped skill.

- [ ] **Step 2: Write failing static contract tests**

`SkillContract.Tests.ps1` must assert:

- `AGENTS.md` routes study/practice/review requests to `leetcode-coach`.
- `SKILL.md` frontmatter has exactly `name: leetcode-coach` and a description containing positive triggers plus a non-trigger for ordinary project coding.
- `SKILL.md` links all four reference files and all referenced paths exist.
- The hint reference names L1 through L5, contains an explicit L5 confirmation gate, and says `attempt.cpp` cannot be overwritten.
- The session reference contains start, recall, concept, solve, review, and schedule transitions.
- The state reference uses exact JSON field names from Task 1.
- The code-review reference orders correctness and invariants before style.
- Each eval file contains `## Prompt`, `## Must`, and `## Must not` sections.

Run the test before creating the instruction files and expect missing-file failure.

- [ ] **Step 3: Write concise root guidance and skill frontmatter**

Keep `AGENTS.md` below 120 lines. It must state stable rules and defer operational detail to the skill. The skill description must be:

```yaml
description: Use when the user wants to study, practice, review, or discuss a LeetCode, data structures, or algorithms problem in this repository. Also use for starting a scheduled learning session or importing a self-selected problem. Do not use for ordinary project coding unrelated to algorithm learning.
```

`SKILL.md` must route five intents: start/resume session, import problem, request hint, review code, and finish/review session. It must run `tools/check.ps1` before stateful work, prefer due review over new material, and require state validation plus visualization refresh before declaring a session complete.

- [ ] **Step 4: Write the four focused protocol references**

Repeat exact field names and commands rather than assuming model memory:

```text
pwsh -NoProfile -File tools/check.ps1
pwsh -NoProfile -File tools/new-problem.ps1 -ProblemId 1 -Slug two-sum -Title 'Two Sum' -Source leetcode -Difficulty easy -PrimaryTopicId hash-table -SecondaryTopicIds arrays-strings
pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath problems/1-two-sum
pwsh -NoProfile -File tools/update-state.ps1 -Kind state -CandidatePath learner/state.candidate.json
pwsh -NoProfile -File tools/update-visualization.ps1
```

The session protocol uses the approved 3–5 / 5–8 / 15–20 / 5–8 minute phases. The hint protocol exactly reproduces L1–L5 boundaries. The state model contains the 1/3/7/14/30-day scheduling rules. The code review protocol requires failure evidence first and forbids an unsolicited patch to learner code.

- [ ] **Step 5: Add six behavior evals with concrete expected behavior**

Each eval uses a realistic Chinese learner prompt. Required coverage:

```text
first-session: reads state, starts diagnosis, asks one question, gives no solution
hint-escalation: moves one level per explicit request and confirms before L5
failing-code-review: reports input/expected/actual/category before a coaching question
self-selected-problem: validates constraints, maps one primary and at most two secondary topics
session-resume: detects active session and offers continue or early review
review-scheduling: applies the exact mastery cap and interval for the recorded hint level
```

Every `Must not` section prohibits inventing a problem statement, claiming unrun tests passed, overwriting `attempt.cpp`, and creating `reference.cpp` below L5 where relevant.

- [ ] **Step 6: Validate skill structure and static contracts**

Run the skill-creator/writing-skills validation commands discovered in Step 1, then:

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile SkillContract.Tests.ps1
pwsh -NoProfile -File tests/harness/run-tests.ps1
pwsh -NoProfile -File tools/check.ps1
```

Expected: all commands pass. If Codex does not show the new skill immediately, restart the Codex task once; repository skills are discovered from `.agents/skills`.

- [ ] **Step 7: Manually replay two guardrail evals**

Start a fresh Codex task in this repository and replay `first-session.md` and `hint-escalation.md`. Record the observed response under an `## Observed` section in each file and mark each `Must`/`Must not` item with pass or fail. Fix instruction ambiguity and repeat until both scenarios pass.

- [ ] **Step 8: Commit the coaching harness**

```powershell
git add AGENTS.md .agents/skills/leetcode-coach evals tests/harness/SkillContract.Tests.ps1
git commit -m "feat: add the LeetCode coaching skill"
```

---

### Task 8: Learner Documentation and End-to-End Acceptance

**Files:**
- Create: `README.md`
- Create: `tests/harness/EndToEnd.Tests.ps1`
- Modify: `evals/README.md`
- Modify: `visualization/learning-path.html`

**Interfaces:**
- Consumes: The complete harness from Tasks 1–7.
- Produces: A learner-facing entry point, a repeatable acceptance test, and final verification evidence.

- [ ] **Step 1: Write the failing end-to-end test**

The test creates one isolated temporary repository fixture, copies the completed harness into it, and exercises this sequence:

```text
1. tools/check.ps1 returns CHECK PASS.
2. new-problem creates 1-two-sum mapped to hash-table + arrays-strings.
3. a valid active solve session at hint level 2 is saved.
4. a valid state update marks diagnosis introduced with a next-day review.
5. visualization is regenerated and reports fresh.
6. tools/check.ps1 returns CHECK PASS again.
7. test-cpp on the passing fixture returns PASS or SKIPPED, never FAIL.
8. attempt.cpp content remains byte-for-byte unchanged by every state and visualization command.
```

Before the README and any final command corrections, run the test and expect at least one documented command or output contract to fail.

- [ ] **Step 2: Write the learner-facing README**

README sections and exact user entry phrases:

```text
快速开始
  “开始今天的学习”
  “继续上次的学习”
  “学习 LeetCode 1”
  “给我下一级提示”
  “复盘这道题并安排复习”

仓库结构
一次学习如何进行
五级提示
常用 PowerShell 命令
安装 C++ 编译器后的验证
学习状态和可视化
数据恢复
当前限制
```

State that the current machine has no detected C++ compiler, so conceptual coaching works now while execution reports `SKIPPED`. Give examples for running `doctor.ps1`, `check.ps1`, `test-cpp.ps1`, and `update-visualization.ps1`. Do not recommend a single compiler vendor as mandatory.

- [ ] **Step 3: Run the end-to-end test and repair only contract mismatches**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1 -TestFile EndToEnd.Tests.ps1
```

Expected: exit 0. If it fails, change the narrowest module or documentation contract responsible; do not relax no-overwrite, validation, or hint rules.

- [ ] **Step 4: Run complete automated verification**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1
pwsh -NoProfile -File tools/check.ps1
pwsh -NoProfile -File tools/doctor.ps1
pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath tests/fixtures/cpp/pass
pwsh -NoProfile -File tools/update-visualization.ps1
git diff --check
git status --short
```

Expected on the current machine:

```text
All PowerShell test files report PASS.
check.ps1 ends with CHECK PASS.
doctor.ps1 ends with LIMITED.
test-cpp.ps1 begins with SKIPPED and exits 0.
update-visualization.ps1 reports UPDATED.
git diff --check prints no errors.
git status lists only intentional final documentation or generated-visualization changes.
```

- [ ] **Step 5: Visually inspect the generated learning path**

Open `visualization/learning-path.html` in Codex. At desktop width and approximately 360px width, verify no overlap or horizontal clipping, select at least `diagnosis`, `arrays-strings`, and `dynamic-programming`, and confirm the details match `roadmap.json` and `state.json`. Verify keyboard focus can reach and activate every node.

- [ ] **Step 6: Replay the remaining four behavior evals**

In fresh Codex tasks, replay `failing-code-review.md`, `self-selected-problem.md`, `session-resume.md`, and `review-scheduling.md`. Record `## Observed` evidence and require every `Must` and `Must not` item to pass. Instruction fixes require rerunning `SkillContract.Tests.ps1`, the affected eval, and `tools/check.ps1`.

- [ ] **Step 7: Commit documentation and acceptance evidence**

```powershell
git add README.md tests/harness/EndToEnd.Tests.ps1 evals visualization/learning-path.html
git commit -m "docs: add harness usage and acceptance evidence"
```

- [ ] **Step 8: Final clean verification**

```powershell
pwsh -NoProfile -File tests/harness/run-tests.ps1
pwsh -NoProfile -File tools/check.ps1
git status --short --branch
git log --oneline -10
```

Expected: all tests pass, consistency check passes, worktree is clean, and the task commits appear after design and plan commits.
