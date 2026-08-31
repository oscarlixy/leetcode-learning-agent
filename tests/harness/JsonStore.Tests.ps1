Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force
Import-Module "$RepoRoot/tools/lib/JsonStore.psm1" -Force

function New-TestRepositoryFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-json-store-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    $curriculumRoot = Join-Path $resolvedFixtureRoot 'curriculum'
    $learnerRoot = Join-Path $resolvedFixtureRoot 'learner'
    New-Item -ItemType Directory -Path $curriculumRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination $curriculumRoot -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner') -Destination $resolvedFixtureRoot -Recurse -Force

    return $resolvedFixtureRoot
}

function Get-WriteJsonAtomicCommandAsts {
    $scriptBlock = (Get-Command Write-JsonAtomic -CommandType Function).ScriptBlock
    return @(
        $scriptBlock.Ast.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst]
            },
            $true
        )
    )
}

$testRoot = New-TestRepositoryFixture
try {
    $statePath = Join-Path $testRoot 'learner/state.json'
    $candidatePath = Join-Path $testRoot 'learner/state.candidate.json'
    $invalidPath = Join-Path $testRoot 'learner/state.invalid.json'

    $before = Get-Content -LiteralPath $statePath -Raw
    $candidate = Read-JsonDocument $statePath
    $candidate.topics.diagnosis.mastery = 1
    $candidate.topics.diagnosis.status = 'learning'
    $candidate.updated_at = '2026-08-31T12:00:00+08:00'
    $candidate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $candidatePath -Encoding utf8

    Save-LearnerDocument -Kind state -CandidatePath $candidatePath -RepoRoot $testRoot
    $saved = Read-JsonDocument $statePath
    Assert-Equal 1 $saved.topics.diagnosis.mastery 'Valid state was not saved.'
    Assert-Equal $before (Get-Content -LiteralPath (Join-Path $testRoot 'learner/state.backup.json') -Raw) 'Backup did not preserve the prior state.'

    $invalid = Read-JsonDocument $statePath
    $invalid.topics.diagnosis.mastery = 9
    $invalid | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidPath -Encoding utf8
    $stable = Get-Content -LiteralPath $statePath -Raw
    Assert-Throws { Save-LearnerDocument -Kind state -CandidatePath $invalidPath -RepoRoot $testRoot } 'mastery'
    Assert-Equal $stable (Get-Content -LiteralPath $statePath -Raw) 'Invalid update changed state.json.'

    $activeSessionPath = Join-Path $testRoot 'learner/active-session.json'
    $activeCandidatePath = Join-Path $testRoot 'learner/active-session.candidate.json'
    $activeCandidate = Read-JsonDocument $activeSessionPath
    $activeCandidate.active = $true
    $activeCandidate.session_id = 'session-1'
    $activeCandidate.started_at = '2026-08-31T12:00:00+08:00'
    $activeCandidate.topic_id = 'diagnosis'
    $activeCandidate.problem_slug = $null
    $activeCandidate.phase = 'solve'
    $activeCandidate.hint_level = 0
    $activeCandidate.last_updated_at = '2026-08-31T12:05:00+08:00'
    $activeCandidate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $activeCandidatePath -Encoding utf8

    $activeBefore = Get-Content -LiteralPath $activeSessionPath -Raw
    Save-LearnerDocument -Kind active-session -CandidatePath $activeCandidatePath -RepoRoot $testRoot

    Assert-True ($activeBefore -ne (Get-Content -LiteralPath $activeSessionPath -Raw)) 'Active session file did not change.'
    $savedActiveSession = Read-JsonDocument $activeSessionPath
    Assert-True $savedActiveSession.active 'Active session was not saved.'
    Assert-Equal 'solve' $savedActiveSession.phase 'Active session phase was not saved.'
    Assert-Equal 'diagnosis' $savedActiveSession.topic_id 'Active session topic was not saved.'
    Assert-Equal $null $savedActiveSession.problem_slug 'Null problem_slug should be preserved.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'learner/active-session.backup.json'))) 'Active session should not create a backup file.'
    $activeSessionArtifacts = @(
        Get-ChildItem -LiteralPath (Join-Path $testRoot 'learner') -File |
            Where-Object { $_.Name -like 'active-session.json.*' -or $_.Name -like 'active-session.*.bak' }
    )
    Assert-Equal 0 $activeSessionArtifacts.Count 'Active session save left a temporary or backup artifact.'

    $writeJsonAtomicCommands = Get-WriteJsonAtomicCommandAsts
    $cleanupCommands = @(
        $writeJsonAtomicCommands |
            Where-Object { $_.GetCommandName() -eq 'Remove-Item' } |
            ForEach-Object { $_.Extent.Text }
    )
    Assert-Equal 1 $cleanupCommands.Count 'Write-JsonAtomic should have exactly one cleanup path.'
    Assert-True ($cleanupCommands[0] -match '\$tempPath') 'Write-JsonAtomic cleanup should target only the temporary file path.'

    $replaceCommands = @(
        $writeJsonAtomicCommands |
            Where-Object { $_.Extent.Text -match '\[System\.IO\.File\]::Replace' } |
            ForEach-Object { $_.Extent.Text }
    )
    $transientBackupReplaceCommands = @(
        $replaceCommands | Where-Object { $_ -match '\.bak|transientBackupPath' }
    )
    Assert-Equal 0 $transientBackupReplaceCommands.Count 'Write-JsonAtomic should not synthesize a transient backup path for no-backup saves.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
