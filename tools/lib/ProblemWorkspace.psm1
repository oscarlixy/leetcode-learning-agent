Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'JsonStore.psm1') -Force

function New-ProblemWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        $ProblemId,

        [Parameter(Mandatory = $true)]
        [string]$Slug,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Difficulty,

        [Parameter(Mandatory = $true)]
        [string]$PrimaryTopicId,

        [string[]]$SecondaryTopicIds = @()
    )

    $resolvedRepoRoot = Resolve-RepoScopedPath -Path $RepoRoot -BasePath $RepoRoot -Label 'repository root'
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "Repository root [$resolvedRepoRoot] does not exist."
    }

    $roadmapPath = Resolve-RepoScopedPath -Path 'curriculum/roadmap.json' -BasePath $resolvedRepoRoot -Label 'roadmap'
    $roadmap = Validation\Read-JsonDocument $roadmapPath

    $resolvedProblemsRoot = Resolve-RepoScopedPath -Path 'problems' -BasePath $resolvedRepoRoot -Label 'problems root'
    if (-not (Test-Path -LiteralPath $resolvedProblemsRoot -PathType Container)) {
        throw "Problems root [$resolvedProblemsRoot] does not exist."
    }

    $templateRoot = Resolve-RepoScopedPath -Path 'problems/_template' -BasePath $resolvedRepoRoot -Label 'problem template'
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        throw "Problem template [$templateRoot] does not exist."
    }

    $canonicalProblemId = Assert-ProblemIdPathSegment -ProblemId $ProblemId
    $canonicalSlug = Assert-CanonicalSlug -Slug $Slug
    $destinationLeafName = '{0}-{1}' -f $canonicalProblemId, $canonicalSlug
    $destinationPath = Resolve-RepoScopedPath -Path (Join-Path 'problems' $destinationLeafName) -BasePath $resolvedRepoRoot -Label 'problem workspace'
    Assert-ChildPath -RootPath $resolvedProblemsRoot -CandidatePath $destinationPath -Label 'problem workspace'

    if (Test-Path -LiteralPath $destinationPath) {
        throw 'problem workspace already exists'
    }

    $stagingLeafName = '.staging-{0}-{1}' -f $destinationLeafName, [System.Guid]::NewGuid().ToString('N')
    $stagingPath = Resolve-RepoScopedPath -Path (Join-Path 'problems' $stagingLeafName) -BasePath $resolvedRepoRoot -Label 'problem staging workspace'
    Assert-ChildPath -RootPath $resolvedProblemsRoot -CandidatePath $stagingPath -Label 'problem staging workspace'

    try {
        New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null
        Copy-TemplateContent -TemplateRoot $templateRoot -DestinationPath $stagingPath

        $metaDocument = New-ProblemMetaDocument `
            -ProblemId $ProblemId `
            -Slug $canonicalSlug `
            -Title $Title `
            -Source $Source `
            -Url $Url `
            -Difficulty $Difficulty `
            -PrimaryTopicId $PrimaryTopicId `
            -SecondaryTopicIds $SecondaryTopicIds

        $metaPath = Join-Path $stagingPath 'meta.json'
        JsonStore\Write-JsonAtomic -Path $metaPath -Value $metaDocument -Validation {
            param($Document)
            Validation\Assert-ProblemDocument $Document $roadmap
        }

        [System.IO.Directory]::Move($stagingPath, $destinationPath)
        return $destinationPath
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
    }
}

function New-ProblemMetaDocument {
    param(
        $ProblemId,
        [string]$Slug,
        [string]$Title,
        [string]$Source,
        [string]$Url,
        [string]$Difficulty,
        [string]$PrimaryTopicId,
        [string[]]$SecondaryTopicIds
    )

    return [pscustomobject]@{
        schema_version = 1
        source = $Source
        problem_id = $ProblemId
        slug = $Slug
        title = $Title
        url = $Url
        difficulty = $Difficulty
        primary_topic_id = $PrimaryTopicId
        secondary_topic_ids = @($SecondaryTopicIds)
        status = 'new'
        attempt_count = 0
        highest_hint_level_used = 0
        created_at = ([datetimeoffset]::Now.ToString('o'))
        last_attempted_at = $null
    }
}

