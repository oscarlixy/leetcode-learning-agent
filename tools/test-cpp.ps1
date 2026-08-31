[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProblemPath,

    [int]$TimeoutSeconds = 5,

    [string]$CompilerPath
)

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'lib/Compiler.psm1') -Force

$invokeParameters = @{
    ProblemPath = $ProblemPath
    TimeoutSeconds = $TimeoutSeconds
}
if ($PSBoundParameters.ContainsKey('CompilerPath')) {
    $invokeParameters.CompilerPath = $CompilerPath
}

$result = Invoke-CppProblemTest @invokeParameters

Write-Output $result.Status
if ($null -ne $result.Compiler) {
    Write-Output "Compiler: $($result.Compiler.Path)"
}
Write-Output "ExitCode: $($result.ExitCode)"
Write-Output "DurationMs: $($result.DurationMs)"
if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
    Write-Output $result.Output
}

if ($result.Status -eq 'FAIL') {
    exit 1
}
