Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$schedulingModulePath = Join-Path $RepoRoot 'tools/lib/Scheduling.psm1'

# Break caught: scheduling had no executable seam that read the learner timezone.
Assert-True (Test-Path -LiteralPath $schedulingModulePath -PathType Leaf) 'Scheduling.psm1 is required for learner-timezone date derivation.'
Import-Module $schedulingModulePath -Force

$profilePath = Join-Path $RepoRoot 'learner/profile.json'
$utcHongKongBoundary = [datetimeoffset]::Parse('2026-08-31T16:30:00Z', [System.Globalization.CultureInfo]::InvariantCulture)
$beforeUtcHongKongBoundary = [datetimeoffset]::Parse('2026-08-31T15:30:00Z', [System.Globalization.CultureInfo]::InvariantCulture)

# Break caught: UTC/host-local dates used to produce August 31 after Hong Kong midnight.
Assert-Equal '2026-09-01' (Get-LearnerToday -ProfilePath $profilePath -Instant $utcHongKongBoundary) 'Hong Kong today must cross the date boundary at UTC+08:00.'
Assert-Equal '2026-08-31' (Get-LearnerToday -ProfilePath $profilePath -Instant $beforeUtcHongKongBoundary) 'Hong Kong today must remain August 31 before local midnight.'
Assert-Equal '2026-09-04' (Get-LearnerReviewDate -ProfilePath $profilePath -Days 3 -Instant $utcHongKongBoundary) 'Review date must add days to the learner-local calendar date.'
Assert-True ((Get-LearnerReviewDate -ProfilePath $profilePath -Days 30 -Instant $utcHongKongBoundary) -cmatch '^\d{4}-\d{2}-\d{2}$') 'Review dates must use exact YYYY-MM-DD form.'

$sessionProtocol = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/session-protocol.md') -Raw -Encoding utf8
$stateModel = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/state-model.md') -Raw -Encoding utf8
$combinedInstructions = $sessionProtocol + [Environment]::NewLine + $stateModel
Assert-True ($combinedInstructions -match '(?i)learner/profile\.json.{0,100}timezone|timezone.{0,100}learner/profile\.json') 'Coaching must read timezone from learner/profile.json.'
Assert-True ($combinedInstructions -match '(?i)(never|must not|do not).{0,120}(host.local|UTC).{0,100}(date|today)') 'Coaching must explicitly forbid host-local or UTC calendar dates.'
Assert-True ($combinedInstructions -match 'Get-LearnerToday') 'Coaching must use the tested learner-date helper for today.'
Assert-True ($combinedInstructions -match 'Get-LearnerReviewDate') 'Coaching must use the tested learner-date helper for review dates.'
