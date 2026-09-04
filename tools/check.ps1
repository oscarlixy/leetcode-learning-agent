[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'lib/Validation.psm1') -Force

try {
    $report = Get-RepositoryConsistencyReport -RepoRoot $RepoRoot
} catch {
    Write-Output "ERROR $($_.Exception.Message)"
    Write-Output 'CHECK FAIL'
    exit 1
}

if ($report.Errors.Count -gt 0) {
    foreach ($errorMessage in $report.Errors) {
        Write-Output "ERROR $errorMessage"
    }

    Write-Output 'CHECK FAIL'
    exit 1
}

foreach ($okMessage in $report.Ok) {
    Write-Output "OK $okMessage"
}

Write-Output 'CHECK PASS'
