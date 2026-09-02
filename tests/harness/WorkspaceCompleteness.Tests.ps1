Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/ProblemWorkspace.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Visualization.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tools/lib/Validation.psm1') -Force

function New-WorkspaceFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-workspace-completeness-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $resolvedFixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path

    foreach ($directory in @('curriculum', 'learner', 'problems', 'problems/_template', 'visualization')) {
        New-Item -ItemType Directory -Path (Join-Path $resolvedFixtureRoot $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $resolvedFixtureRoot 'curriculum/roadmap.json') -Force
    foreach ($learnerFile in @('profile.json', 'state.json', 'state.backup.json', 'active-session.json')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot "learner/$learnerFile") -Destination (Join-Path $resolvedFixtureRoot "learner/$learnerFile") -Force
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'visualization/learning-path.template.html') -Destination (Join-Path $resolvedFixtureRoot 'visualization/learning-path.template.html') -Force
    foreach ($templateChild in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'problems/_template') -Force) {
        Copy-Item -LiteralPath $templateChild.FullName -Destination (Join-Path $resolvedFixtureRoot 'problems/_template') -Recurse -Force
    }
    Update-LearningPathVisualization -RepoRoot $resolvedFixtureRoot | Out-Null
    return $resolvedFixtureRoot
}

function New-ProblemArguments {
    param([string]$TargetRepoRoot)

    return @{
        RepoRoot = $TargetRepoRoot
        ProblemId = 1
        Slug = 'two-sum'
        Title = 'Two Sum'
        Source = 'leetcode'
        Url = 'https://leetcode.com/problems/two-sum/'
        Difficulty = 'easy'
        PrimaryTopicId = 'hash-table'
        SecondaryTopicIds = @('arrays-strings')
    }
}

function Assert-NoPublishedWorkspace {
    param([string]$TargetRepoRoot)

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $TargetRepoRoot 'problems/1-two-sum'))) 'A failed staging attempt must not publish the workspace.'
}

$missingTemplateRoot = New-WorkspaceFixture
try {
    $templateTestsPath = Join-Path $missingTemplateRoot 'problems/_template/tests.cpp'
    Remove-Item -LiteralPath $templateTestsPath -Force
    $problemArguments = New-ProblemArguments -TargetRepoRoot $missingTemplateRoot

    # Break caught: an incomplete template used to publish an incomplete workspace.
    Assert-Throws { New-ProblemWorkspace @problemArguments } 'tests\.cpp|required|template'
    Assert-NoPublishedWorkspace -TargetRepoRoot $missingTemplateRoot

    Copy-Item -LiteralPath (Join-Path $RepoRoot 'problems/_template/tests.cpp') -Destination $templateTestsPath -Force
    $created = New-ProblemWorkspace @problemArguments
    $createdFileNames = @(Get-ChildItem -LiteralPath $created -File | ForEach-Object Name | Sort-Object)
    Assert-Equal 'attempt.cpp,meta.json,review.md,tests.cpp' ($createdFileNames -join ',') 'Published workspace must contain exactly the required files.'
}
finally {
    if (Test-Path -LiteralPath $missingTemplateRoot) {
        Remove-Item -LiteralPath $missingTemplateRoot -Recurse -Force
    }
}

$referenceTemplateRoot = New-WorkspaceFixture
try {
    $templateReferencePath = Join-Path $referenceTemplateRoot 'problems/_template/reference.cpp'
    Set-Content -LiteralPath $templateReferencePath -Value '// template must never ship a reference' -Encoding utf8
    $problemArguments = New-ProblemArguments -TargetRepoRoot $referenceTemplateRoot

    Assert-Throws { New-ProblemWorkspace @problemArguments } 'reference\.cpp|template|unexpected'
    Assert-NoPublishedWorkspace -TargetRepoRoot $referenceTemplateRoot
    Remove-Item -LiteralPath $templateReferencePath -Force
    Assert-True ((New-ProblemWorkspace @problemArguments) -like '*1-two-sum') 'A clean retry after rejecting template reference.cpp must succeed.'
}
finally {
    if (Test-Path -LiteralPath $referenceTemplateRoot) {
        Remove-Item -LiteralPath $referenceTemplateRoot -Recurse -Force
    }
}

if ($IsWindows) {
    $copyFailureRoot = New-WorkspaceFixture
    try {
        $lockedTemplatePath = Join-Path $copyFailureRoot 'problems/_template/attempt.cpp'
        $lock = [System.IO.File]::Open($lockedTemplatePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $problemArguments = New-ProblemArguments -TargetRepoRoot $copyFailureRoot
            Assert-Throws { New-ProblemWorkspace @problemArguments } 'copy|attempt\.cpp|process|used by another'
        }
        finally {
            $lock.Dispose()
        }

        Assert-NoPublishedWorkspace -TargetRepoRoot $copyFailureRoot
        Assert-True ((New-ProblemWorkspace @problemArguments) -like '*1-two-sum') 'A clean retry after a terminating copy failure must succeed.'
    }
    finally {
        if (Test-Path -LiteralPath $copyFailureRoot) {
            Remove-Item -LiteralPath $copyFailureRoot -Recurse -Force
        }
    }
}

$incompleteExistingRoot = New-WorkspaceFixture
try {
    $problemArguments = New-ProblemArguments -TargetRepoRoot $incompleteExistingRoot
    $created = New-ProblemWorkspace @problemArguments
    Remove-Item -LiteralPath (Join-Path $created 'review.md') -Force

    $checkOutput = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/check.ps1') -RepoRoot $incompleteExistingRoot 2>&1
    $checkExitCode = $LASTEXITCODE
    $checkText = $checkOutput -join [Environment]::NewLine
    Assert-Equal 1 $checkExitCode 'check.ps1 must reject an incomplete existing workspace.'
    Assert-True ($checkText -match 'review\.md') "Incomplete workspace error must name review.md. Output=[$checkText]"
}
finally {
    if (Test-Path -LiteralPath $incompleteExistingRoot) {
        Remove-Item -LiteralPath $incompleteExistingRoot -Recurse -Force
    }
}
