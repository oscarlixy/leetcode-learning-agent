Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding utf8
$gitignore = Get-Content -LiteralPath (Join-Path $RepoRoot '.gitignore') -Raw -Encoding utf8

$l2Line = [regex]::Match($readme, '(?im)^- `L2`[^\r\n]*$').Value
$l3Line = [regex]::Match($readme, '(?im)^- `L3`[^\r\n]*$').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($l2Line)) 'README L2 description is missing.'
Assert-True (-not [string]::IsNullOrWhiteSpace($l3Line)) 'README L3 description is missing.'

# Break caught: README shifted L3 invariant/state help down into L2 and overstated L3.
Assert-True (-not ($l2Line -match '(?i)(give|provide|指出|给出).{0,30}(invariant|state definition|core data structure|不变量|状态定义|核心数据结构)')) 'README L2 must not promise an invariant, state definition, or core data structure.'
Assert-True ($l2Line -match '(?i)(must not|does not|不给).{0,40}(state|data structure|状态|数据结构)') 'README L2 must explicitly retain the key-state/core-data-structure boundary.'
Assert-True ($l3Line -match '(?i)invariant|state|data structure|不变量|状态|数据结构') 'README L3 must own the invariant, state definition, or core data structure.'

Assert-True ($gitignore -match '(?m)^\*\.candidate\.json\s*$') '.gitignore must ignore normal candidate JSON artifacts.'
Assert-True ($gitignore -match '(?m)(?:^|/)\.build/\s*$|(?m)^\*\*/\.build/\s*$|(?m)^problems/\*/\.build/\s*$') '.gitignore must ignore per-problem .build scratch directories.'
