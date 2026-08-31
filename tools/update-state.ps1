[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('state', 'active-session')]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $resolvedRepoRoot = if ($PSBoundParameters.ContainsKey('RepoRoot')) {
        (Resolve-Path -LiteralPath $RepoRoot).Path
    } else {
        (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    Import-Module (Join-Path $resolvedRepoRoot 'tools/lib/Validation.psm1') -Force
    Import-Module (Join-Path $resolvedRepoRoot 'tools/lib/JsonStore.psm1') -Force

    Save-LearnerDocument -Kind $Kind -CandidatePath $CandidatePath -RepoRoot $resolvedRepoRoot
    Write-Output "UPDATED $Kind"
}
catch {
    Write-Output "ERROR $($_.Exception.Message)"
    exit 1
}
