Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$SkillRoot = Join-Path $RepoRoot '.agents/skills/leetcode-coach'
$SkillPath = Join-Path $SkillRoot 'SKILL.md'
$ExpectedDescription = 'Use when the user wants to study, practice, review, or discuss a LeetCode, data structures, or algorithms problem in this repository. Also use for starting a scheduled learning session or importing a self-selected problem. Do not use for ordinary project coding unrelated to algorithm learning.'

function Get-RequiredFileText {
    param([string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required file missing [$RelativePath]."
    return Get-Content -Raw -LiteralPath $path
}

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    Assert-True ($Text -match $Pattern) $Message
}

function Get-MatchIndex {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    Assert-True $match.Success $Message
    return $match.Index
}

function Get-SkillFrontmatter {
    param([string]$Text)

    $match = [regex]::Match(
        $Text,
        '^---\r?\n(?<frontmatter>[\s\S]*?)\r?\n---\r?\n(?<body>[\s\S]+)$',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    Assert-True $match.Success 'SKILL.md must start with YAML frontmatter.'

    $frontmatter = [ordered]@{}
    foreach ($line in ($match.Groups['frontmatter'].Value -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $lineMatch = [regex]::Match($line, '^(?<key>[A-Za-z0-9_-]+):\s*(?<value>.+?)\s*$')
        Assert-True $lineMatch.Success "Invalid frontmatter line [$line]."
        $frontmatter[$lineMatch.Groups['key'].Value] = $lineMatch.Groups['value'].Value
    }

    return [pscustomobject]@{
        Frontmatter = $frontmatter
        Body = $match.Groups['body'].Value
    }
}

$agentsText = Get-RequiredFileText 'AGENTS.md'
Assert-Match $agentsText 'leetcode-coach' 'AGENTS.md must route learners to leetcode-coach.'
Assert-Match $agentsText '(?i)study|practice|review' 'AGENTS.md must mention study, practice, or review requests.'
Assert-Match $agentsText '(?i)algorithm|LeetCode|data structure' 'AGENTS.md must mention algorithm-learning requests.'

$skillText = Get-RequiredFileText '.agents/skills/leetcode-coach/SKILL.md'
$skillDocument = Get-SkillFrontmatter $skillText
$frontmatterKeys = @($skillDocument.Frontmatter.Keys)
Assert-Equal 2 $frontmatterKeys.Count 'SKILL.md frontmatter key count mismatch.'
Assert-Equal 'name' $frontmatterKeys[0] 'SKILL.md first frontmatter key mismatch.'
Assert-Equal 'description' $frontmatterKeys[1] 'SKILL.md second frontmatter key mismatch.'
Assert-Equal 'leetcode-coach' $skillDocument.Frontmatter['name'] 'SKILL.md skill name mismatch.'
Assert-Equal $ExpectedDescription $skillDocument.Frontmatter['description'] 'SKILL.md description mismatch.'

foreach ($referencePath in @(
    'references/session-protocol.md',
    'references/hint-policy.md',
    'references/state-model.md',
    'references/code-review.md'
)) {
    Assert-Match $skillDocument.Body ([regex]::Escape($referencePath)) "SKILL.md must link [$referencePath]."
    $absoluteReferencePath = Join-Path $SkillRoot $referencePath
    Assert-True (Test-Path -LiteralPath $absoluteReferencePath -PathType Leaf) "Referenced skill file missing [$referencePath]."
}

foreach ($routeKeyword in @(
    'start',
    'resume',
    'import',
    'hint',
    'review',
    'finish'
)) {
    Assert-Match $skillDocument.Body ("(?i)\b{0}\b" -f [regex]::Escape($routeKeyword)) "SKILL.md must route [$routeKeyword] intent."
}

Assert-Match $skillDocument.Body 'tools/check\.ps1' 'SKILL.md must run tools/check.ps1 before stateful work.'
Assert-Match $skillDocument.Body '(?i)due review' 'SKILL.md must prefer due review over new material.'
Assert-Match $skillDocument.Body 'tools/update-state\.ps1' 'SKILL.md must reference state updates.'
Assert-Match $skillDocument.Body 'tools/update-visualization\.ps1' 'SKILL.md must refresh the visualization before completion.'

$sessionProtocolText = Get-RequiredFileText '.agents/skills/leetcode-coach/references/session-protocol.md'
foreach ($sessionToken in @('start', 'recall', 'concept', 'solve', 'review', 'schedule')) {
    Assert-Match $sessionProtocolText ("(?i)\b{0}\b" -f [regex]::Escape($sessionToken)) "Session protocol missing [$sessionToken] transition."
}
Assert-Match $sessionProtocolText '3.?5' 'Session protocol must contain the 3-5 minute startup phase.'
Assert-Match $sessionProtocolText '5.?8' 'Session protocol must contain the 5-8 minute concept or review phase.'
Assert-Match $sessionProtocolText '15.?20' 'Session protocol must contain the 15-20 minute solve phase.'

$hintPolicyText = Get-RequiredFileText '.agents/skills/leetcode-coach/references/hint-policy.md'
foreach ($hintLevel in @('L1', 'L2', 'L3', 'L4', 'L5')) {
    Assert-Match $hintPolicyText $hintLevel "Hint policy missing [$hintLevel]."
}
Assert-Match $hintPolicyText '(?i)L5[\s\S]{0,240}(explicit|confirm)' 'Hint policy must include an explicit L5 confirmation gate.'
Assert-Match $hintPolicyText '(?i)attempt\.cpp[\s\S]{0,120}(cannot|must not|do not)[\s\S]{0,80}(overwrite|replace)' 'Hint policy must say attempt.cpp cannot be overwritten.'

$stateModelText = Get-RequiredFileText '.agents/skills/leetcode-coach/references/state-model.md'
foreach ($stateField in @(
    'schema_version',
    'current_topic_id',
    'updated_at',
    'topics',
    'mastery',
    'status',
    'last_studied_at',
    'next_review_at',
    'sessions_completed',
    'best_independent_result',
    'highest_hint_level_used',
    'error_tags'
)) {
    Assert-Match $stateModelText ([regex]::Escape($stateField)) "State model missing field [$stateField]."
}
foreach ($reviewInterval in @('1', '3', '7', '14', '30')) {
    Assert-Match $stateModelText ("(?<!\d){0}(?!\d)" -f $reviewInterval) "State model missing review interval [$reviewInterval]."
}

$codeReviewText = Get-RequiredFileText '.agents/skills/leetcode-coach/references/code-review.md'
$constraintsIndex = Get-MatchIndex -Text $codeReviewText -Pattern '(?i)constraint' -Message 'Code review reference must start from constraints or correctness.'
$invariantIndex = Get-MatchIndex -Text $codeReviewText -Pattern '(?i)invariant' -Message 'Code review reference must mention invariants.'
$styleIndex = Get-MatchIndex -Text $codeReviewText -Pattern '(?i)style|naming|expression' -Message 'Code review reference must mention style.'
Assert-True ($constraintsIndex -lt $invariantIndex) 'Code review reference must order correctness or constraints before invariants.'
Assert-True ($invariantIndex -lt $styleIndex) 'Code review reference must order invariants before style.'
Assert-Match $codeReviewText '(?i)input' 'Code review reference must ask for concrete failing input evidence first.'
Assert-Match $codeReviewText '(?i)expected' 'Code review reference must ask for expected behavior.'
Assert-Match $codeReviewText '(?i)actual' 'Code review reference must ask for actual behavior.'
Assert-Match $codeReviewText '(?i)must not|do not|forbid' 'Code review reference must forbid unsolicited learner-code patches.'

$evalScenarios = @(
    @{
        Path = 'evals/README.md'
        Patterns = @('(?i)first-session', '(?i)hint-escalation', '(?i)failing-code-review', '(?i)self-selected-problem', '(?i)session-resume', '(?i)review-scheduling')
    },
    @{
        Path = 'evals/first-session.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)diagnosis', '(?i)one question', '(?i)no solution')
    },
    @{
        Path = 'evals/hint-escalation.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)L1', '(?i)L5', '(?i)confirm')
    },
    @{
        Path = 'evals/failing-code-review.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)input', '(?i)expected', '(?i)actual', '(?i)category')
    },
    @{
        Path = 'evals/self-selected-problem.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)primary', '(?i)secondary', '(?i)constraint')
    },
    @{
        Path = 'evals/session-resume.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)continue', '(?i)early review')
    },
    @{
        Path = 'evals/review-scheduling.md'
        Patterns = @('[\u4e00-\u9fff]', '(?i)mastery', '(?i)interval', '(?i)hint level')
    }
)

