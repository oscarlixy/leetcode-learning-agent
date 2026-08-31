Set-StrictMode -Version Latest

$script:ApprovedRoadmapStages = @(
    'foundation',
    'linear-structures',
    'sorting-recursion-trees',
    'graph-composite-search'
)
$script:ApprovedRoadmapNodeIds = @(
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
$script:IsoTimestampPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+\-]\d{2}:\d{2})$'
$script:IsoDatePattern = '^\d{4}-\d{2}-\d{2}$'

function Read-JsonDocument {
    param([string]$Path)

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    } catch {
        throw "Failed to read JSON document [$Path]: $($_.Exception.Message)"
    }

    try {
        $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
        if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
            return $raw | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop
        }
        return $raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON document [$Path]: $($_.Exception.Message)"
    }
}

function Get-RoadmapNodeIds {
    param($Roadmap)

    Assert-RoadmapDocument $Roadmap
    return @($Roadmap.nodes | ForEach-Object { $_.id })
}

function Assert-ProfileDocument {
    param($Document)

    $allowed = @(
        'schema_version',
        'language',
        'language_standard',
        'objective',
        'session_minutes',
        'teaching_mode',
        'hint_policy',
        'problem_source_mode',
        'timezone'
    )
    Assert-ObjectDocument $Document 'profile document' $allowed
    Assert-ExactValue $Document 'schema_version' 1 'profile document'
    Assert-ExactValue $Document 'language' 'cpp' 'profile document'
    Assert-ExactValue $Document 'language_standard' 'c++20' 'profile document'
    Assert-ExactValue $Document 'objective' 'foundations' 'profile document'
    Assert-ExactValue $Document 'session_minutes' 40 'profile document'
    Assert-ExactValue $Document 'teaching_mode' 'socratic' 'profile document'
    Assert-ExactValue $Document 'hint_policy' 'progressive-five-level' 'profile document'
    Assert-ExactValue $Document 'problem_source_mode' 'hybrid' 'profile document'
    Assert-ExactValue $Document 'timezone' 'Asia/Hong_Kong' 'profile document'
}

function Assert-RoadmapDocument {
    param($Document)

    $allowed = @('schema_version', 'nodes')
    Assert-ObjectDocument $Document 'roadmap document' $allowed
    Assert-ExactValue $Document 'schema_version' 1 'roadmap document'

    if (-not ($Document.nodes -is [System.Array])) {
        throw 'roadmap document nodes must be an array.'
    }

    $nodes = @($Document.nodes)
    if ($nodes.Count -ne $script:ApprovedRoadmapNodeIds.Count) {
        throw "roadmap must contain exactly $($script:ApprovedRoadmapNodeIds.Count) nodes."
    }

    $states = @{}
    $nodeById = @{}
    for ($index = 0; $index -lt $nodes.Count; $index++) {
        $node = $nodes[$index]
        $nodeAllowed = @(
            'id',
            'title',
            'stage',
            'objectives',
            'completion_criteria',
            'prerequisites',
            'recommended_problems'
        )
        Assert-ObjectDocument $node 'roadmap node' $nodeAllowed
        Assert-NodeIdValue $node.id 'roadmap node id'
        $expectedNodeId = $script:ApprovedRoadmapNodeIds[$index]
        if ($node.id -ne $expectedNodeId) {
            throw "roadmap node order expected [$expectedNodeId] at index [$index] but found [$($node.id)]."
        }
        Assert-NonEmptyString $node.title 'roadmap node title'
        Assert-EnumValue $node.stage $script:ApprovedRoadmapStages 'roadmap node stage'
        Assert-StringArray $node.objectives 'roadmap node objectives' 1 $true
        Assert-StringArray $node.completion_criteria 'roadmap node completion_criteria' 1 $true
        Assert-StringArray $node.prerequisites 'roadmap node prerequisites' 0 $true
        Assert-StringArray $node.recommended_problems 'roadmap node recommended_problems' 1 $true

        foreach ($recommendedProblem in $node.recommended_problems) {
            if ($recommendedProblem -notmatch '^(?:local|[0-9]+):[a-z0-9]+(?:-[a-z0-9]+)*$') {
                throw "roadmap node [$($node.id)] recommended problem [$recommendedProblem] is invalid."
            }
        }

        if ($nodeById.ContainsKey($node.id)) {
            throw "roadmap node id [$($node.id)] is duplicated."
        }

        $nodeById[$node.id] = $node
        $states[$node.id] = 'unvisited'
    }

    foreach ($node in $nodes) {
        foreach ($prerequisiteId in $node.prerequisites) {
            Assert-NodeIdValue $prerequisiteId "roadmap prerequisite for [$($node.id)]"
            if (-not $nodeById.ContainsKey($prerequisiteId)) {
                throw "roadmap prerequisite [$prerequisiteId] is missing."
            }
        }
    }

    foreach ($nodeId in $nodeById.Keys) {
        Assert-NoRoadmapCycle $nodeId $nodeById $states
    }
}

