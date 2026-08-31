Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$validationModule = Import-Module "$RepoRoot/tools/lib/Validation.psm1" -Force -PassThru
Import-Module "$RepoRoot/tools/lib/Visualization.psm1" -Force
$ReadJsonDocument = $validationModule.ExportedFunctions['Read-JsonDocument']

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-visualization-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Copy-VisualizationFixture {
    param([string]$DestinationRoot)

    foreach ($directory in @('curriculum', 'learner', 'visualization')) {
        New-Item -ItemType Directory -Path (Join-Path $DestinationRoot $directory) -Force | Out-Null
    }

    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $DestinationRoot 'curriculum/roadmap.json')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/state.json') -Destination (Join-Path $DestinationRoot 'learner/state.json')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'visualization/learning-path.template.html') -Destination (Join-Path $DestinationRoot 'visualization/learning-path.template.html')
}

$testRoot = New-TestDirectory
try {
    Copy-VisualizationFixture -DestinationRoot $testRoot

    $output = Update-LearningPathVisualization -RepoRoot $testRoot
    Assert-True (Test-Path -LiteralPath $output -PathType Leaf) 'Visualization was not generated.'
    Assert-True (Test-LearningPathVisualizationFresh -RepoRoot $testRoot) 'Fresh visualization reported stale.'

    $html = Get-Content -LiteralPath $output -Raw -Encoding utf8
    Assert-True ($html -match 'data-input-hash="[a-f0-9]{64}"') 'Input hash is missing.'
    Assert-True ($html -match 'dynamic-programming') 'Roadmap nodes were not embedded.'
    Assert-True ($html -match '"roadmap"') 'Embedded roadmap root is missing.'
    Assert-True ($html -match '"state"') 'Embedded state root is missing.'

    $state = & $ReadJsonDocument (Join-Path $testRoot 'learner/state.json')
    $state.topics.diagnosis.mastery = 1
    $state | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $testRoot 'learner/state.json') -Encoding utf8
    Assert-True (-not (Test-LearningPathVisualizationFresh -RepoRoot $testRoot)) 'Changed state was not detected.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$escapingRoot = New-TestDirectory
try {
    Copy-VisualizationFixture -DestinationRoot $escapingRoot

    $roadmap = & $ReadJsonDocument (Join-Path $escapingRoot 'curriculum/roadmap.json')
    $roadmap.nodes[0].title = "Unsafe <tag> & line separator $([char]0x2028)$([char]0x2029)"
    $roadmap | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $escapingRoot 'curriculum/roadmap.json') -Encoding utf8

    $html = Get-Content -LiteralPath (Update-LearningPathVisualization -RepoRoot $escapingRoot) -Raw -Encoding utf8
    Assert-True ($html -match '\\u003c') 'Embedded JSON did not escape <.'
    Assert-True ($html -match '\\u003e') 'Embedded JSON did not escape >.'
    Assert-True ($html -match '\\u0026') 'Embedded JSON did not escape &.'
    Assert-True ($html -match '\\u2028') 'Embedded JSON did not escape U+2028.'
    Assert-True ($html -match '\\u2029') 'Embedded JSON did not escape U+2029.'
}
finally {
    if (Test-Path -LiteralPath $escapingRoot) {
        Remove-Item -LiteralPath $escapingRoot -Recurse -Force
    }
}

$missingMarkerRoot = New-TestDirectory
try {
    Copy-VisualizationFixture -DestinationRoot $missingMarkerRoot
    Set-Content -LiteralPath (Join-Path $missingMarkerRoot 'visualization/learning-path.template.html') -Value '<main>__LEARNING_PATH_DATA_JSON__</main>' -Encoding utf8
    Assert-Throws { Update-LearningPathVisualization -RepoRoot $missingMarkerRoot } 'missing|hash'
}
finally {
    if (Test-Path -LiteralPath $missingMarkerRoot) {
        Remove-Item -LiteralPath $missingMarkerRoot -Recurse -Force
    }
}

$duplicateMarkerRoot = New-TestDirectory
try {
    Copy-VisualizationFixture -DestinationRoot $duplicateMarkerRoot
    $duplicateTemplate = @'
<main data-input-hash="__LEARNING_PATH_INPUT_HASH__">
<script type="application/json">__LEARNING_PATH_DATA_JSON__</script>
<span>__LEARNING_PATH_DATA_JSON__</span>
</main>
'@
    Set-Content -LiteralPath (Join-Path $duplicateMarkerRoot 'visualization/learning-path.template.html') -Value $duplicateTemplate -Encoding utf8
    Assert-Throws { Update-LearningPathVisualization -RepoRoot $duplicateMarkerRoot } 'appears more than once|duplicate'
}
finally {
    if (Test-Path -LiteralPath $duplicateMarkerRoot) {
        Remove-Item -LiteralPath $duplicateMarkerRoot -Recurse -Force
    }
}