foreach ($scenario in $evalScenarios) {
    $scenarioText = Get-RequiredFileText $scenario.Path
    if ($scenario.Path -ne 'evals/README.md') {
        foreach ($section in @('## Prompt', '## Must', '## Must not')) {
            Assert-Match $scenarioText ([regex]::Escape($section)) "$($scenario.Path) must contain [$section]."
        }
        Assert-Match $scenarioText '(?i)inventing a problem statement' "$($scenario.Path) must forbid inventing a problem statement."
        Assert-Match $scenarioText '(?i)claiming unrun tests passed|claim tests passed without running' "$($scenario.Path) must forbid claiming unrun tests passed."
        Assert-Match $scenarioText '(?i)overwriting `?attempt\.cpp`?' "$($scenario.Path) must forbid overwriting attempt.cpp."
    }

    foreach ($pattern in $scenario.Patterns) {
        Assert-Match $scenarioText $pattern "$($scenario.Path) is missing required content [$pattern]."
    }
}

$hintEvalText = Get-RequiredFileText 'evals/hint-escalation.md'
Assert-Match $hintEvalText '(?i)reference\.cpp' 'hint-escalation eval must mention the reference.cpp guardrail.'

$reviewSchedulingEvalText = Get-RequiredFileText 'evals/review-scheduling.md'
Assert-Match $reviewSchedulingEvalText '(?i)reference\.cpp' 'review-scheduling eval must mention the reference.cpp guardrail where relevant.'