function Assert-StateDocument {
    param(
        $Document,
        $Roadmap
    )

    $roadmapIds = Get-RoadmapNodeIds $Roadmap
    $roadmapIdSet = New-StringSet $roadmapIds

    $allowed = @('schema_version', 'current_topic_id', 'updated_at', 'topics')
    Assert-ObjectDocument $Document 'state document' $allowed
    Assert-ExactValue $Document 'schema_version' 1 'state document'
    Assert-NodeIdValue $Document.current_topic_id 'state current_topic_id'
    Assert-DateTimeOffsetString $Document.updated_at 'state updated_at'

    if (-not ($Document.topics -is [System.Management.Automation.PSCustomObject])) {
        throw 'state topics must be an object.'
    }

    $topicNames = @($Document.topics.PSObject.Properties.Name)
    foreach ($topicName in $topicNames) {
        if (-not $roadmapIdSet.Contains($topicName)) {
            throw "state topic [$topicName] does not exist in the roadmap."
        }
    }

    foreach ($roadmapId in $roadmapIds) {
        if ($topicNames -notcontains $roadmapId) {
            throw "state topic [$roadmapId] is missing."
        }
    }

    if (-not $roadmapIdSet.Contains($Document.current_topic_id)) {
        throw "state current_topic_id [$($Document.current_topic_id)] does not exist in the roadmap."
    }

    foreach ($topicName in $topicNames) {
        Assert-TopicState (Get-ObjectPropertyValue $Document.topics $topicName) $topicName
    }
}

function Assert-ActiveSessionDocument {
    param(
        $Document,
        $Roadmap,
        [string]$ProblemsRoot
    )

    $roadmapIds = Get-RoadmapNodeIds $Roadmap
    $roadmapIdSet = New-StringSet $roadmapIds
    $allowed = @(
        'schema_version',
        'active',
        'session_id',
        'started_at',
        'topic_id',
        'problem_slug',
        'phase',
        'hint_level',
        'last_updated_at'
    )

    Assert-ObjectDocument $Document 'active-session document' $allowed
    Assert-ExactValue $Document 'schema_version' 1 'active-session document'
    Assert-BooleanValue $Document.active 'active-session active'

    $sessionFields = @(
        'session_id',
        'started_at',
        'topic_id',
        'problem_slug',
        'phase',
        'hint_level',
        'last_updated_at'
    )

    if (-not $Document.active) {
        foreach ($fieldName in $sessionFields) {
            if ($null -ne $Document.$fieldName) {
                throw "active-session [$fieldName] must be null when active is false."
            }
        }
        return
    }

    Assert-NonEmptyString $Document.session_id 'active-session session_id'
    Assert-DateTimeOffsetString $Document.started_at 'active-session started_at'
    Assert-NodeIdValue $Document.topic_id 'active-session topic_id'
    if (-not $roadmapIdSet.Contains($Document.topic_id)) {
        throw "active-session topic_id [$($Document.topic_id)] does not exist in the roadmap."
    }

    Assert-EnumValue $Document.phase @('recall', 'concept', 'solve', 'review', 'complete') 'active-session phase'
    Assert-IntegerRangeValue $Document.hint_level 0 5 'active-session hint_level'
    Assert-DateTimeOffsetString $Document.last_updated_at 'active-session last_updated_at'

    if ($null -eq $Document.problem_slug) {
        return
    }

    Assert-NonEmptyString $Document.problem_slug 'active-session problem_slug'
    Assert-SlugValue $Document.problem_slug 'active-session problem_slug'

    $matchingWorkspaces = @(Get-MatchingProblemWorkspaces $ProblemsRoot $Document.problem_slug $Roadmap)
    if ($matchingWorkspaces.Count -eq 0) {
        throw "active-session problem_slug [$($Document.problem_slug)] matched no workspace."
    }
    if ($matchingWorkspaces.Count -gt 1) {
        throw "active-session problem_slug [$($Document.problem_slug)] matched multiple workspaces."
    }
}

