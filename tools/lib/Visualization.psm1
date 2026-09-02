Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -Force

function Get-LearningPathInputHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RoadmapPath,

        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $resolvedRoadmapPath = Get-ResolvedPath -Path $RoadmapPath -Label 'roadmap'
    $resolvedStatePath = Get-ResolvedPath -Path $StatePath -Label 'state'

    $roadmapHash = Get-FileSha256Hex -Path $resolvedRoadmapPath
    $stateHash = Get-FileSha256Hex -Path $resolvedStatePath
    return Get-TextSha256Hex -Text "$roadmapHash`:$stateHash"
}

function Update-LearningPathVisualization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Get-ResolvedPath -Path $RepoRoot -Label 'repository root'
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "Repository root [$resolvedRepoRoot] does not exist."
    }

    $roadmapPath = Join-Path $resolvedRepoRoot 'curriculum/roadmap.json'
    $statePath = Join-Path $resolvedRepoRoot 'learner/state.json'
    $templatePath = Join-Path $resolvedRepoRoot 'visualization/learning-path.template.html'
    $outputPath = Join-Path $resolvedRepoRoot 'visualization/learning-path.html'

    $inputHash = Get-LearningPathInputHash -RoadmapPath $roadmapPath -StatePath $statePath
    $roadmap = Validation\Read-JsonDocument $roadmapPath
    $state = Validation\Read-JsonDocument $statePath
    $data = [ordered]@{
        roadmap = $roadmap
        state = $state
    }

    $template = Read-Utf8Text -Path $templatePath
    Assert-ReplacementMarkerCount -Template $template -Marker '__LEARNING_PATH_INPUT_HASH__'
    Assert-ReplacementMarkerCount -Template $template -Marker '__LEARNING_PATH_DATA_JSON__'

    $embeddedJson = ConvertTo-EmbeddedJson -Value $data
    $html = $template.Replace('__LEARNING_PATH_INPUT_HASH__', $inputHash).Replace('__LEARNING_PATH_DATA_JSON__', $embeddedJson)

    Assert-GeneratedHtml -Html $html -ExpectedHash $inputHash
    Write-Utf8TextAtomically -Path $outputPath -Value $html
    return $outputPath
}

function Test-LearningPathVisualizationFresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Get-ResolvedPath -Path $RepoRoot -Label 'repository root'
    $outputPath = Join-Path $resolvedRepoRoot 'visualization/learning-path.html'
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        return $false
    }

    $html = Read-Utf8Text -Path $outputPath
    $match = [System.Text.RegularExpressions.Regex]::Match($html, 'data-input-hash="([a-f0-9]{64})"')
    if (-not $match.Success) {
        return $false
    }

    $currentHash = Get-LearningPathInputHash `
        -RoadmapPath (Join-Path $resolvedRepoRoot 'curriculum/roadmap.json') `
        -StatePath (Join-Path $resolvedRepoRoot 'learner/state.json')

    return $match.Groups[1].Value -eq $currentHash
}

function Get-ResolvedPath {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label path must not be empty."
    }

    if ($Path.Contains('*') -or $Path.Contains('?')) {
        throw "$Label path [$Path] must not contain wildcard characters."
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-FileSha256Hex {
    param([string]$Path)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
    }
    catch {
        throw "Failed to read bytes from [$Path]: $($_.Exception.Message)"
    }

    return Get-ByteArraySha256Hex -Bytes $bytes
}

function Get-TextSha256Hex {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return Get-ByteArraySha256Hex -Bytes $bytes
}

function Get-ByteArraySha256Hex {
    param([byte[]]$Bytes)

    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return [System.Convert]::ToHexString($hashBytes).ToLowerInvariant()
}

function Read-Utf8Text {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    }
    catch {
        throw "Failed to read text file [$Path]: $($_.Exception.Message)"
    }
}

function Assert-ReplacementMarkerCount {
    param(
        [string]$Template,
        [string]$Marker
    )

    $count = [System.Text.RegularExpressions.Regex]::Matches($Template, [System.Text.RegularExpressions.Regex]::Escape($Marker)).Count
    if ($count -eq 0) {
        throw "Template marker [$Marker] is missing."
    }
    if ($count -gt 1) {
        throw "Template marker [$Marker] appears more than once."
    }
}

function ConvertTo-EmbeddedJson {
    param($Value)

    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    return $json.Replace('&', '\u0026').Replace('<', '\u003c').Replace('>', '\u003e').Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
}

function Assert-GeneratedHtml {
    param(
        [string]$Html,
        [string]$ExpectedHash
    )

    if ($Html -notmatch "data-input-hash=""$ExpectedHash""") {
        throw 'Generated visualization is missing the computed input hash.'
    }
    if ($Html -notmatch '"roadmap"') {
        throw 'Generated visualization is missing the roadmap data root.'
    }
    if ($Html -notmatch '"state"') {
        throw 'Generated visualization is missing the state data root.'
    }
}

function Write-Utf8TextAtomically {
    param(
        [string]$Path,
        [string]$Value
    )

    $directoryPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        throw "Destination directory [$directoryPath] does not exist."
    }

    $tempFileName = [System.IO.Path]::GetFileName($Path) + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $tempPath = Join-Path $directoryPath $tempFileName

    try {
        [System.IO.File]::WriteAllText($tempPath, $Value, [System.Text.UTF8Encoding]::new($false))
        Assert-GeneratedHtml -Html (Read-Utf8Text -Path $tempPath) -ExpectedHash ([System.Text.RegularExpressions.Regex]::Match($Value, 'data-input-hash="([a-f0-9]{64})"').Groups[1].Value)

        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Move($tempPath, $Path, $true)
        } else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LearningPathInputHash',
    'Update-LearningPathVisualization',
    'Test-LearningPathVisualizationFresh'
)
