Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force
Import-Module "$RepoRoot/tools/lib/JsonStore.psm1" -Force

$problemWorkspaceModulePath = Join-Path $RepoRoot 'tools/lib/ProblemWorkspace.psm1'
if (Test-Path -LiteralPath $problemWorkspaceModulePath) {
    Import-Module $problemWorkspaceModulePath -Force
}

function New-TestRepositoryFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-problem-workspace-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    $curriculumRoot = Join-Path $resolvedFixtureRoot 'curriculum'
    $problemsRoot = Join-Path $resolvedFixtureRoot 'problems'
    $templateRoot = Join-Path $problemsRoot '_template'
    New-Item -ItemType Directory -Path $curriculumRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination $curriculumRoot -Force

    $repoTemplateRoot = Join-Path $RepoRoot 'problems/_template'
    if (Test-Path -LiteralPath $repoTemplateRoot -PathType Container) {
        foreach ($child in Get-ChildItem -LiteralPath $repoTemplateRoot -Force) {
            Copy-Item -LiteralPath $child.FullName -Destination $templateRoot -Recurse -Force
        }
    } else {
        Set-Content -LiteralPath (Join-Path $templateRoot 'attempt.cpp') -Value @'
#include <vector>

using namespace std;

class Solution {
public:
    // Write the LeetCode method signature and your implementation here.
};
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $templateRoot 'tests.cpp') -Value @'
#include "attempt.cpp"

int main() {
    // Add learner assertions here.
    return 0;
}
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $templateRoot 'review.md') -Value @'
# Review

- Invariant:
- Complexity:
- Original blocker:
- Edge cases:
- Transfer signal:
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $templateRoot 'meta.json') -Value @'
{
  "schema_version": 1,
  "source": "__SOURCE__",
  "problem_id": "__PROBLEM_ID__",
  "slug": "__SLUG__",
  "title": "__TITLE__",
  "url": "__URL__",
  "difficulty": "__DIFFICULTY__",
  "primary_topic_id": "__PRIMARY_TOPIC_ID__",
  "secondary_topic_ids": [],
  "status": "new",
  "attempt_count": 0,
  "highest_hint_level_used": 0,
  "created_at": "__CREATED_AT__",
  "last_attempted_at": null
}
'@ -Encoding utf8
    }

    return $resolvedFixtureRoot
}

function New-ProblemParameters {
    param([string]$RepoRoot)

    return @{
        RepoRoot = $RepoRoot
        ProblemId = '1'
        Slug = 'two-sum'
        Title = 'Two Sum'
        Source = 'leetcode'
        Url = 'https://leetcode.com/problems/two-sum/'
        Difficulty = 'easy'
        PrimaryTopicId = 'hash-table'
        SecondaryTopicIds = @('arrays-strings')
    }
}

function Assert-TemplateFilePresent {
    param(
        [string]$Path,
        [string]$Message
    )

    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) $Message
}

function Read-TestJsonDocument {
    param([string]$Path)

    $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
        return $raw | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop
    }

    return $raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
}

$testRoot = New-TestRepositoryFixture
try {
    $problemParameters = New-ProblemParameters -RepoRoot $testRoot
    $created = New-ProblemWorkspace @problemParameters

    Assert-Equal (Join-Path (Join-Path $testRoot 'problems') '1-two-sum') $created 'Problem workspace path mismatch.'
    Assert-True (Test-Path -LiteralPath (Join-Path $created 'attempt.cpp')) 'attempt.cpp was not created.'
    Assert-True (Test-Path -LiteralPath (Join-Path $created 'tests.cpp')) 'tests.cpp was not created.'
    $meta = Read-TestJsonDocument (Join-Path $created 'meta.json')
    Assert-Equal 'hash-table' $meta.primary_topic_id 'Primary topic mismatch.'
    Assert-Equal 1 $meta.secondary_topic_ids.Count 'Secondary topics mismatch.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $created 'reference.cpp'))) 'Reference must not exist initially.'

    Set-Content -LiteralPath (Join-Path $created 'attempt.cpp') -Value '// learner work' -Encoding utf8
    Assert-Throws { New-ProblemWorkspace @problemParameters } 'already exists'
    Assert-Equal '// learner work' (Get-Content -Raw -LiteralPath (Join-Path $created 'attempt.cpp')).Trim() 'Existing attempt was overwritten.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$validationRoot = New-TestRepositoryFixture
try {
    Assert-Throws {
        $bad = New-ProblemParameters -RepoRoot $validationRoot
        $bad.Slug = 'two/sum'
        New-ProblemWorkspace @bad
    } 'slug|invalid'
    Assert-Throws {
        $bad = New-ProblemParameters -RepoRoot $validationRoot
        $bad.PrimaryTopicId = 'unknown-topic'
        New-ProblemWorkspace @bad
    } 'primary_topic_id|does not exist'
    Assert-Throws {
        $bad = New-ProblemParameters -RepoRoot $validationRoot
        $bad.SecondaryTopicIds = @('arrays-strings', 'stack-queue', 'graph')
        New-ProblemWorkspace @bad
    } 'at most two'
    Assert-Throws {
        $bad = New-ProblemParameters -RepoRoot $validationRoot
        $bad.SecondaryTopicIds = @('hash-table')
        New-ProblemWorkspace @bad
    } 'duplicate|primary'
    Assert-Throws {
        $bad = New-ProblemParameters -RepoRoot $validationRoot
        $bad.Source = 'hackerrank'
        New-ProblemWorkspace @bad
    } 'source|invalid'
}
finally {
    if (Test-Path -LiteralPath $validationRoot) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $validationRoot -Recurse -Force
    }
}