function Assert-ProblemDocument {
    param(
        $Document,
        $Roadmap
    )

    $roadmapIds = Get-RoadmapNodeIds $Roadmap
    $roadmapIdSet = New-StringSet $roadmapIds
    $allowed = @(
        'schema_version',
        'source',
        'problem_id',
        'slug',
        'title',
        'url',
        'difficulty',
        'primary_topic_id',
        'secondary_topic_ids',
        'status',
        'attempt_count',
        'highest_hint_level_used',
        'created_at',
        'last_attempted_at'
    )

    Assert-ObjectDocument $Document 'problem document' $allowed
    Assert-ExactValue $Document 'schema_version' 1 'problem document'
    Assert-EnumValue $Document.source @('leetcode', 'local') 'problem source'
    Assert-ProblemIdValue $Document.problem_id
    Assert-SlugValue $Document.slug 'problem slug'
    Assert-NonEmptyString $Document.title 'problem title'
    Assert-UriValue $Document.url 'problem url'
    Assert-EnumValue $Document.difficulty @('easy', 'medium', 'hard', 'unknown') 'problem difficulty'
    Assert-NodeIdValue $Document.primary_topic_id 'problem primary_topic_id'
    if (-not $roadmapIdSet.Contains($Document.primary_topic_id)) {
        throw "problem primary_topic_id [$($Document.primary_topic_id)] does not exist in the roadmap."
    }

    Assert-StringArray $Document.secondary_topic_ids 'problem secondary_topic_ids' 0 $true
    if ($Document.secondary_topic_ids.Count -gt 2) {
        throw 'problem secondary_topic_ids may contain at most two entries.'
    }
    foreach ($secondaryTopicId in $Document.secondary_topic_ids) {
        Assert-NodeIdValue $secondaryTopicId 'problem secondary_topic_id'
        if (-not $roadmapIdSet.Contains($secondaryTopicId)) {
            throw "problem secondary_topic_id [$secondaryTopicId] does not exist in the roadmap."
        }
        if ($secondaryTopicId -eq $Document.primary_topic_id) {
            throw "problem secondary_topic_id [$secondaryTopicId] duplicates the primary topic."
        }
    }

    Assert-EnumValue $Document.status @('new', 'attempting', 'solved', 'review') 'problem status'
    Assert-NonNegativeIntegerValue $Document.attempt_count 'problem attempt_count'
    Assert-IntegerRangeValue $Document.highest_hint_level_used 0 5 'problem highest_hint_level_used'
    Assert-DateTimeOffsetString $Document.created_at 'problem created_at'
    Assert-NullableDateTimeOffsetString $Document.last_attempted_at 'problem last_attempted_at'
}

