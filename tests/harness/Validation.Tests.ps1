Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force

$ExpectedRoadmapNodeIds = @(
    'diagnosis',
    'complexity',
    'cpp-toolbox',
    'arrays-strings',
    'linked-list',
    'stack-queue',
    'hash-table',
    'sorting-binary-search',
    'recursion-backtracking',
    'binary-tree',
    'heap-priority-queue',
    'bfs-dfs',
    'graph',
    'greedy',
    'dynamic-programming'
)
$ExpectedRoadmapStages = @(
    'foundation',
    'graph-composite-search',
    'linear-structures',
    'sorting-recursion-trees'
)
$ExpectedTimestampPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+\-]\d{2}:\d{2})$'
$ExpectedDatePattern = '^\d{4}-\d{2}-\d{2}$'

function ConvertFrom-JsonStrict {
    param([string]$Json)

    $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
        return $Json | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop
    }

    return $Json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
}

function Copy-JsonValue {
    param($Value)

    return ConvertFrom-JsonStrict ($Value | ConvertTo-Json -Depth 100)
}

function Get-JsonPropertyValue {
    param(
        $Object,
        [string]$PropertyName
    )

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        throw "Missing JSON property [$PropertyName]."
    }
    return $property.Value
}

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-validation-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-ProblemWorkspaceFixture {
    param(
        [string]$ProblemsRoot,
        [string]$DirectoryName,
        [object]$ProblemId,
        [string]$MetaSlug,
        [string]$RawMetaJson,
        [switch]$SkipMeta
    )

    $workspacePath = Join-Path $ProblemsRoot $DirectoryName
    New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

    if ($SkipMeta) {
        return
    }

    if ($PSBoundParameters.ContainsKey('RawMetaJson')) {
        Set-Content -LiteralPath (Join-Path $workspacePath 'meta.json') -Value $RawMetaJson -Encoding utf8
        return
    }

    $meta = [pscustomobject]@{
        schema_version = 1
        source = 'leetcode'
        problem_id = $ProblemId
        slug = $MetaSlug
        title = 'Fixture Problem'
        url = "https://leetcode.com/problems/$MetaSlug/"
        difficulty = 'easy'
        primary_topic_id = 'hash-table'
        secondary_topic_ids = @()
        status = 'new'
        attempt_count = 0
        highest_hint_level_used = 0
        created_at = '2026-08-31T00:00:00+08:00'
        last_attempted_at = $null
    }
    $meta | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $workspacePath 'meta.json') -Encoding utf8
}

$roadmap = Read-JsonDocument "$RepoRoot/curriculum/roadmap.json"
$profile = Read-JsonDocument "$RepoRoot/learner/profile.json"
$state = Read-JsonDocument "$RepoRoot/learner/state.json"
$active = Read-JsonDocument "$RepoRoot/learner/active-session.json"
$roadmapSchema = Read-JsonDocument "$RepoRoot/schemas/roadmap.schema.json"
$stateSchema = Read-JsonDocument "$RepoRoot/schemas/state.schema.json"
$activeSessionSchema = Read-JsonDocument "$RepoRoot/schemas/active-session.schema.json"
$problemSchema = Read-JsonDocument "$RepoRoot/schemas/problem.schema.json"

Assert-ProfileDocument $profile
Assert-RoadmapDocument $roadmap
Assert-StateDocument $state $roadmap
Assert-ActiveSessionDocument $active $roadmap "$RepoRoot/problems"

$roadmapNodesSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $roadmapSchema 'properties') 'nodes'
$roadmapPrefixItems = @(Get-JsonPropertyValue $roadmapNodesSchema 'prefixItems')
$roadmapSchemaIds = @(
    $roadmapPrefixItems | ForEach-Object {
        Get-JsonPropertyValue (Get-JsonPropertyValue (Get-JsonPropertyValue $_ 'allOf')[1] 'properties') 'id' |
            ForEach-Object { Get-JsonPropertyValue $_ 'const' }
    }
)
Assert-Equal 15 (Get-JsonPropertyValue $roadmapNodesSchema 'minItems') 'Roadmap schema minItems mismatch.'
Assert-Equal 15 (Get-JsonPropertyValue $roadmapNodesSchema 'maxItems') 'Roadmap schema maxItems mismatch.'
Assert-Equal $false (Get-JsonPropertyValue $roadmapNodesSchema 'items') 'Roadmap schema must reject extra items.'
Assert-Equal 15 $roadmapPrefixItems.Count 'Roadmap schema prefixItems count mismatch.'
Assert-Equal ($ExpectedRoadmapNodeIds -join ',') ($roadmapSchemaIds -join ',') 'Roadmap schema node ID order mismatch.'

$stateUpdatedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $stateSchema 'properties') 'updated_at'
$stateTopicSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $stateSchema '$defs') 'topicState'
$stateLastStudiedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $stateTopicSchema 'properties') 'last_studied_at'
$stateNextReviewAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $stateTopicSchema 'properties') 'next_review_at'
$activeStartedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $activeSessionSchema 'properties') 'started_at'
$activeLastUpdatedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $activeSessionSchema 'properties') 'last_updated_at'
$problemCreatedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $problemSchema 'properties') 'created_at'
$problemLastAttemptedAtSchema = Get-JsonPropertyValue (Get-JsonPropertyValue $problemSchema 'properties') 'last_attempted_at'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue $stateUpdatedAtSchema 'pattern') 'State schema updated_at pattern mismatch.'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue (Get-JsonPropertyValue $stateLastStudiedAtSchema 'anyOf')[0] 'pattern') 'State schema last_studied_at pattern mismatch.'
Assert-Equal $ExpectedDatePattern (Get-JsonPropertyValue (Get-JsonPropertyValue $stateNextReviewAtSchema 'anyOf')[0] 'pattern') 'State schema next_review_at pattern mismatch.'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue (Get-JsonPropertyValue $activeStartedAtSchema 'anyOf')[0] 'pattern') 'Active-session schema started_at pattern mismatch.'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue (Get-JsonPropertyValue $activeLastUpdatedAtSchema 'anyOf')[0] 'pattern') 'Active-session schema last_updated_at pattern mismatch.'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue $problemCreatedAtSchema 'pattern') 'Problem schema created_at pattern mismatch.'
Assert-Equal $ExpectedTimestampPattern (Get-JsonPropertyValue (Get-JsonPropertyValue $problemLastAttemptedAtSchema 'anyOf')[0] 'pattern') 'Problem schema last_attempted_at pattern mismatch.'

Assert-Equal 15 $roadmap.nodes.Count 'Roadmap node count mismatch.'
Assert-Equal ($ExpectedRoadmapNodeIds -join ',') (@($roadmap.nodes | ForEach-Object { $_.id }) -join ',') 'Roadmap node ID order mismatch.'
Assert-Equal 'diagnosis' $state.current_topic_id 'Initial topic must be diagnosis.'
$stages = @($roadmap.nodes | ForEach-Object { $_.stage } | Sort-Object -Unique)
Assert-Equal 4 $stages.Count 'Roadmap stage count mismatch.'
Assert-Equal ($ExpectedRoadmapStages -join ',') ($stages -join ',') 'Roadmap stages must match the approved visual stages.'

$badState = Copy-JsonValue $state
$badState.topics.diagnosis.mastery = 5
Assert-Throws { Assert-StateDocument $badState $roadmap } 'mastery'

$reorderedRoadmap = Copy-JsonValue $roadmap
$swap = $reorderedRoadmap.nodes[0]
$reorderedRoadmap.nodes[0] = $reorderedRoadmap.nodes[1]
$reorderedRoadmap.nodes[1] = $swap
Assert-Throws { Assert-RoadmapDocument $reorderedRoadmap } 'order|expected'

$substitutedRoadmap = Copy-JsonValue $roadmap
$substitutedRoadmap.nodes[14].id = 'dynamic-programming-2'
Assert-Throws { Assert-RoadmapDocument $substitutedRoadmap } 'order|expected'

$badStage = Copy-JsonValue $roadmap
$badStage.nodes[0].stage = 'invalid-stage'
Assert-Throws { Assert-RoadmapDocument $badStage } 'stage'

$offsetlessTimestampState = Copy-JsonValue $state
$offsetlessTimestampState.updated_at = '2026-08-31T00:00:00'
Assert-Throws { Assert-StateDocument $offsetlessTimestampState $roadmap } 'ISO 8601|timezone'

$nonIsoTimestampState = Copy-JsonValue $state
$nonIsoTimestampState.updated_at = '08/31/2026 00:00:00 +08:00'
Assert-Throws { Assert-StateDocument $nonIsoTimestampState $roadmap } 'ISO 8601|timezone'

$dateTimeObjectTimestampState = Copy-JsonValue $state
$dateTimeObjectTimestampState.updated_at = [datetime]::Parse('2026-08-31T00:00:00')
Assert-Throws { Assert-StateDocument $dateTimeObjectTimestampState $roadmap } 'string|ISO 8601'

$invalidCalendarTimestampState = Copy-JsonValue $state
$invalidCalendarTimestampState.updated_at = '2026-02-30T00:00:00+08:00'
Assert-Throws { Assert-StateDocument $invalidCalendarTimestampState $roadmap } 'ISO 8601|timezone'

