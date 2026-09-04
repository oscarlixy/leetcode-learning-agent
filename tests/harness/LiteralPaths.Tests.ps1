Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/ProblemWorkspace.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Visualization.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Validation.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/JsonStore.psm1') -Force

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-[literal]-path-tests-" + [System.Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($fixtureRoot)
try {
    foreach ($directory in @('curriculum', 'learner', 'problems', 'problems/_template', 'visualization')) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $fixtureRoot $directory))
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $fixtureRoot 'curriculum/roadmap.json') -Force
    foreach ($learnerFile in @('profile.json', 'state.json', 'state.backup.json', 'active-session.json')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot "learner/$learnerFile") -Destination (Join-Path $fixtureRoot "learner/$learnerFile") -Force
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'visualization/learning-path.template.html') -Destination (Join-Path $fixtureRoot 'visualization/learning-path.template.html') -Force
    foreach ($templateChild in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'problems/_template') -Force) {
        Copy-Item -LiteralPath $templateChild.FullName -Destination (Join-Path $fixtureRoot 'problems/_template') -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tools') -Destination $fixtureRoot -Recurse -Force

    $candidatePath = Join-Path $fixtureRoot 'learner/state.candidate.json'
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'learner/state.json') -Destination $candidatePath -Force

    $stateCliOutput = & pwsh -NoProfile -File (Join-Path $fixtureRoot 'tools/update-state.ps1') `
        -Kind state `
        -CandidatePath 'learner/state.candidate.json' 2>&1
    Assert-Equal 0 $LASTEXITCODE "update-state.ps1 must resolve its default repository root literally. Output=[$($stateCliOutput -join [Environment]::NewLine)]"

    $visualizationCliOutput = & pwsh -NoProfile -File (Join-Path $fixtureRoot 'tools/update-visualization.ps1') 2>&1
    Assert-Equal 0 $LASTEXITCODE "update-visualization.ps1 must resolve its repository root literally. Output=[$($visualizationCliOutput -join [Environment]::NewLine)]"

    # Break caught: literal-path-only operations rejected legal bracket characters as wildcards.
    $outputPath = Update-LearningPathVisualization -RepoRoot $fixtureRoot
    Assert-True (Test-Path -LiteralPath $outputPath -PathType Leaf) 'Visualization must support legal bracket characters in repository paths.'

    $problemPath = New-ProblemWorkspace `
        -RepoRoot $fixtureRoot `
        -ProblemId 1 `
        -Slug 'two-sum' `
        -Title 'Two Sum' `
        -Source 'leetcode' `
        -Url 'https://leetcode.com/problems/two-sum/' `
        -Difficulty 'easy' `
        -PrimaryTopicId 'hash-table'
    Assert-True (Test-Path -LiteralPath $problemPath -PathType Container) 'Problem creation must support legal bracket characters in repository paths.'

    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'learner/state.json') -Destination $candidatePath -Force
    Save-LearnerDocument -Kind state -CandidatePath $candidatePath -RepoRoot $fixtureRoot
    [void](Update-LearningPathVisualization -RepoRoot $fixtureRoot)

    $checkOutput = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/check.ps1') -RepoRoot $fixtureRoot 2>&1
    $checkExitCode = $LASTEXITCODE
    Assert-Equal 0 $checkExitCode 'Consistency checking must support legal bracket characters in repository paths.'
    Assert-True (($checkOutput -join [Environment]::NewLine) -match 'CHECK PASS') 'Bracket-path repository must pass consistency checking.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
