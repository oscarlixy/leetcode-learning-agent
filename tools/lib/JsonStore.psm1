Set-StrictMode -Version Latest

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Validation,

        [string]$BackupPath
    )

    Assert-NoWildcardPath $Path 'destination'
    if ($PSBoundParameters.ContainsKey('BackupPath') -and $null -ne $BackupPath) {
        Assert-NoWildcardPath $BackupPath 'backup'
    }

    $destinationPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedBackupPath = if ($PSBoundParameters.ContainsKey('BackupPath') -and $null -ne $BackupPath) {
        [System.IO.Path]::GetFullPath($BackupPath)
    } else {
        $null
    }

    $directoryPath = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        throw "Destination directory [$directoryPath] does not exist."
    }

    $tempFileName = [System.IO.Path]::GetFileName($destinationPath) + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $tempPath = Join-Path $directoryPath $tempFileName

    try {
        $json = $Value | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))

        $tempDocument = Read-JsonStoreDocument $tempPath
        & $Validation $tempDocument

        if (Test-Path -LiteralPath $destinationPath) {
            if ($null -eq $resolvedBackupPath) {
                [System.IO.File]::Move($tempPath, $destinationPath, $true)
            } else {
                [System.IO.File]::Replace($tempPath, $destinationPath, $resolvedBackupPath, $true)
            }
        } else {
            [System.IO.File]::Move($tempPath, $destinationPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Save-LearnerDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('state', 'active-session')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Resolve-RepoScopedPath -Path $RepoRoot -BasePath $RepoRoot -Label 'repository root'
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "Repository root [$resolvedRepoRoot] does not exist."
    }

    $resolvedCandidatePath = Resolve-RepoScopedPath -Path $CandidatePath -BasePath $resolvedRepoRoot -Label 'candidate'
    if (-not (Test-Path -LiteralPath $resolvedCandidatePath -PathType Leaf)) {
        throw "Candidate file [$resolvedCandidatePath] does not exist."
    }

    $roadmapPath = Resolve-RepoScopedPath -Path 'curriculum/roadmap.json' -BasePath $resolvedRepoRoot -Label 'roadmap'
    $roadmap = Validation\Read-JsonDocument $roadmapPath

    switch ($Kind) {
        'state' {
            $documentPath = Resolve-RepoScopedPath -Path 'learner/state.json' -BasePath $resolvedRepoRoot -Label 'state'
            $backupPath = Resolve-RepoScopedPath -Path 'learner/state.backup.json' -BasePath $resolvedRepoRoot -Label 'state backup'
            $candidateDocument = Validation\Read-JsonDocument $resolvedCandidatePath
            Validation\Assert-StateDocument $candidateDocument $roadmap

            Write-JsonAtomic -Path $documentPath -Value $candidateDocument -BackupPath $backupPath -Validation {
                param($Document)
                Validation\Assert-StateDocument $Document $roadmap
            }
        }
        'active-session' {
            $documentPath = Resolve-RepoScopedPath -Path 'learner/active-session.json' -BasePath $resolvedRepoRoot -Label 'active-session'
            $problemsRoot = Resolve-RepoScopedPath -Path 'problems' -BasePath $resolvedRepoRoot -Label 'problems'
            $candidateDocument = Validation\Read-JsonDocument $resolvedCandidatePath
            Validation\Assert-ActiveSessionDocument $candidateDocument $roadmap $problemsRoot

            Write-JsonAtomic -Path $documentPath -Value $candidateDocument -Validation {
                param($Document)
                Validation\Assert-ActiveSessionDocument $Document $roadmap $problemsRoot
            }
        }
    }
}

