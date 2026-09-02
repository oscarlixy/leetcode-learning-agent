Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/Validation.psm1') -Force

function ConvertFrom-TestJson {
    param([string]$Json)

    $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
        return $Json | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop
    }

    return $Json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
}

function Copy-TestJsonValue {
    param($Value)

    return ConvertFrom-TestJson ($Value | ConvertTo-Json -Depth 100)
}

function Rename-TestJsonProperty {
    param(
        $Object,
        [string]$OldName,
        [string]$NewName
    )

    $property = @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $OldName })
    Assert-Equal 1 $property.Count "Fixture property [$OldName] is missing or ambiguous."
    $value = $property[0].Value
    $Object.PSObject.Properties.Remove($OldName)
    $Object.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($NewName, $value))
}

function New-ValidProblemDocument {
    return [pscustomobject]@{
        schema_version = 1
        source = 'leetcode'
        problem_id = 1
        slug = 'two-sum'
        title = 'Two Sum'
        url = 'https://leetcode.com/problems/two-sum/'
        difficulty = 'easy'
        primary_topic_id = 'hash-table'
        secondary_topic_ids = @('arrays-strings')
        status = 'new'
        attempt_count = 0
        highest_hint_level_used = 0
        created_at = '2026-08-31T00:00:00+08:00'
        last_attempted_at = $null
    }
}

$roadmap = Read-JsonDocument (Join-Path $RepoRoot 'curriculum/roadmap.json')
$profile = Read-JsonDocument (Join-Path $RepoRoot 'learner/profile.json')
$state = Read-JsonDocument (Join-Path $RepoRoot 'learner/state.json')
$activeSession = Read-JsonDocument (Join-Path $RepoRoot 'learner/active-session.json')

# Break caught: a wrong-case roadmap property used to satisfy the required-property lookup.
$wrongCaseRoadmapProperty = Copy-TestJsonValue $roadmap
Rename-TestJsonProperty $wrongCaseRoadmapProperty 'schema_version' 'Schema_Version'
Assert-Throws { Assert-RoadmapDocument $wrongCaseRoadmapProperty } 'schema_version|unexpected|required'

# Break caught: numeric constants encoded as strings used to compare equal through coercion.
$stringProfileSchemaVersion = Copy-TestJsonValue $profile
$stringProfileSchemaVersion.schema_version = '1'
Assert-Throws { Assert-ProfileDocument $stringProfileSchemaVersion } 'schema_version|integer'

$stringSessionMinutes = Copy-TestJsonValue $profile
$stringSessionMinutes.session_minutes = '40'
Assert-Throws { Assert-ProfileDocument $stringSessionMinutes } 'session_minutes|integer'

# Break caught: exact string constants and enums used to compare case-insensitively.
$wrongCaseProfileConstant = Copy-TestJsonValue $profile
$wrongCaseProfileConstant.language = 'CPP'
Assert-Throws { Assert-ProfileDocument $wrongCaseProfileConstant } 'language'

$wrongCaseProfileProperty = Copy-TestJsonValue $profile
Rename-TestJsonProperty $wrongCaseProfileProperty 'session_minutes' 'Session_Minutes'
Assert-Throws { Assert-ProfileDocument $wrongCaseProfileProperty } 'session_minutes|unexpected|required'

$wrongCaseRoadmapStage = Copy-TestJsonValue $roadmap
$wrongCaseRoadmapStage.nodes[0].stage = 'Foundation'
Assert-Throws { Assert-RoadmapDocument $wrongCaseRoadmapStage } 'stage'

$wrongCaseStateProperty = Copy-TestJsonValue $state
Rename-TestJsonProperty $wrongCaseStateProperty 'current_topic_id' 'Current_Topic_Id'
Assert-Throws { Assert-StateDocument $wrongCaseStateProperty $roadmap } 'current_topic_id|unexpected|required'

$wrongCaseStateStatus = Copy-TestJsonValue $state
$wrongCaseStateStatus.topics.diagnosis.status = 'Learning'
Assert-Throws { Assert-StateDocument $wrongCaseStateStatus $roadmap } 'status'

$stringStateInteger = Copy-TestJsonValue $state
$stringStateInteger.topics.diagnosis.mastery = '0'
Assert-Throws { Assert-StateDocument $stringStateInteger $roadmap } 'mastery|integer'

$activeSolve = Copy-TestJsonValue $activeSession
$activeSolve.active = $true
$activeSolve.session_id = 'strict-validation'
$activeSolve.started_at = '2026-08-31T00:00:00+08:00'
$activeSolve.topic_id = 'diagnosis'
$activeSolve.problem_slug = $null
$activeSolve.phase = 'Solve'
$activeSolve.hint_level = 0
$activeSolve.last_updated_at = '2026-08-31T00:05:00+08:00'
Assert-Throws { Assert-ActiveSessionDocument $activeSolve $roadmap (Join-Path $RepoRoot 'problems') } 'phase'

$stringActiveBoolean = Copy-TestJsonValue $activeSession
$stringActiveBoolean.active = 'false'
Assert-Throws { Assert-ActiveSessionDocument $stringActiveBoolean $roadmap (Join-Path $RepoRoot 'problems') } 'active|boolean'

$wrongCaseActiveProperty = Copy-TestJsonValue $activeSession
Rename-TestJsonProperty $wrongCaseActiveProperty 'active' 'Active'
Assert-Throws { Assert-ActiveSessionDocument $wrongCaseActiveProperty $roadmap (Join-Path $RepoRoot 'problems') } 'active|unexpected|required'

$problem = New-ValidProblemDocument
Assert-ProblemDocument $problem $roadmap

$wrongCaseProblemProperty = Copy-TestJsonValue $problem
Rename-TestJsonProperty $wrongCaseProblemProperty 'slug' 'Slug'
Assert-Throws { Assert-ProblemDocument $wrongCaseProblemProperty $roadmap } 'slug|unexpected|required'

foreach ($mutation in @(
    @{ Property = 'slug'; Value = 'Two-Sum'; Pattern = 'slug' },
    @{ Property = 'difficulty'; Value = 'Easy'; Pattern = 'difficulty' },
    @{ Property = 'status'; Value = 'New'; Pattern = 'status' },
    @{ Property = 'attempt_count'; Value = '0'; Pattern = 'attempt_count|integer' },
    @{ Property = 'schema_version'; Value = '1'; Pattern = 'schema_version|integer' }
)) {
    $invalidProblem = Copy-TestJsonValue $problem
    $invalidProblem.($mutation.Property) = $mutation.Value
    Assert-Throws { Assert-ProblemDocument $invalidProblem $roadmap } $mutation.Pattern
}

# Valid documents remain accepted after strictness is applied.
Assert-ProfileDocument $profile
Assert-RoadmapDocument $roadmap
Assert-StateDocument $state $roadmap
Assert-ActiveSessionDocument $activeSession $roadmap (Join-Path $RepoRoot 'problems')
Assert-ProblemDocument $problem $roadmap
