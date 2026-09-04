Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/Validation.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/JsonStore.psm1') -Force

function Write-TestJson {
    param(
        [string]$Path,
        $Document
    )

    $Document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

$roadmap = Read-JsonDocument (Join-Path $RepoRoot 'curriculum/roadmap.json')
$inactive = Read-JsonDocument (Join-Path $RepoRoot 'learner/active-session.json')
$completedButActive = $inactive | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
$completedButActive.active = $true
$completedButActive.session_id = 'completed-but-resumable'
$completedButActive.started_at = '2026-09-02T09:00:00+08:00'
$completedButActive.topic_id = 'diagnosis'
$completedButActive.problem_slug = $null
$completedButActive.phase = 'complete'
$completedButActive.hint_level = 0
$completedButActive.last_updated_at = '2026-09-02T09:30:00+08:00'

# Break caught: active=true, phase=complete used to remain a valid resumable session forever.
Assert-Throws {
    Assert-ActiveSessionDocument $completedButActive $roadmap (Join-Path $RepoRoot 'problems')
} 'complete|inactive|active'

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-session-completion-tests-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
    foreach ($directory in @('curriculum', 'learner', 'problems')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $fixtureRoot 'curriculum/roadmap.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/active-session.json') -Destination (Join-Path $fixtureRoot 'learner/active-session.json') -Force

    $activeCandidatePath = Join-Path $fixtureRoot 'learner/active-session.candidate.json'
    $activeCandidate = Read-JsonDocument (Join-Path $fixtureRoot 'learner/active-session.json')
    $activeCandidate.active = $true
    $activeCandidate.session_id = 'session-to-close'
    $activeCandidate.started_at = '2026-09-02T09:00:00+08:00'
    $activeCandidate.topic_id = 'diagnosis'
    $activeCandidate.problem_slug = $null
    $activeCandidate.phase = 'review'
    $activeCandidate.hint_level = 0
    $activeCandidate.last_updated_at = '2026-09-02T09:25:00+08:00'
    Write-TestJson -Path $activeCandidatePath -Document $activeCandidate
    Save-LearnerDocument -Kind active-session -CandidatePath $activeCandidatePath -RepoRoot $fixtureRoot

    $closedCandidatePath = Join-Path $fixtureRoot 'learner/active-session.closed.candidate.json'
    $closedCandidate = [pscustomobject]@{
        schema_version = 1
        active = $false
        session_id = $null
        started_at = $null
        topic_id = $null
        problem_slug = $null
        phase = $null
        hint_level = $null
        last_updated_at = $null
    }
    Write-TestJson -Path $closedCandidatePath -Document $closedCandidate
    Save-LearnerDocument -Kind active-session -CandidatePath $closedCandidatePath -RepoRoot $fixtureRoot

    $saved = Read-JsonDocument (Join-Path $fixtureRoot 'learner/active-session.json')
    Assert-Equal $false $saved.active 'A completed session must be persisted as inactive.'
    foreach ($field in @('session_id', 'started_at', 'topic_id', 'problem_slug', 'phase', 'hint_level', 'last_updated_at')) {
        Assert-Equal $null $saved.$field "Closed session field [$field] must be null."
    }
    Assert-ActiveSessionDocument $saved $roadmap (Join-Path $fixtureRoot 'problems')
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$sessionProtocol = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/session-protocol.md') -Raw -Encoding utf8
Assert-True ($sessionProtocol -match '(?is)successful learner state.{0,300}problem metadata.{0,500}active\s*[:=]\s*false.{0,400}(all|every).{0,120}(null|nullable).{0,500}update-visualization\.ps1') 'Session protocol must document the terminal inactive-session write after learner/problem updates and before visualization refresh.'
Assert-True ($sessionProtocol -match '(?i)offer.{0,100}(continue|resume).{0,160}only.{0,100}active.{0,30}true|active.{0,30}true.{0,160}offer') 'Start behavior must offer resume only for active=true sessions.'