function Assert-ObjectDocument {
    param(
        $Document,
        [string]$Context,
        [string[]]$AllowedProperties
    )

    if (-not ($Document -is [System.Management.Automation.PSCustomObject])) {
        throw "$Context must be an object."
    }

    Assert-RequiredProperties $Document $AllowedProperties $Context
    Assert-NoUnexpectedProperties $Document $AllowedProperties $Context
}

function Assert-RequiredProperties {
    param(
        $Document,
        [string[]]$RequiredProperties,
        [string]$Context
    )

    $names = @($Document.PSObject.Properties.Name)
    foreach ($propertyName in $RequiredProperties) {
        if ($names -notcontains $propertyName) {
            throw "$Context is missing required property [$propertyName]."
        }
    }
}

function Assert-NoUnexpectedProperties {
    param(
        $Document,
        [string[]]$AllowedProperties,
        [string]$Context
    )

    foreach ($propertyName in $Document.PSObject.Properties.Name) {
        if ($AllowedProperties -notcontains $propertyName) {
            throw "$Context contains unexpected property [$propertyName]."
        }
    }
}

function Assert-ExactValue {
    param(
        $Document,
        [string]$PropertyName,
        $ExpectedValue,
        [string]$Context
    )

    if ($Document.$PropertyName -ne $ExpectedValue) {
        throw "$Context property [$PropertyName] must equal [$ExpectedValue]."
    }
}

function Assert-EnumValue {
    param(
        $Value,
        [string[]]$AllowedValues,
        [string]$Context
    )

    if (-not ($Value -is [string])) {
        throw "$Context must be a string."
    }
    if ($AllowedValues -notcontains $Value) {
        throw "$Context value [$Value] is invalid."
    }
}

function Assert-BooleanValue {
    param(
        $Value,
        [string]$Context
    )

    if (-not ($Value -is [bool])) {
        throw "$Context must be a boolean."
    }
}

function Assert-NonEmptyString {
    param(
        $Value,
        [string]$Context
    )

    if (-not ($Value -is [string])) {
        throw "$Context must be a string."
    }
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Context must not be empty."
    }
}

function Assert-StringArray {
    param(
        $Value,
        [string]$Context,
        [int]$MinimumCount,
        [bool]$RequireUnique
    )

    if (-not ($Value -is [System.Array])) {
        throw "$Context must be an array."
    }
    if ($Value.Count -lt $MinimumCount) {
        throw "$Context must contain at least $MinimumCount item(s)."
    }

    $seen = New-StringSet @()
    foreach ($item in $Value) {
        Assert-NonEmptyString $item $Context
        if ($RequireUnique) {
            if ($seen.Contains($item)) {
                throw "$Context contains a duplicate value [$item]."
            }
            [void]$seen.Add($item)
        }
    }
}

function Assert-IntegerRangeValue {
    param(
        $Value,
        [int]$Minimum,
        [int]$Maximum,
        [string]$Context
    )

    if (-not (Test-IsIntegerValue $Value)) {
        throw "$Context must be an integer."
    }
    if ($Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "$Context must be between $Minimum and $Maximum."
    }
}

function Assert-NonNegativeIntegerValue {
    param(
        $Value,
        [string]$Context
    )

    if (-not (Test-IsIntegerValue $Value)) {
        throw "$Context must be an integer."
    }
    if ($Value -lt 0) {
        throw "$Context must be non-negative."
    }
}

function Assert-DateTimeOffsetString {
    param(
        $Value,
        [string]$Context
    )

    if (-not ($Value -is [string])) {
        throw "$Context must be a string."
    }
    if ($Value -notmatch $script:IsoTimestampPattern) {
        throw "$Context must be an ISO 8601 datetime with timezone."
    }

    $parsedValue = [datetimeoffset]::MinValue
    $parsed = [datetimeoffset]::TryParse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsedValue
    )
    if (-not $parsed) {
        throw "$Context must be an ISO 8601 datetime with timezone."
    }
}

