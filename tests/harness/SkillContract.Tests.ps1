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

function Assert-NotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    Assert-True (-not ($Text -match $Pattern)) $Message
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
Assert-Match $sessionProtocolText ([regex]::Escape('pwsh -NoProfile -File tools/new-problem.ps1 -RepoRoot (Resolve-Path ''.'') -ProblemId $ProblemId -Slug $Slug -Title $Title -Source $Source -Url $Url -Difficulty $Difficulty -PrimaryTopicId $PrimaryTopicId -SecondaryTopicIds $SecondaryTopicIds')) 'Session protocol must document the executable PowerShell new-problem command shape with (Resolve-Path ''.'') and validated metadata variables.'
Assert-Match $sessionProtocolText '(?i)validated learner-provided metadata' 'Session protocol must say the self-selected import variables come from validated learner-provided metadata.'
Assert-NotMatch $sessionProtocolText '(?i)-ProblemId\s+1|-Slug\s+two-sum|-Title\s+''Two Sum''|-PrimaryTopicId\s+hash-table' 'Session protocol must not hardcode a specific self-selected problem import command.'
Assert-Match $sessionProtocolText '(?i)after every phase transition[\s\S]{0,220}pwsh -NoProfile -File tools/update-state\.ps1 -Kind active-session -CandidatePath learner/active-session\.candidate\.json' 'Session protocol must persist active-session after every phase transition with the exact command.'

$hintPolicyText = Get-RequiredFileText '.agents/skills/leetcode-coach/references/hint-policy.md'
foreach ($hintLevel in @('L1', 'L2', 'L3', 'L4', 'L5')) {
    Assert-Match $hintPolicyText $hintLevel "Hint policy missing [$hintLevel]."
}
Assert-Match $hintPolicyText '(?i)L5[\s\S]{0,240}(explicit|confirm)' 'Hint policy must include an explicit L5 confirmation gate.'
Assert-Match $hintPolicyText '(?i)attempt\.cpp[\s\S]{0,120}(cannot|must not|do not)[\s\S]{0,80}(overwrite|replace)' 'Hint policy must say attempt.cpp cannot be overwritten.'
Assert-Match $hintPolicyText '(?i)after every hint(?:_level)? increase[\s\S]{0,220}pwsh -NoProfile -File tools/update-state\.ps1 -Kind active-session -CandidatePath learner/active-session\.candidate\.json' 'Hint policy must persist active-session after every hint_level increase with the exact command.'

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
Assert-Match $stateModelText ([regex]::Escape('- Fields: `schema_version`, `active`, `session_id`, `started_at`, `topic_id`, `problem_slug`, `phase`, `hint_level`, `last_updated_at`')) 'State model must pin the exact active-session field set.'
Assert-Match $stateModelText ([regex]::Escape('- `phase` uses `recall`, `concept`, `solve`, `review`, `complete`.')) 'State model must pin the exact active-session phase enum.'
Assert-Match $stateModelText '(?i)Needed L4 or L5 to finish:[\s\S]{0,120}mastery[\s\S]{0,40}2[\s\S]{0,80}1 day' 'State model must pin the L4/L5 mastery cap and 1-day review rule.'
Assert-Match $stateModelText '(?i)Finished under L1-L3 and can explain correctness:[\s\S]{0,120}mastery[\s\S]{0,40}2[\s\S]{0,80}3 days' 'State model must pin the L1-L3 mastery cap and 3-day review rule.'
Assert-Match $stateModelText '(?i)Solved a standard problem independently:[\s\S]{0,120}mastery[\s\S]{0,40}3[\s\S]{0,80}7 or 14 days' 'State model must pin the independent standard-problem mastery and 7/14-day rule.'
Assert-Match $stateModelText '(?i)Solved a variant independently[\s\S]{0,120}mastery[\s\S]{0,40}4[\s\S]{0,80}30 days' 'State model must pin the variant-transfer mastery and 30-day rule.'
Assert-Match $stateModelText '(?i)Failed a due review:[\s\S]{0,120}status[\s\S]{0,40}`review`[\s\S]{0,80}1 day[\s\S]{0,120}at most one level' 'State model must pin the failed-review downgrade rule.'

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

