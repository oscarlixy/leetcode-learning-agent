Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force

$roadmap = Read-JsonDocument "$RepoRoot/curriculum/roadmap.json"
$profile = Read-JsonDocument "$RepoRoot/learner/profile.json"
$state = Read-JsonDocument "$RepoRoot/learner/state.json"
$active = Read-JsonDocument "$RepoRoot/learner/active-session.json"

Assert-ProfileDocument $profile
Assert-RoadmapDocument $roadmap
Assert-StateDocument $state $roadmap
Assert-ActiveSessionDocument $active $roadmap "$RepoRoot/problems"
Assert-Equal 15 $roadmap.nodes.Count 'Roadmap node count mismatch.'
Assert-Equal 'diagnosis' $state.current_topic_id 'Initial topic must be diagnosis.'
$stages = @($roadmap.nodes | ForEach-Object { $_.stage } | Sort-Object -Unique)
Assert-Equal 4 $stages.Count 'Roadmap stage count mismatch.'
Assert-Equal 'foundation,graph-composite-search,linear-structures,sorting-recursion-trees' ($stages -join ',') 'Roadmap stages must match the approved visual stages.'

$badState = $state | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$badState.topics.diagnosis.mastery = 5
Assert-Throws { Assert-StateDocument $badState $roadmap } 'mastery'

$badStage = $roadmap | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$badStage.nodes[0].stage = 'invalid-stage'
Assert-Throws { Assert-RoadmapDocument $badStage } 'stage'

$cyclic = $roadmap | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$cyclic.nodes[0].prerequisites = @('dynamic-programming')
Assert-Throws { Assert-RoadmapDocument $cyclic } 'cycle'
