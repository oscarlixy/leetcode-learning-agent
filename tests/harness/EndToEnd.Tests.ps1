Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function New-EndToEndRepositoryFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-end-to-end-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    foreach ($directory in @('curriculum', 'learner', 'problems', 'schemas', 'tests', 'tools', 'visualization')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $directory) -Destination $resolvedFixtureRoot -Recurse -Force
    }

    foreach ($file in @('.gitignore', 'AGENTS.md', 'README.md')) {
        $sourcePath = Join-Path $RepoRoot $file
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            Copy-Item -LiteralPath $sourcePath -Destination $resolvedFixtureRoot -Force
        }
    }

    return $resolvedFixtureRoot
}

function Invoke-RepoScript {
    param(
        [string]$TargetRepoRoot,
        [string]$ScriptRelativePath,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $TargetRepoRoot $ScriptRelativePath
    $output = & pwsh -NoProfile -File $scriptPath @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

function Write-TestJsonDocument {
    param(
        [string]$Path,
        $Document
    )

    $Document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Assert-FileBytesEqual {
    param(
        [byte[]]$Expected,
        [string]$Path,
        [string]$Message
    )

    $actual = [System.IO.File]::ReadAllBytes($Path)
    Assert-True ([System.Linq.Enumerable]::SequenceEqual($Expected, $actual)) $Message
}

function Assert-FileAbsent {
    param(
        [string]$Path,
        [string]$Message
    )

    Assert-True (-not (Test-Path -LiteralPath $Path -PathType Leaf)) $Message
}

$fixtureRoot = New-EndToEndRepositoryFixture
try {
    $initialCheck = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/check.ps1'
    Assert-Equal 0 $initialCheck.ExitCode 'Initial check should pass for the copied fixture.'
    Assert-True ($initialCheck.Output -match 'CHECK PASS') "Initial check output mismatch. Output=[$($initialCheck.Output)]"

    $created = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/new-problem.ps1' -Arguments @(
        '-RepoRoot', $fixtureRoot,
        '-ProblemId', '1',
        '-Slug', 'two-sum',
        '-Title', 'Two Sum',
        '-Source', 'leetcode',
        '-Url', 'https://leetcode.com/problems/two-sum/',
        '-Difficulty', 'easy',
        '-PrimaryTopicId', 'hash-table',
        '-SecondaryTopicIds', 'arrays-strings'
    )
    Assert-Equal 0 $created.ExitCode 'new-problem should succeed for the fixture workspace.'
    Assert-True ($created.Output -match '^CREATED .+1-two-sum') "new-problem output mismatch. Output=[$($created.Output)]"

    $problemRoot = Join-Path $fixtureRoot 'problems/1-two-sum'
    $attemptPath = Join-Path $problemRoot 'attempt.cpp'
    $referencePath = Join-Path $problemRoot 'reference.cpp'
    $attemptBytes = [System.IO.File]::ReadAllBytes($attemptPath)
    Assert-FileAbsent -Path $referencePath -Message 'reference.cpp should remain absent immediately after workspace creation for a non-L5 flow.'

    $meta = Get-Content -LiteralPath (Join-Path $problemRoot 'meta.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    Assert-Equal 'hash-table' $meta.primary_topic_id 'new-problem should persist the primary topic.'
    Assert-Equal 1 $meta.secondary_topic_ids.Count 'new-problem should persist one secondary topic.'
    Assert-Equal 'arrays-strings' $meta.secondary_topic_ids[0] 'new-problem should persist arrays-strings as the secondary topic.'

    $activeSessionCandidatePath = Join-Path $fixtureRoot 'learner/active-session.candidate.json'
    $activeSessionCandidate = Get-Content -LiteralPath (Join-Path $fixtureRoot 'learner/active-session.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    $activeSessionCandidate.active = $true
    $activeSessionCandidate.session_id = 'session-two-sum'
    $activeSessionCandidate.started_at = '2026-09-02T09:00:00+08:00'
    $activeSessionCandidate.topic_id = 'hash-table'
    $activeSessionCandidate.problem_slug = 'two-sum'
    $activeSessionCandidate.phase = 'solve'
    $activeSessionCandidate.hint_level = 2
    $activeSessionCandidate.last_updated_at = '2026-09-02T09:15:00+08:00'
    Write-TestJsonDocument -Path $activeSessionCandidatePath -Document $activeSessionCandidate

    $activeSessionUpdate = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/update-state.ps1' -Arguments @(
        '-Kind', 'active-session',
        '-CandidatePath', 'learner/active-session.candidate.json'
    )
    Assert-Equal 0 $activeSessionUpdate.ExitCode 'Saving a valid active solve session should succeed.'
    Assert-True ($activeSessionUpdate.Output -match '^UPDATED active-session$') "active-session update output mismatch. Output=[$($activeSessionUpdate.Output)]"
    Assert-FileBytesEqual -Expected $attemptBytes -Path $attemptPath -Message 'active-session update should not modify attempt.cpp.'
    Assert-FileAbsent -Path $referencePath -Message 'reference.cpp should remain absent after active-session updates below L5.'

    $savedActiveSession = Get-Content -LiteralPath (Join-Path $fixtureRoot 'learner/active-session.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    Assert-True $savedActiveSession.active 'Saved active session should remain active.'
    Assert-Equal 'hash-table' $savedActiveSession.topic_id 'Saved active session topic mismatch.'
    Assert-Equal 'two-sum' $savedActiveSession.problem_slug 'Saved active session problem mismatch.'
    Assert-Equal 2 $savedActiveSession.hint_level 'Saved active session hint level mismatch.'

    $stateCandidatePath = Join-Path $fixtureRoot 'learner/state.candidate.json'
    $stateCandidate = Get-Content -LiteralPath (Join-Path $fixtureRoot 'learner/state.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    $stateCandidate.updated_at = '2026-09-02T09:20:00+08:00'
    $stateCandidate.current_topic_id = 'diagnosis'
    $stateCandidate.topics.diagnosis.mastery = 1
    $stateCandidate.topics.diagnosis.status = 'learning'
    $stateCandidate.topics.diagnosis.last_studied_at = '2026-09-02T09:20:00+08:00'
    $stateCandidate.topics.diagnosis.next_review_at = '2026-09-03'
    $stateCandidate.topics.diagnosis.sessions_completed = 1
    Write-TestJsonDocument -Path $stateCandidatePath -Document $stateCandidate

    $stateUpdate = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/update-state.ps1' -Arguments @(
        '-Kind', 'state',
        '-CandidatePath', 'learner/state.candidate.json'
    )
    Assert-Equal 0 $stateUpdate.ExitCode 'Saving a valid learner state should succeed.'
    Assert-True ($stateUpdate.Output -match '^UPDATED state$') "state update output mismatch. Output=[$($stateUpdate.Output)]"
    Assert-FileBytesEqual -Expected $attemptBytes -Path $attemptPath -Message 'state update should not modify attempt.cpp.'
    Assert-FileAbsent -Path $referencePath -Message 'reference.cpp should remain absent after state updates below L5.'

    $savedState = Get-Content -LiteralPath (Join-Path $fixtureRoot 'learner/state.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    Assert-Equal 1 $savedState.topics.diagnosis.mastery 'Saved diagnosis mastery mismatch.'
    Assert-Equal 'learning' $savedState.topics.diagnosis.status 'Saved diagnosis status mismatch.'
    Assert-Equal '2026-09-03' $savedState.topics.diagnosis.next_review_at 'Saved diagnosis review date mismatch.'

    $visualizationUpdate = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/update-visualization.ps1'
    Assert-Equal 0 $visualizationUpdate.ExitCode 'update-visualization should succeed for the fixture.'
    Assert-True ($visualizationUpdate.Output -match '^UPDATED visualization/learning-path\.html$') "update-visualization output mismatch. Output=[$($visualizationUpdate.Output)]"
    Assert-FileBytesEqual -Expected $attemptBytes -Path $attemptPath -Message 'visualization update should not modify attempt.cpp.'
    Assert-FileAbsent -Path $referencePath -Message 'reference.cpp should remain absent after visualization regeneration below L5.'

    Import-Module (Join-Path $fixtureRoot 'tools/lib/Visualization.psm1') -Force
    Assert-True (Test-LearningPathVisualizationFresh -RepoRoot $fixtureRoot) 'Visualization should report fresh after regeneration.'

    $finalCheck = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/check.ps1'
    Assert-Equal 0 $finalCheck.ExitCode 'Final check should pass after the end-to-end sequence.'
    Assert-True ($finalCheck.Output -match 'CHECK PASS') "Final check output mismatch. Output=[$($finalCheck.Output)]"
    Assert-FileAbsent -Path $referencePath -Message 'reference.cpp should remain absent through the full non-L5 end-to-end sequence.'

    $cppResult = Invoke-RepoScript -TargetRepoRoot $fixtureRoot -ScriptRelativePath 'tools/test-cpp.ps1' -Arguments @(
        '-ProblemPath', (Join-Path $fixtureRoot 'tests/fixtures/cpp/pass')
    )
    Assert-Equal 0 $cppResult.ExitCode 'test-cpp should never fail for the passing fixture.'
    Assert-True ($cppResult.Output -match '^(PASS|SKIPPED)\b') "test-cpp should report PASS or SKIPPED. Output=[$($cppResult.Output)]"
    Assert-True ($cppResult.Output -notmatch '^FAIL\b') "test-cpp must not report FAIL for the passing fixture. Output=[$($cppResult.Output)]"

    $readmePath = Join-Path $fixtureRoot 'README.md'
    Assert-True (Test-Path -LiteralPath $readmePath -PathType Leaf) 'README.md is missing from the fixture.'
    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding utf8

    foreach ($section in @(
        '快速开始',
        '仓库结构',
        '一次学习如何进行',
        '五级提示',
        '常用 PowerShell 命令',
        '安装 C++ 编译器后的验证',
        '学习状态和可视化',
        '数据恢复',
        '当前限制'
    )) {
        Assert-True ($readme.Contains($section)) "README.md is missing section [$section]."
    }

    foreach ($phrase in @(
        '开始今天的学习',
        '继续上次的学习',
        '学习 LeetCode 1',
        '给我下一级提示',
        '复盘这道题并安排复习'
    )) {
        Assert-True ($readme.Contains($phrase)) "README.md is missing learner phrase [$phrase]."
    }

    Assert-True ($readme.Contains('SKIPPED')) 'README.md should explain that C++ execution reports SKIPPED when no compiler is installed.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
