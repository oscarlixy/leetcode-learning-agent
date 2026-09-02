[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProblemPath,

    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $resolvedRepoRoot = if ($PSBoundParameters.ContainsKey('RepoRoot')) {
        (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    } else {
        (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') -ErrorAction Stop).Path
    }

    Import-Module (Join-Path $PSScriptRoot 'lib/Validation.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot 'lib/JsonStore.psm1') -Force -ErrorAction Stop

    $savedProblemPath = Save-ProblemMetadata -ProblemPath $ProblemPath -CandidatePath $CandidatePath -RepoRoot $resolvedRepoRoot
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedRepoRoot, $savedProblemPath).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    Write-Output "UPDATED problem metadata $relativePath"
}
catch {
    Write-Output "ERROR $($_.Exception.Message)"
    exit 1
}
