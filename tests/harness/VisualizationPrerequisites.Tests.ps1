Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/Visualization.psm1') -Force

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-visualization-prerequisite-tests-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
    foreach ($directory in @('curriculum', 'learner', 'visualization')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'curriculum/roadmap.json') -Destination (Join-Path $fixtureRoot 'curriculum/roadmap.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'learner/state.json') -Destination (Join-Path $fixtureRoot 'learner/state.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'visualization/learning-path.template.html') -Destination (Join-Path $fixtureRoot 'visualization/learning-path.template.html') -Force

    $outputPath = Update-LearningPathVisualization -RepoRoot $fixtureRoot
    $html = Get-Content -LiteralPath $outputPath -Raw -Encoding utf8

    # Break caught: prerequisites existed in JSON but were absent from node details.
    Assert-True ($html -match '<section\s+aria-labelledby="detail-prerequisites-title">') 'Prerequisites need an accessible labelled detail section.'
    Assert-True ($html -match '<h3\s+id="detail-prerequisites-title">Prerequisites</h3>') 'Prerequisites detail heading is missing.'
    Assert-True ($html -match '<ul\s+id="detail-prerequisites"></ul>') 'Prerequisites detail list is missing.'
    Assert-True ($html -match "const detailPrerequisites = document\.getElementById\('detail-prerequisites'\)") 'Prerequisites list must be connected to the renderer.'
    Assert-True ($html -match 'node\.prerequisites\.map') 'Selected-node rendering must derive prerequisite relationships from roadmap JSON.'
    Assert-True ($html -match 'appendList\(detailPrerequisites,\s*prerequisiteLabels\.length') 'Selected-node rendering must populate the prerequisite list.'
    Assert-True ($html -match "prerequisiteLabels\.length\s*>\s*0\s*\?\s*prerequisiteLabels\s*:\s*\['None'\]") 'Root nodes must retain a readable no-prerequisites fallback.'
    Assert-True (-not ($html -match '\.innerHTML\s*=')) 'Prerequisite rendering must not introduce innerHTML.'
    Assert-True ($html -match 'overflow-wrap:\s*anywhere') 'Prerequisite text must retain wrapping for narrow layouts.'
    Assert-True ($html -match '@media\s*\(max-width:\s*360px\)') 'Prerequisite details must retain the 360px responsive layout.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