$repoTemplateRoot = Join-Path $RepoRoot 'problems/_template'
Assert-TemplateFilePresent (Join-Path $repoTemplateRoot 'meta.json') 'Repository template meta.json is missing.'
Assert-TemplateFilePresent (Join-Path $repoTemplateRoot 'attempt.cpp') 'Repository template attempt.cpp is missing.'
Assert-TemplateFilePresent (Join-Path $repoTemplateRoot 'tests.cpp') 'Repository template tests.cpp is missing.'
Assert-TemplateFilePresent (Join-Path $repoTemplateRoot 'review.md') 'Repository template review.md is missing.'

$attemptTemplate = Get-Content -Raw -LiteralPath (Join-Path $repoTemplateRoot 'attempt.cpp')
Assert-True ($attemptTemplate -match 'class Solution') 'attempt.cpp template must define Solution.'
Assert-True ($attemptTemplate -match 'Write the LeetCode method signature') 'attempt.cpp template must remain instructional.'

$testsTemplate = Get-Content -Raw -LiteralPath (Join-Path $repoTemplateRoot 'tests.cpp')
Assert-True ($testsTemplate -match '#include "attempt\.cpp"') 'tests.cpp template must include attempt.cpp.'
Assert-True ($testsTemplate -match 'int main\(\)') 'tests.cpp template must define main.'

$reviewTemplate = Get-Content -Raw -LiteralPath (Join-Path $repoTemplateRoot 'review.md')
Assert-True ($reviewTemplate -match 'Invariant') 'review.md must ask for the invariant.'
Assert-True ($reviewTemplate -match 'Complexity') 'review.md must ask for complexity.'
Assert-True ($reviewTemplate -match 'Original blocker') 'review.md must ask for the original blocker.'
Assert-True ($reviewTemplate -match 'Edge cases') 'review.md must ask for edge cases.'
Assert-True ($reviewTemplate -match 'Transfer signal') 'review.md must ask for the transfer signal.'

$cliRepoRoot = New-TestRepositoryFixture
try {
    $cliScriptPath = Join-Path $RepoRoot 'tools/new-problem.ps1'
    $cliParameters = New-ProblemParameters -RepoRoot $cliRepoRoot

    $createdOutput = & pwsh -NoProfile -File $cliScriptPath `
        -RepoRoot $cliParameters.RepoRoot `
        -ProblemId $cliParameters.ProblemId `
        -Slug $cliParameters.Slug `
        -Title $cliParameters.Title `
        -Source $cliParameters.Source `
        -Url $cliParameters.Url `
        -Difficulty $cliParameters.Difficulty `
        -PrimaryTopicId $cliParameters.PrimaryTopicId `
        -SecondaryTopicIds $cliParameters.SecondaryTopicIds 2>&1
    $createdExitCode = $LASTEXITCODE

    Assert-Equal 0 $createdExitCode 'CLI should succeed for a valid new workspace.'
    Assert-True (($createdOutput -join [Environment]::NewLine) -match '^CREATED .+1-two-sum') 'CLI success output mismatch.'

    $repeatOutput = & pwsh -NoProfile -File $cliScriptPath `
        -RepoRoot $cliParameters.RepoRoot `
        -ProblemId $cliParameters.ProblemId `
        -Slug $cliParameters.Slug `
        -Title $cliParameters.Title `
        -Source $cliParameters.Source `
        -Url $cliParameters.Url `
        -Difficulty $cliParameters.Difficulty `
        -PrimaryTopicId $cliParameters.PrimaryTopicId `
        -SecondaryTopicIds $cliParameters.SecondaryTopicIds 2>&1
    $repeatExitCode = $LASTEXITCODE

    Assert-Equal 1 $repeatExitCode 'CLI should fail when the workspace already exists.'
    Assert-True (($repeatOutput -join [Environment]::NewLine) -match '^ERROR .+already exists') 'CLI failure output mismatch.'
}
finally {
    if (Test-Path -LiteralPath $cliRepoRoot) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $cliRepoRoot -Recurse -Force
    }
}