function Copy-TemplateContent {
    param(
        [string]$TemplateRoot,
        [string]$DestinationPath
    )

    foreach ($child in Get-ChildItem -LiteralPath $TemplateRoot -Force -ErrorAction Stop) {
        Copy-Item -LiteralPath $child.FullName -Destination $DestinationPath -Recurse -Force
    }
}

function Assert-CanonicalSlug {
    param([string]$Slug)

    if ($Slug -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "problem slug [$Slug] must use lowercase ASCII letters, digits, and single hyphens."
    }

    return $Slug
}

function Assert-ProblemIdPathSegment {
    param($ProblemId)

    if ($ProblemId -is [string]) {
        if ([string]::IsNullOrWhiteSpace($ProblemId)) {
            throw 'problem_id must not be empty.'
        }
    } elseif (
        $ProblemId -is [byte] -or
        $ProblemId -is [sbyte] -or
        $ProblemId -is [int16] -or
        $ProblemId -is [uint16] -or
        $ProblemId -is [int32] -or
        $ProblemId -is [uint32] -or
        $ProblemId -is [int64] -or
        $ProblemId -is [uint64]
    ) {
        if ($ProblemId -lt 1) {
            throw 'problem_id must be positive.'
        }
    } else {
        throw 'problem_id must be an integer or string.'
    }

    $problemIdText = [string]$ProblemId
    if ($problemIdText -eq '.' -or $problemIdText -eq '..') {
        throw "problem_id [$problemIdText] must be a single safe path segment."
    }
    if (
        $problemIdText.Contains([System.IO.Path]::DirectorySeparatorChar) -or
        $problemIdText.Contains([System.IO.Path]::AltDirectorySeparatorChar)
    ) {
        throw "problem_id [$problemIdText] must be a single safe path segment."
    }

    return $problemIdText
}

function Resolve-RepoScopedPath {
    param(
        [string]$Path,
        [string]$BasePath,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label path must not be empty."
    }

    Assert-NoWildcardPath -Path $Path -Label $Label

    $resolvedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    $candidatePath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $resolvedBasePath $Path))
    }

    if (-not (Test-PathWithinRoot -RootPath $resolvedBasePath -CandidatePath $candidatePath)) {
        throw "$Label path [$candidatePath] must stay within repository root [$resolvedBasePath]."
    }

    return $candidatePath
}

function Assert-ChildPath {
    param(
        [string]$RootPath,
        [string]$CandidatePath,
        [string]$Label
    )

    if (-not (Test-PathWithinRoot -RootPath $RootPath -CandidatePath $CandidatePath)) {
        throw "$Label path [$CandidatePath] must stay within [$RootPath]."
    }
}

function Test-PathWithinRoot {
    param(
        [string]$RootPath,
        [string]$CandidatePath
    )

    $trimmedRootPath = Trim-TrailingDirectorySeparators -Path $RootPath
    $trimmedCandidatePath = Trim-TrailingDirectorySeparators -Path $CandidatePath

    if ($trimmedCandidatePath.Equals($trimmedRootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = $trimmedRootPath + [System.IO.Path]::DirectorySeparatorChar
    return $trimmedCandidatePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Trim-TrailingDirectorySeparators {
    param([string]$Path)

    $trimmedPath = $Path
    while (
        $trimmedPath.Length -gt 0 -and
        (
            $trimmedPath.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or
            $trimmedPath.EndsWith([System.IO.Path]::AltDirectorySeparatorChar)
        )
    ) {
        $trimmedPath = $trimmedPath.Substring(0, $trimmedPath.Length - 1)
    }

    return $trimmedPath
}

function Assert-NoWildcardPath {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "$Label path [$Path] must not contain wildcard characters."
    }
}

Export-ModuleMember -Function @(
    'New-ProblemWorkspace'
)
