[CmdletBinding()]
param(
    [string]$TestFile
)

Set-StrictMode -Version Latest

$testRoot = Split-Path -Parent $PSCommandPath
$testFiles = if ($TestFile) {
    $candidate = if ([System.IO.Path]::IsPathRooted($TestFile)) {
        $TestFile
    } else {
        Join-Path $testRoot $TestFile
    }
    Get-Item -LiteralPath $candidate -ErrorAction Stop
} else {
    Get-ChildItem -LiteralPath $testRoot -Filter '*.Tests.ps1' -File | Sort-Object Name
}

$failed = $false
foreach ($test in @($testFiles)) {
    try {
        & $test.FullName
        Write-Output "PASS $($test.Name)"
    } catch {
        $failed = $true
        Write-Output "FAIL $($test.Name): $($_.Exception.Message)"
    }
}

if ($failed) { exit 1 }
