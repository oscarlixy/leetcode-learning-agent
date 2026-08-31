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

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "$Label path [$Path] must not contain wildcard characters."
    }
}

Export-ModuleMember -Function @(
    'Write-JsonAtomic',
    'Save-LearnerDocument'
)
