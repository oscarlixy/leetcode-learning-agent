Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$updateProblemScript = Join-Path $RepoRoot 'tools/update-problem.ps1'

# Break caught: there was no validated atomic command for problem metadata updates.
Assert-True (Test-Path -LiteralPath $updateProblemScript -PathType Leaf) 'tools/update-problem.ps1 is required for atomic problem metadata updates.'

Import-Module (Join-Path $RepoRoot 'tools/lib/ProblemWorkspace.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Visualization.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Validation.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/JsonStore.psm1') -Force
Assert-True ($null -ne (Get-Command Save-ProblemMetadata -ErrorAction SilentlyContinue)) 'Save-ProblemMetadata must be exported by JsonStore.psm1.'

function New-ProblemMetadataFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-problem-metadata-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    foreach ($directory in @('curriculum', 'learner', 'problems', 'problems/_template', 'visualization')) {
        New-Item -ItemType Directory -Path (Join-Path $resolvedFixtureRoot $directory) -Force | Out-Null
    }

    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $resolvedFixtureRoot 'curriculum/roadmap.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/profile.json') -Destination (Join-Path $resolvedFixtureRoot 'learner/profile.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/state.json') -Destination (Join-Path $resolvedFixtureRoot 'learner/state.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/state.backup.json') -Destination (Join-Path $resolvedFixtureRoot 'learner/state.backup.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/active-session.json') -Destination (Join-Path $resolvedFixtureRoot 'learner/active-session.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'visualization/learning-path.template.html') -Destination (Join-Path $resolvedFixtureRoot 'visualization/learning-path.template.html') -Force
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

function Write-TestJson {
    param(
        [string]$Path,
        $Document
    )

    $Document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-Check {
    param([string]$TargetRepoRoot)

    $output = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/check.ps1') -RepoRoot $TargetRepoRoot 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

$l5Root = New-ProblemMetadataFixture
try {
    $problemRoot = Join-Path $l5Root 'problems/1-two-sum'
    $attemptPath = Join-Path $problemRoot 'attempt.cpp'
    Set-Content -LiteralPath $attemptPath -Value '// learner-owned bytes' -Encoding utf8
    $attemptBytes = [System.IO.File]::ReadAllBytes($attemptPath)

    $activeCandidatePath = Join-Path $l5Root 'learner/active-session.candidate.json'
    $activeCandidate = Read-JsonDocument (Join-Path $l5Root 'learner/active-session.json')
    $activeCandidate.active = $true
    $activeCandidate.session_id = 'l5-transaction'
    $activeCandidate.started_at = '2026-09-02T09:00:00+08:00'
    $activeCandidate.topic_id = 'hash-table'
    $activeCandidate.problem_slug = 'two-sum'
    $activeCandidate.phase = 'solve'
    $activeCandidate.hint_level = 5
    $activeCandidate.last_updated_at = '2026-09-02T09:15:00+08:00'
    Write-TestJson -Path $activeCandidatePath -Document $activeCandidate
    Save-LearnerDocument -Kind active-session -CandidatePath $activeCandidatePath -RepoRoot $l5Root

    $metaPath = Join-Path $problemRoot 'meta.json'
    $metaCandidatePath = Join-Path $problemRoot 'meta.candidate.json'
    $metaCandidate = Read-JsonDocument $metaPath
    $metaCandidate.status = 'attempting'
    $metaCandidate.attempt_count = 1
    $metaCandidate.highest_hint_level_used = 5
    $metaCandidate.last_attempted_at = '2026-09-02T09:15:00+08:00'
    Write-TestJson -Path $metaCandidatePath -Document $metaCandidate

    $updateOutput = & pwsh -NoProfile -File $updateProblemScript `
        -RepoRoot $l5Root `
        -ProblemPath 'problems/1-two-sum' `
        -CandidatePath 'problems/1-two-sum/meta.candidate.json' 2>&1
    $updateExitCode = $LASTEXITCODE
    Assert-Equal 0 $updateExitCode 'Valid problem metadata update should succeed.'
    Assert-True (($updateOutput -join [Environment]::NewLine) -match '^UPDATED problem metadata problems/1-two-sum$') 'Problem metadata CLI success output mismatch.'

    $savedMeta = Read-JsonDocument $metaPath
    Assert-Equal 'attempting' $savedMeta.status 'Problem status was not persisted.'
    Assert-Equal 1 $savedMeta.attempt_count 'Problem attempt_count was not persisted.'
    Assert-Equal 5 $savedMeta.highest_hint_level_used 'Problem hint level was not synchronized to L5.'
    Assert-Equal '2026-09-02T09:15:00+08:00' $savedMeta.last_attempted_at 'Problem last_attempted_at was not persisted.'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual($attemptBytes, [System.IO.File]::ReadAllBytes($attemptPath))) 'Problem metadata update modified learner-owned attempt.cpp.'

    Set-Content -LiteralPath (Join-Path $problemRoot 'reference.cpp') -Value '// reference unlocked after persisted L5 metadata' -Encoding utf8
    $check = Invoke-Check -TargetRepoRoot $l5Root
    Assert-Equal 0 $check.ExitCode 'The completed L5 metadata transaction should keep check.ps1 valid.'
    Assert-True ($check.Output -match 'CHECK PASS') "L5 consistency output mismatch. Output=[$($check.Output)]"

    $invalidCandidatePath = Join-Path $problemRoot 'meta.invalid.candidate.json'
    $invalidCandidate = Read-JsonDocument $metaPath
    $invalidCandidate.highest_hint_level_used = 6
    Write-TestJson -Path $invalidCandidatePath -Document $invalidCandidate
    $stableMeta = [System.IO.File]::ReadAllBytes($metaPath)
    Assert-Throws {
        Save-ProblemMetadata -ProblemPath 'problems/1-two-sum' -CandidatePath 'problems/1-two-sum/meta.invalid.candidate.json' -RepoRoot $l5Root
    } 'highest_hint_level_used'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual($stableMeta, [System.IO.File]::ReadAllBytes($metaPath))) 'Invalid metadata candidate changed meta.json.'
}
finally {
    if (Test-Path -LiteralPath $l5Root) {
        Remove-Item -LiteralPath $l5Root -Recurse -Force
    }
}

$belowL5Root = New-ProblemMetadataFixture
try {
    $problemRoot = Join-Path $belowL5Root 'problems/1-two-sum'
    $metaPath = Join-Path $problemRoot 'meta.json'
    $metaCandidatePath = Join-Path $problemRoot 'meta.candidate.json'
    $metaCandidate = Read-JsonDocument $metaPath
    $metaCandidate.status = 'attempting'
    $metaCandidate.attempt_count = 1
    $metaCandidate.highest_hint_level_used = 4
    $metaCandidate.last_attempted_at = '2026-09-02T09:15:00+08:00'
    Write-TestJson -Path $metaCandidatePath -Document $metaCandidate
    [void](Save-ProblemMetadata -ProblemPath 'problems/1-two-sum' -CandidatePath 'problems/1-two-sum/meta.candidate.json' -RepoRoot $belowL5Root)

    Set-Content -LiteralPath (Join-Path $problemRoot 'reference.cpp') -Value '// forbidden below L5' -Encoding utf8
    $check = Invoke-Check -TargetRepoRoot $belowL5Root
    Assert-Equal 1 $check.ExitCode 'reference.cpp below L5 must fail check.ps1.'
    Assert-True ($check.Output -match 'reference\.cpp') 'Below-L5 failure must name reference.cpp.'
}
finally {
    if (Test-Path -LiteralPath $belowL5Root) {
        Remove-Item -LiteralPath $belowL5Root -Recurse -Force
    }
}

$desynchronizedRoot = New-ProblemMetadataFixture
try {
    $activeSessionPath = Join-Path $desynchronizedRoot 'learner/active-session.json'
    $activeSession = Read-JsonDocument $activeSessionPath
    $activeSession.active = $true
    $activeSession.session_id = 'desynchronized-hints'
    $activeSession.started_at = '2026-09-02T09:00:00+08:00'
    $activeSession.topic_id = 'hash-table'
    $activeSession.problem_slug = 'two-sum'
    $activeSession.phase = 'solve'
    $activeSession.hint_level = 5
    $activeSession.last_updated_at = '2026-09-02T09:15:00+08:00'
    Write-TestJson -Path $activeSessionPath -Document $activeSession

    $check = Invoke-Check -TargetRepoRoot $desynchronizedRoot
    Assert-Equal 1 $check.ExitCode 'check.ps1 must reject an active hint level above problem metadata.'
    Assert-True ($check.Output -match '(?i)highest_hint_level_used|hint_level') 'Desynchronized hint failure must name the mismatched fields.'
}
finally {
    if (Test-Path -LiteralPath $desynchronizedRoot) {
        Remove-Item -LiteralPath $desynchronizedRoot -Recurse -Force
    }
}

$equivalentCreatedAtRoot = New-ProblemMetadataFixture
try {
    $problemRoot = Join-Path $equivalentCreatedAtRoot 'problems/1-two-sum'
    $metaPath = Join-Path $problemRoot 'meta.json'
    $metaCandidatePath = Join-Path $problemRoot 'meta.candidate.json'

    $currentMeta = Read-JsonDocument $metaPath
    $currentMeta.created_at = '2026-09-02T09:00:00.6000000+08:00'
    Write-TestJson -Path $metaPath -Document $currentMeta

    $equivalentCandidate = Read-JsonDocument $metaPath
    $equivalentCandidate.created_at = '2026-09-02T09:00:00.6+08:00'
    Write-TestJson -Path $metaCandidatePath -Document $equivalentCandidate

    [void](Save-ProblemMetadata `
        -ProblemPath 'problems/1-two-sum' `
        -CandidatePath 'problems/1-two-sum/meta.candidate.json' `
        -RepoRoot $equivalentCreatedAtRoot)

    $savedMeta = Read-JsonDocument $metaPath
    Assert-Equal '2026-09-02T09:00:00.6+08:00' $savedMeta.created_at 'Equivalent ISO 8601 created_at representations should not count as an identity change.'
}
finally {
    if (Test-Path -LiteralPath $equivalentCreatedAtRoot) {
        Remove-Item -LiteralPath $equivalentCreatedAtRoot -Recurse -Force
    }
}

$hintPolicy = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/hint-policy.md') -Raw -Encoding utf8
Assert-True ($hintPolicy -match '(?i)explicit learner confirmation') 'The explicit learner-confirmation gate must remain in the L5 policy.'
Assert-True ($hintPolicy -match '(?is)hint_level.{0,100}5.{0,300}update-state\.ps1.{0,500}update-problem\.ps1.{0,500}(only then|after).{0,120}reference\.cpp') 'L5 policy must order active-session save, metadata save, then reference.cpp creation.'
