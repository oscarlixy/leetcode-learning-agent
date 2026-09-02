[CmdletBinding()]
param()

Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $repoRoot 'tools/lib/Visualization.psm1') -Force

[void](Update-LearningPathVisualization -RepoRoot $repoRoot)
Write-Output 'UPDATED visualization/learning-path.html'