function Save-ProblemMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProblemPath,

        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Resolve-RepoScopedPath -Path $RepoRoot -BasePath $RepoRoot -Label 'repository root'
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "Repository root [$resolvedRepoRoot] does not exist."
    }

    $problemsRoot = Resolve-RepoScopedPath -Path 'problems' -BasePath $resolvedRepoRoot -Label 'problems root'
    $resolvedProblemPath = Resolve-RepoScopedPath -Path $ProblemPath -BasePath $resolvedRepoRoot -Label 'problem workspace'
    if (-not (Test-Path -LiteralPath $resolvedProblemPath -PathType Container)) {
        throw "Problem workspace [$resolvedProblemPath] does not exist."
    }
    if (-not (Test-IsDirectChildPath -ParentPath $problemsRoot -CandidatePath $resolvedProblemPath)) {
        throw "Problem workspace [$resolvedProblemPath] must be a direct child of [$problemsRoot]."
    }
    if ([string]::Equals([System.IO.Path]::GetFileName($resolvedProblemPath), '_template', [System.StringComparison]::Ordinal)) {
        throw 'Problem template metadata cannot be updated as a learner problem.'
    }

    foreach ($requiredFileName in @('attempt.cpp', 'tests.cpp', 'review.md', 'meta.json')) {
        $requiredPath = Join-Path $resolvedProblemPath $requiredFileName
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Problem workspace required file [$requiredFileName] is missing."
        }
    }

    $resolvedCandidatePath = Resolve-RepoScopedPath -Path $CandidatePath -BasePath $resolvedRepoRoot -Label 'problem metadata candidate'
    if (-not (Test-Path -LiteralPath $resolvedCandidatePath -PathType Leaf)) {
        throw "Problem metadata candidate [$resolvedCandidatePath] does not exist."
    }

    $roadmap = Validation\Read-JsonDocument (Resolve-RepoScopedPath -Path 'curriculum/roadmap.json' -BasePath $resolvedRepoRoot -Label 'roadmap')
    $metaPath = Join-Path $resolvedProblemPath 'meta.json'
    $currentDocument = Validation\Read-JsonDocument $metaPath
    $candidateDocument = Validation\Read-JsonDocument $resolvedCandidatePath
    Validation\Assert-ProblemDocument $currentDocument $roadmap
    Validation\Assert-ProblemDocument $candidateDocument $roadmap

    Assert-ProblemMetadataTransition `
        -CurrentDocument $currentDocument `
        -CandidateDocument $candidateDocument `
        -ProblemPath $resolvedProblemPath `
        -RepoRoot $resolvedRepoRoot `
        -Roadmap $roadmap `
        -ProblemsRoot $problemsRoot

    Write-JsonAtomic -Path $metaPath -Value $candidateDocument -Validation {
        param($Document)
        Validation\Assert-ProblemDocument $Document $roadmap
        Assert-ProblemMetadataIdentity -Document $Document -ProblemPath $resolvedProblemPath
    }

    return $resolvedProblemPath
}

