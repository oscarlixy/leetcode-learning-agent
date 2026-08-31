Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/ProblemWorkspace.psm1" -Force
Import-Module "$RepoRoot/tools/lib/Visualization.psm1" -Force
$validationModule = Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force -PassThru
$ReadJsonDocument = $validationModule.ExportedFunctions['Read-JsonDocument']

function New-TestRepositoryFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-check-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    foreach ($directory in @('curriculum', 'learner', 'problems', 'problems/_template', 'visualization')) {
        New-Item -ItemType Directory -Path (Join-Path $resolvedFixtureRoot $directory) -Force | Out-Null
    }

    foreach ($file in @(
        'curriculum/roadmap.json',
        'learner/profile.json',
        'learner/state.json',
        'learner/state.backup.json',
        'learner/active-session.json',
        'visualization/learning-path.template.html'
    )) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination (Join-Path $resolvedFixtureRoot $file) -Force
    }

    foreach ($templateChild in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'problems/_template') -Force) {
        Copy-Item -LiteralPath $templateChild.FullName -Destination (Join-Path $resolvedFixtureRoot 'problems/_template') -Recurse -Force
    }

    New-ProblemWorkspace `
        -RepoRoot $resolvedFixtureRoot `
        -ProblemId 1 `
        -Slug 'two-sum' `
        -Title 'Two Sum' `
        -Source 'leetcode' `
        -Url 'https://leetcode.com/problems/two-sum/' `
        -Difficulty 'easy' `
        -PrimaryTopicId 'hash-table' `
        -SecondaryTopicIds @('arrays-strings') | Out-Null

    Update-LearningPathVisualization -RepoRoot $resolvedFixtureRoot | Out-Null
    return $resolvedFixtureRoot
}

function Write-TestJsonDocument {
    param(
        [string]$Path,
        $Document
    )

    $Document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-CheckScript {
    param([string]$TargetRepoRoot)

    $output = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/check.ps1') -RepoRoot $TargetRepoRoot 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

function Invoke-CheckScenario {
    param(
        [scriptblock]$Mutate,
        [int]$ExpectedExitCode,
        [string]$ExpectedPattern,
        [string]$Message
    )

    $fixtureRoot = New-TestRepositoryFixture
    try {
        if ($null -ne $Mutate) {
            & $Mutate $fixtureRoot
        }

        $result = Invoke-CheckScript -TargetRepoRoot $fixtureRoot
        Assert-Equal $ExpectedExitCode $result.ExitCode $Message
        Assert-True ($result.Output -match $ExpectedPattern) "$Message Output=[$($result.Output)]"
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}

Invoke-CheckScenario -Mutate $null -ExpectedExitCode 0 -ExpectedPattern 'CHECK PASS' -Message 'Valid repository should pass the consistency check.'

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'mastery' -Message 'Out-of-range mastery should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $statePath = Join-Path $FixtureRoot 'learner/state.json'
    $state = & $ReadJsonDocument $statePath
    $state.topics.diagnosis.mastery = 8
    Write-TestJsonDocument -Path $statePath -Document $state
}

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'prerequisite' -Message 'Missing roadmap prerequisites should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $roadmapPath = Join-Path $FixtureRoot 'curriculum/roadmap.json'
    $roadmap = & $ReadJsonDocument $roadmapPath
    $roadmap.nodes[1].prerequisites = @('missing-topic')
    Write-TestJsonDocument -Path $roadmapPath -Document $roadmap
}

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'primary_topic_id' -Message 'Unknown problem topics should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $metaPath = Join-Path $FixtureRoot 'problems/1-two-sum/meta.json'
    $meta = & $ReadJsonDocument $metaPath
    $meta.primary_topic_id = 'missing-topic'
    Write-TestJsonDocument -Path $metaPath -Document $meta
}

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'topic_id' -Message 'Unknown active-session topics should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $activeSessionPath = Join-Path $FixtureRoot 'learner/active-session.json'
    $activeSession = & $ReadJsonDocument $activeSessionPath
    $activeSession.active = $true
    $activeSession.session_id = 'session-1'
    $activeSession.started_at = '2026-08-31T00:00:00+08:00'
    $activeSession.topic_id = 'missing-topic'
    $activeSession.problem_slug = 'two-sum'
    $activeSession.phase = 'solve'
    $activeSession.hint_level = 0
    $activeSession.last_updated_at = '2026-08-31T00:10:00+08:00'
    Write-TestJsonDocument -Path $activeSessionPath -Document $activeSession
}

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'reference\.cpp' -Message 'Reference solutions below hint level five should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $metaPath = Join-Path $FixtureRoot 'problems/1-two-sum/meta.json'
    $meta = & $ReadJsonDocument $metaPath
    $meta.highest_hint_level_used = 4
    Write-TestJsonDocument -Path $metaPath -Document $meta
    Set-Content -LiteralPath (Join-Path $FixtureRoot 'problems/1-two-sum/reference.cpp') -Value '// unlocked too early' -Encoding utf8
}

Invoke-CheckScenario -ExpectedExitCode 1 -ExpectedPattern 'visualization' -Message 'Stale visualization output should fail the consistency check.' -Mutate {
    param($FixtureRoot)

    $statePath = Join-Path $FixtureRoot 'learner/state.json'
    $state = & $ReadJsonDocument $statePath
    $state.topics.diagnosis.mastery = 1
    Write-TestJsonDocument -Path $statePath -Document $state
}