$invalidCalendarDateState = Copy-JsonValue $state
$invalidCalendarDateState.topics.diagnosis.next_review_at = '2026-02-30'
Assert-Throws { Assert-StateDocument $invalidCalendarDateState $roadmap } 'YYYY-MM-DD'

$dateTimeObjectDateState = Copy-JsonValue $state
$dateTimeObjectDateState.topics.diagnosis.next_review_at = [datetime]::Parse('2026-08-31')
Assert-Throws { Assert-StateDocument $dateTimeObjectDateState $roadmap } 'string|YYYY-MM-DD'

$cyclic = Copy-JsonValue $roadmap
$cyclic.nodes[0].prerequisites = @('dynamic-programming')
Assert-Throws { Assert-RoadmapDocument $cyclic } 'cycle'

$tempRoot = New-TestDirectory
try {
    $activeSolve = [pscustomobject]@{
        schema_version = 1
        active = $true
        session_id = 'session-1'
        started_at = '2026-08-31T00:00:00+08:00'
        topic_id = 'hash-table'
        problem_slug = 'two-sum'
        phase = 'solve'
        hint_level = 0
        last_updated_at = '2026-08-31T00:10:00+08:00'
    }

    $singleValidWithMalformedSiblingsRoot = Join-Path $tempRoot 'single-valid-with-malformed-siblings'
    New-Item -ItemType Directory -Path $singleValidWithMalformedSiblingsRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $singleValidWithMalformedSiblingsRoot '1-two-sum' 1 'two-sum'
    New-ProblemWorkspaceFixture $singleValidWithMalformedSiblingsRoot 'wrong-two-sum' 1 'two-sum' -SkipMeta
    New-ProblemWorkspaceFixture $singleValidWithMalformedSiblingsRoot '3-two-sum' 3 'two-sum' -RawMetaJson '{ invalid json'
    Assert-ActiveSessionDocument $activeSolve $roadmap $singleValidWithMalformedSiblingsRoot

    $onlyMalformedExactRoot = Join-Path $tempRoot 'only-malformed-exact'
    New-Item -ItemType Directory -Path $onlyMalformedExactRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $onlyMalformedExactRoot '1-two-sum' 1 'two-sum' -SkipMeta
    Assert-Throws { Assert-ActiveSessionDocument $activeSolve $roadmap $onlyMalformedExactRoot } 'problem_slug'

    $ambiguousProblemsRoot = Join-Path $tempRoot 'ambiguous-problems'
    New-Item -ItemType Directory -Path $ambiguousProblemsRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $ambiguousProblemsRoot '1-two-sum' 1 'two-sum'
    New-ProblemWorkspaceFixture $ambiguousProblemsRoot '2-two-sum' 2 'two-sum'
    Assert-Throws { Assert-ActiveSessionDocument $activeSolve $roadmap $ambiguousProblemsRoot } 'problem_slug'

    $mismatchedDirectoryMetadataRoot = Join-Path $tempRoot 'mismatched-directory-metadata'
    New-Item -ItemType Directory -Path $mismatchedDirectoryMetadataRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $mismatchedDirectoryMetadataRoot 'wrong-two-sum' 1 'two-sum'
    Assert-Throws { Assert-ActiveSessionDocument $activeSolve $roadmap $mismatchedDirectoryMetadataRoot } 'problem_slug'

    $mismatchedDirectoryMetadataIgnoredRoot = Join-Path $tempRoot 'mismatched-directory-metadata-ignored'
    New-Item -ItemType Directory -Path $mismatchedDirectoryMetadataIgnoredRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $mismatchedDirectoryMetadataIgnoredRoot '1-two-sum' 1 'two-sum'
    New-ProblemWorkspaceFixture $mismatchedDirectoryMetadataIgnoredRoot 'wrong-two-sum' 1 'two-sum'
    Assert-ActiveSessionDocument $activeSolve $roadmap $mismatchedDirectoryMetadataIgnoredRoot

    $missingProblem = Copy-JsonValue $activeSolve
    $missingProblem.problem_slug = 'not-found'
    Assert-Throws { Assert-ActiveSessionDocument $missingProblem $roadmap $singleValidWithMalformedSiblingsRoot } 'problem_slug'

    $unrelatedMalformedProblemsRoot = Join-Path $tempRoot 'unrelated-malformed-problems'
    New-Item -ItemType Directory -Path $unrelatedMalformedProblemsRoot -Force | Out-Null
    New-ProblemWorkspaceFixture $unrelatedMalformedProblemsRoot '1-two-sum' 1 'two-sum'
    New-ProblemWorkspaceFixture $unrelatedMalformedProblemsRoot 'broken-problem' 99 'broken-problem' -RawMetaJson '{ invalid json'
    Assert-ActiveSessionDocument $activeSolve $roadmap $unrelatedMalformedProblemsRoot
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
