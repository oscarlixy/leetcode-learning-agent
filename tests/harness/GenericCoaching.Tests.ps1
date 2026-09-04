Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$sessionProtocol = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/session-protocol.md') -Raw -Encoding utf8

# Break caught: generic coaching used to run Two Sum regardless of the active session.
Assert-True (-not ($sessionProtocol -match '(?i)tools/test-cpp\.ps1\s+-ProblemPath\s+problems/1-two-sum')) 'Generic solve guidance must not target the Two Sum workspace.'
Assert-True ($sessionProtocol -match '(?i)active-session(?:\.json)?[^\r\n]*problem_slug|active-session\.problem_slug') 'Solve guidance must derive the problem slug from the validated active session.'
Assert-True ($sessionProtocol -match '(?i)meta\.json[^\r\n]*(identity|workspace)|workspace[^\r\n]*meta\.json') 'Solve guidance must validate problem metadata against workspace identity.'
Assert-True ($sessionProtocol -match [regex]::Escape('tools/test-cpp.ps1 -ProblemPath $ProblemPath')) 'Solve guidance must invoke the resolved problem path variable.'
