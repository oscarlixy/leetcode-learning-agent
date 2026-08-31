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

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'lib/ProblemWorkspace.psm1') -Force

try {
    $createdPath = New-ProblemWorkspace `
        -RepoRoot $RepoRoot `
        -ProblemId $ProblemId `
        -Slug $Slug `
        -Title $Title `
        -Source $Source `
        -Url $Url `
        -Difficulty $Difficulty `
        -PrimaryTopicId $PrimaryTopicId `
        -SecondaryTopicIds $SecondaryTopicIds

    Write-Output "CREATED $createdPath"
}
catch {
    Write-Output "ERROR $($_.Exception.Message)"
    exit 1
}