function Assert-ProblemMetadataTransition {
    param(
        $CurrentDocument,
        $CandidateDocument,
        [string]$ProblemPath,
        [string]$RepoRoot,
        $Roadmap,
        [string]$ProblemsRoot
    )

    Assert-ProblemMetadataIdentity -Document $CurrentDocument -ProblemPath $ProblemPath
    Assert-ProblemMetadataIdentity -Document $CandidateDocument -ProblemPath $ProblemPath

    foreach ($identityField in @('problem_id', 'slug', 'created_at')) {
        $currentValue = Get-ExactJsonPropertyValue -Document $CurrentDocument -PropertyName $identityField
        $candidateValue = Get-ExactJsonPropertyValue -Document $CandidateDocument -PropertyName $identityField
        $unchanged = if ($currentValue -is [string] -and $candidateValue -is [string]) {
            [string]::Equals($currentValue, $candidateValue, [System.StringComparison]::Ordinal)
        } else {
            $currentValue.GetType() -eq $candidateValue.GetType() -and $currentValue.Equals($candidateValue)
        }
        if (-not $unchanged) {
            throw "Problem metadata identity field [$identityField] cannot change."
        }
    }

    if ($CandidateDocument.attempt_count -lt $CurrentDocument.attempt_count) {
        throw 'Problem metadata attempt_count cannot decrease.'
    }
    if ($CandidateDocument.highest_hint_level_used -lt $CurrentDocument.highest_hint_level_used) {
        throw 'Problem metadata highest_hint_level_used cannot decrease.'
    }
    if ($CandidateDocument.attempt_count -gt $CurrentDocument.attempt_count -and $null -eq $CandidateDocument.last_attempted_at) {
        throw 'Problem metadata last_attempted_at is required when attempt_count increases.'
    }

    $activeSessionPath = Resolve-RepoScopedPath -Path 'learner/active-session.json' -BasePath $RepoRoot -Label 'active-session'
    if (Test-Path -LiteralPath $activeSessionPath -PathType Leaf) {
        $activeSession = Validation\Read-JsonDocument $activeSessionPath
        Validation\Assert-ActiveSessionDocument $activeSession $Roadmap $ProblemsRoot
        if (
            $activeSession.active -and
            $null -ne $activeSession.problem_slug -and
            [string]::Equals($activeSession.problem_slug, $CandidateDocument.slug, [System.StringComparison]::Ordinal) -and
            $CandidateDocument.highest_hint_level_used -lt $activeSession.hint_level
        ) {
            throw "Problem metadata highest_hint_level_used must be at least the active-session hint_level [$($activeSession.hint_level)]."
        }
    }
}

function Assert-ProblemMetadataIdentity {
    param(
        $Document,
        [string]$ProblemPath
    )

    $expectedLeafName = '{0}-{1}' -f $Document.problem_id, $Document.slug
    $actualLeafName = [System.IO.Path]::GetFileName($ProblemPath)
    if (-not [string]::Equals($actualLeafName, $expectedLeafName, [System.StringComparison]::Ordinal)) {
        throw "Problem workspace directory [$actualLeafName] must match metadata identity [$expectedLeafName]."
    }
}

function Get-ExactJsonPropertyValue {
    param(
        $Document,
        [string]$PropertyName
    )

    $matches = @($Document.PSObject.Properties | Where-Object { $_.Name -ceq $PropertyName })
    if ($matches.Count -ne 1) {
        throw "Problem metadata property [$PropertyName] is missing or ambiguous."
    }
    return $matches[0].Value
}

function Test-IsDirectChildPath {
    param(
        [string]$ParentPath,
        [string]$CandidatePath
    )

    $candidateParent = [System.IO.Path]::GetDirectoryName((Trim-TrailingDirectorySeparators $CandidatePath))
    $normalizedParent = Trim-TrailingDirectorySeparators ([System.IO.Path]::GetFullPath($ParentPath))
    return [string]::Equals($candidateParent, $normalizedParent, [System.StringComparison]::OrdinalIgnoreCase)
}

function Read-JsonStoreDocument {
    param([string]$Path)

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    }
    catch {
        throw "Failed to read JSON document [$Path]: $($_.Exception.Message)"
    }

    try {
        $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
        if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
            return $raw | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop
        }
        return $raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON document [$Path]: $($_.Exception.Message)"
    }
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

    Assert-NoWildcardPath $Path $Label

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

function Test-PathWithinRoot {
    param(
        [string]$RootPath,
        [string]$CandidatePath
    )

    $trimmedRootPath = Trim-TrailingDirectorySeparators $RootPath
    $trimmedCandidatePath = Trim-TrailingDirectorySeparators $CandidatePath

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

    if ($Path.Contains('*') -or $Path.Contains('?')) {
        throw "$Label path [$Path] must not contain wildcard characters."
    }
}

Export-ModuleMember -Function @(
    'Write-JsonAtomic',
    'Save-LearnerDocument',
    'Save-ProblemMetadata'
)
