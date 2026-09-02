[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProblemPath,

    [int]$TimeoutSeconds = 5,

    [string]$CompilerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'lib/Compiler.psm1') -Force -ErrorAction Stop

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

    if ($result.Status -ceq 'FAIL') {
        exit 1
    }
}
catch {
    Write-Output 'FAIL'
    Write-Output 'ExitCode: 1'
    Write-Output "C++ test wrapper failed: $($_.Exception.Message)"
    exit 1
}
