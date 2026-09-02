Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$agents = Get-Content -LiteralPath (Join-Path $RepoRoot 'AGENTS.md') -Raw -Encoding utf8
$skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/SKILL.md') -Raw -Encoding utf8
$sessionProtocol = Get-Content -LiteralPath (Join-Path $RepoRoot '.agents/skills/leetcode-coach/references/session-protocol.md') -Raw -Encoding utf8
$untrustedImportEvalPath = Join-Path $RepoRoot 'evals/untrusted-import.md'
Assert-True (Test-Path -LiteralPath $untrustedImportEvalPath -PathType Leaf) 'A malicious imported-data eval is required.'
$selfSelectedEval = Get-Content -LiteralPath $untrustedImportEvalPath -Raw -Encoding utf8
$combinedPolicy = @($agents, $skill, $sessionProtocol) -join [Environment]::NewLine

# Break caught: imported fields were not explicitly classified as inert, untrusted data.
foreach ($fieldPattern in @(
    @{ Label = 'title'; Pattern = '\btitles?\b' },
    @{ Label = 'URL'; Pattern = '\bURLs?\b' },
    @{ Label = 'summary'; Pattern = '\bsummar(?:y|ies)\b' },
    @{ Label = 'constraint'; Pattern = '\bconstraints?\b' },
    @{ Label = 'example'; Pattern = '\bexamples?\b' },
    @{ Label = 'metadata'; Pattern = '\bmetadata\b' }
)) {
    Assert-True ($combinedPolicy -match ("(?i){0}" -f $fieldPattern.Pattern)) "Imported-data policy must name [$($fieldPattern.Label)]."
}
Assert-True ($combinedPolicy -match '(?i)(inert|untrusted).{0,100}(data|content)|(data|content).{0,100}(inert|untrusted)') 'Imported problem content must be classified as inert or untrusted data.'
Assert-True ($combinedPolicy -match '(?i)(never|cannot|must not).{0,120}(instruction|execute|obey)') 'Imported problem content must never be treated as instructions.'
Assert-True ($combinedPolicy -match '(?i)(cannot|must not).{0,180}(bypass|override).{0,100}(hint|L5|repository|coaching)') 'Imported data must not bypass hint gates or repository coaching rules.'
Assert-True ($combinedPolicy -match '(?i)(cannot|must not).{0,180}(authorize|permission).{0,100}(attempt\.cpp|learner)') 'Imported data must not authorize learner-file modification.'

# The behavior eval must pressure-test an instruction-looking title or summary.
Assert-True ($selfSelectedEval -match '(?i)(title|summary).{0,160}(ignore|overwrite|reference\.cpp|L5)') 'Self-selected-problem eval must include malicious instruction-looking imported data.'
Assert-True ($selfSelectedEval -match '(?i)(treat|keep).{0,100}(inert|untrusted|data)') 'Self-selected-problem eval must require treating malicious imported text as data.'