function Assert-NullableDateTimeOffsetString {
    param(
        $Value,
        [string]$Context
    )

    if ($null -eq $Value) {
        return
    }

    Assert-DateTimeOffsetString $Value $Context
}

function Assert-DateString {
    param(
        $Value,
        [string]$Context
    )

    if (-not ($Value -is [string])) {
        throw "$Context must be a string."
    }
    if ($Value -notmatch $script:IsoDatePattern) {
        throw "$Context must be a YYYY-MM-DD date."
    }

    $parsedValue = [datetime]::MinValue
    $parsed = [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedValue
    )
    if (-not $parsed) {
        throw "$Context must be a YYYY-MM-DD date."
    }
}

function Assert-NullableDateString {
    param(
        $Value,
        [string]$Context
    )

    if ($null -eq $Value) {
        return
    }

    Assert-DateString $Value $Context
}

function Assert-NodeIdValue {
    param(
        $Value,
        [string]$Context
    )

    Assert-NonEmptyString $Value $Context
    if ($Value -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "$Context value [$Value] is invalid."
    }
}

function Assert-SlugValue {
    param(
        $Value,
        [string]$Context
    )

    Assert-NodeIdValue $Value $Context
}

function Assert-ProblemIdValue {
    param($Value)

    if (Test-IsIntegerValue $Value) {
        if ($Value -lt 1) {
            throw 'problem_id must be positive.'
        }
        return
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            throw 'problem_id must not be empty.'
        }
        return
    }

    throw 'problem_id must be an integer or string.'
}

function Assert-UriValue {
    param(
        $Value,
        [string]$Context
    )

    Assert-NonEmptyString $Value $Context
    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        throw "$Context must be an absolute URI."
    }
}

function Assert-TopicState {
    param(
        $TopicState,
        [string]$TopicId
    )

    $allowed = @(
        'mastery',
        'status',
        'last_studied_at',
        'next_review_at',
        'sessions_completed',
        'best_independent_result',
        'highest_hint_level_used',
        'error_tags'
    )
    Assert-ObjectDocument $TopicState "state topic [$TopicId]" $allowed
    Assert-IntegerRangeValue $TopicState.mastery 0 4 "state topic [$TopicId] mastery"
    Assert-EnumValue $TopicState.status @('unseen', 'learning', 'review', 'mastered') "state topic [$TopicId] status"
    Assert-NullableDateTimeOffsetString $TopicState.last_studied_at "state topic [$TopicId] last_studied_at"
    Assert-NullableDateString $TopicState.next_review_at "state topic [$TopicId] next_review_at"
    Assert-NonNegativeIntegerValue $TopicState.sessions_completed "state topic [$TopicId] sessions_completed"
    Assert-BooleanValue $TopicState.best_independent_result "state topic [$TopicId] best_independent_result"
    Assert-IntegerRangeValue $TopicState.highest_hint_level_used 0 5 "state topic [$TopicId] highest_hint_level_used"
    Assert-StringArray $TopicState.error_tags "state topic [$TopicId] error_tags" 0 $true
}

function Assert-NoRoadmapCycle {
    param(
        [string]$NodeId,
        [hashtable]$NodeById,
        [hashtable]$States
    )

    $state = $States[$NodeId]
    if ($state -eq 'visited') {
        return
    }
    if ($state -eq 'visiting') {
        throw "roadmap cycle detected at node [$NodeId]."
    }

    $States[$NodeId] = 'visiting'
    foreach ($prerequisiteId in $NodeById[$NodeId].prerequisites) {
        Assert-NoRoadmapCycle $prerequisiteId $NodeById $States
    }
    $States[$NodeId] = 'visited'
}

function New-StringSet {
    param([string[]]$Values)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in $Values) {
        [void]$set.Add($value)
    }
    return ,$set
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$PropertyName
    )

    return $Object.PSObject.Properties[$PropertyName].Value
}