$firstSessionEvalText = Get-RequiredFileText 'evals/first-session.md'
Assert-Match $firstSessionEvalText ([regex]::Escape('- Read learner state before choosing the session path.')) 'first-session eval must require reading learner state.'
Assert-Match $firstSessionEvalText ([regex]::Escape('- Start from `diagnosis` for a first session.')) 'first-session eval must require diagnosis.'
Assert-Match $firstSessionEvalText ([regex]::Escape('- Ask exactly one question before assigning the next step.')) 'first-session eval must require exactly one opening question.'
Assert-Match $firstSessionEvalText '(?i)- Mention how the session will be saved in repository state and reviewed later\.' 'first-session eval must require the save/review explanation.'
Assert-Match $firstSessionEvalText ([regex]::Escape('- jumping straight to a full LeetCode solution')) 'first-session eval must forbid a full solution opening.'

$hintEvalText = Get-RequiredFileText 'evals/hint-escalation.md'
Assert-Match $hintEvalText ([regex]::Escape('- Start at `L1` and move one level per explicit request.')) 'hint-escalation eval must require one-level escalation.'
Assert-Match $hintEvalText '(?i)bare `?继续`?.{0,80}not unlock `?L5`?' 'hint-escalation eval must pin that a bare continue request is not enough for L5.'
Assert-Match $hintEvalText '(?i)request unlocked\s+`?L5`?' 'hint-escalation eval must pin the explicit L5 confirmation phrase.'

$codeReviewEvalText = Get-RequiredFileText 'evals/failing-code-review.md'
Assert-Match $codeReviewEvalText ([regex]::Escape('- Lead with `input`, `expected`, `actual`, and `category`.')) 'failing-code-review eval must require the failure-first structure.'
Assert-Match $codeReviewEvalText ([regex]::Escape('- Ask one coaching question after the failure summary.')) 'failing-code-review eval must require a coaching question after the summary.'
Assert-Match $codeReviewEvalText '(?i)- applying an unsolicited patch to learner code' 'failing-code-review eval must forbid unsolicited patches.'

$selfSelectedEvalText = Get-RequiredFileText 'evals/self-selected-problem.md'
Assert-Match $selfSelectedEvalText ([regex]::Escape('- Validate missing `constraint` details instead of inventing them.')) 'self-selected-problem eval must require constraint validation.'
Assert-Match $selfSelectedEvalText '(?i)- Map the problem to one `primary` topic and at most two `secondary` topics\.' 'self-selected-problem eval must require one primary and at most two secondary topics.'
Assert-Match $selfSelectedEvalText ([regex]::Escape('- assigning more than two `secondary` topics')) 'self-selected-problem eval must forbid too many secondary topics.'

$sessionResumeEvalText = Get-RequiredFileText 'evals/session-resume.md'
Assert-Match $sessionResumeEvalText ([regex]::Escape('- Offer exactly two choices: `continue` or `early review`.')) 'session-resume eval must require exactly two choices.'
Assert-Match $sessionResumeEvalText '(?i)- Resume from the stored phase and hint level if the learner chooses continue\.' 'session-resume eval must require resuming the stored phase and hint level.'
Assert-Match $sessionResumeEvalText '(?i)persisted|saved current phase and hint level|current saved state' 'session-resume eval must reflect that the current saved state is used.'

$reviewSchedulingEvalText = Get-RequiredFileText 'evals/review-scheduling.md'
Assert-Match $reviewSchedulingEvalText '(?i)L4|L5|L1-L3' 'review-scheduling eval must mention the exact hint-band scheduling rules.'
Assert-Match $reviewSchedulingEvalText '(?i)mastery.{0,80}2.{0,80}1 day' 'review-scheduling eval must pin the L4/L5 mastery cap and 1-day interval.'
Assert-Match $reviewSchedulingEvalText '(?i)mastery.{0,80}2.{0,80}3 days' 'review-scheduling eval must pin the L1-L3 mastery cap and 3-day interval.'
Assert-Match $reviewSchedulingEvalText '(?i)next review date|saved schedule' 'review-scheduling eval must require the exact next-review explanation from saved state.'

Assert-Match $hintEvalText '(?i)reference\.cpp' 'hint-escalation eval must mention the reference.cpp guardrail.'

Assert-Match $reviewSchedulingEvalText '(?i)reference\.cpp' 'review-scheduling eval must mention the reference.cpp guardrail where relevant.'