function Get-MatchingProblemWorkspaces {
    param(
        [string]$ProblemsRoot,
        [string]$ProblemSlug,
        $Roadmap
    )

    $problemsRootPath = [System.IO.Path]::GetFullPath($ProblemsRoot)
    if (-not (Test-Path -LiteralPath $problemsRootPath -PathType Container)) {
        return @()
    }

    $matches = [System.Collections.Generic.List[string]]::new()
    foreach ($child in Get-ChildItem -LiteralPath $problemsRootPath -Directory -ErrorAction Stop) {
        if ($child.Name -eq '_template') {
            continue
        }

        $metaPath = Join-Path $child.FullName 'meta.json'
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            continue
        }

        try {
            $metaDocument = Read-JsonDocument $metaPath
            Assert-ProblemDocument $metaDocument $Roadmap
        } catch {
            continue
        }

        if ($metaDocument.slug -ne $ProblemSlug) {
            continue
        }

        $expectedLeafName = "$($metaDocument.problem_id)-$($metaDocument.slug)"
        if ($child.Name -ne $expectedLeafName) {
            continue
        }

        [void]$matches.Add($child.FullName)
    }

    return $matches.ToArray()
}

function Test-IsIntegerValue {
    param($Value)

    return (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]
    )
}

function Get-RepositoryConsistencyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Resolve-ConsistencyPath -Path $RepoRoot -Label 'repository root'
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "Repository root [$resolvedRepoRoot] does not exist."
    }

    $ok = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    $roadmapResult = Test-ConsistencyDocument `
        -Path (Join-Path $resolvedRepoRoot 'curriculum/roadmap.json') `
        -Label 'curriculum/roadmap.json' `
        -Validator {
            param($Document)
            Assert-RoadmapDocument $Document
        } `
        -Ok $ok `
        -Errors $errors

    $profileResult = Test-ConsistencyDocument `
        -Path (Join-Path $resolvedRepoRoot 'learner/profile.json') `
        -Label 'learner/profile.json' `
        -Validator {
            param($Document)
            Assert-ProfileDocument $Document
        } `
        -Ok $ok `
        -Errors $errors

    if ($roadmapResult.IsValid) {
        [void](Test-ConsistencyDocument `
            -Path (Join-Path $resolvedRepoRoot 'learner/state.json') `
            -Label 'learner/state.json' `
            -Validator {
                param($Document)
                Assert-StateDocument $Document $roadmapResult.Document
            } `
            -Ok $ok `
            -Errors $errors)

        [void](Test-ConsistencyDocument `
            -Path (Join-Path $resolvedRepoRoot 'learner/state.backup.json') `
            -Label 'learner/state.backup.json' `
            -Validator {
                param($Document)
                Assert-StateDocument $Document $roadmapResult.Document
            } `
            -Ok $ok `
            -Errors $errors)

        [void](Test-ConsistencyDocument `
            -Path (Join-Path $resolvedRepoRoot 'learner/active-session.json') `
            -Label 'learner/active-session.json' `
            -Validator {
                param($Document)
                Assert-ActiveSessionDocument $Document $roadmapResult.Document (Join-Path $resolvedRepoRoot 'problems')
            } `
            -Ok $ok `
            -Errors $errors)

        Test-ProblemWorkspaceConsistency `
            -ProblemsRoot (Join-Path $resolvedRepoRoot 'problems') `
            -Roadmap $roadmapResult.Document `
            -Ok $ok `
            -Errors $errors
    } else {
        Add-ConsistencyError -Errors $errors -Message 'Dependent learner and problem workspace checks skipped because curriculum/roadmap.json is invalid.'
    }

    Test-VisualizationConsistency -RepoRoot $resolvedRepoRoot -Ok $ok -Errors $errors

    return [pscustomobject]@{
        Ok = $ok.ToArray()
        Errors = $errors.ToArray()
    }
}

function Test-ConsistencyDocument {
    param(
        [string]$Path,
        [string]$Label,
        [scriptblock]$Validator,
        [System.Collections.Generic.List[string]]$Ok,
        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $document = Read-JsonDocument $Path
        & $Validator $document
        [void]$Ok.Add($Label)
        return [pscustomobject]@{
            IsValid = $true
            Document = $document
        }
    } catch {
        Add-ConsistencyError -Errors $Errors -Message "${Label}: $($_.Exception.Message)"
        return [pscustomobject]@{
            IsValid = $false
            Document = $null
        }
    }
}

function Test-ProblemWorkspaceConsistency {
    param(
        [string]$ProblemsRoot,
        $Roadmap,
        [System.Collections.Generic.List[string]]$Ok,
        [System.Collections.Generic.List[string]]$Errors
    )

    $resolvedProblemsRoot = Resolve-ConsistencyPath -Path $ProblemsRoot -Label 'problems root'
    if (-not (Test-Path -LiteralPath $resolvedProblemsRoot -PathType Container)) {
        Add-ConsistencyError -Errors $Errors -Message "problems root [$resolvedProblemsRoot] does not exist."
        return
    }

    foreach ($workspace in Get-ChildItem -LiteralPath $resolvedProblemsRoot -Directory -ErrorAction Stop) {
        if ($workspace.Name -eq '_template') {
            continue
        }

        $metaPath = Join-Path $workspace.FullName 'meta.json'
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            Add-ConsistencyError -Errors $Errors -Message "problems/$($workspace.Name)/meta.json is missing."
            continue
        }

        try {
            $metaDocument = Read-JsonDocument $metaPath
            Assert-ProblemDocument $metaDocument $Roadmap

            $expectedWorkspaceName = "$($metaDocument.problem_id)-$($metaDocument.slug)"
            if ($workspace.Name -ne $expectedWorkspaceName) {
                throw "problem workspace directory [$($workspace.Name)] must match [$expectedWorkspaceName]."
            }

            $referencePath = Join-Path $workspace.FullName 'reference.cpp'
            if ((Test-Path -LiteralPath $referencePath -PathType Leaf) -and $metaDocument.highest_hint_level_used -ne 5) {
                throw "reference.cpp is only allowed when highest_hint_level_used equals 5."
            }

            [void]$Ok.Add("problems/$($workspace.Name)/meta.json")
        } catch {
            Add-ConsistencyError -Errors $Errors -Message "problems/$($workspace.Name)/meta.json: $($_.Exception.Message)"
        }
    }
}

function Test-VisualizationConsistency {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Ok,
        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        Import-Module (Join-Path $PSScriptRoot 'Visualization.psm1') -Force -ErrorAction Stop
        if (Visualization\Test-LearningPathVisualizationFresh -RepoRoot $RepoRoot) {
            [void]$Ok.Add('visualization/learning-path.html')
            return
        }

        Add-ConsistencyError -Errors $Errors -Message 'visualization/learning-path.html is missing or stale.'
    } catch {
        Add-ConsistencyError -Errors $Errors -Message "visualization/learning-path.html: $($_.Exception.Message)"
    }
}

function Add-ConsistencyError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )

    [void]$Errors.Add($Message)
}

function Resolve-ConsistencyPath {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label path must not be empty."
    }

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "$Label path [$Path] must not contain wildcard characters."
    }

    return [System.IO.Path]::GetFullPath($Path)
}

Export-ModuleMember -Function @(
    'Read-JsonDocument',
    'Assert-ProfileDocument',
    'Assert-RoadmapDocument',
    'Assert-StateDocument',
    'Assert-ActiveSessionDocument',
    'Assert-ProblemDocument',
    'Get-RoadmapNodeIds',
    'Get-RepositoryConsistencyReport'
)
