[CmdletBinding()]
param()

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'lib/Compiler.psm1') -Force

$compiler = Find-CppCompiler
if ($null -eq $compiler) {
    Write-Output 'compiler: MISSING install cl.exe, clang++.exe, or g++.exe to enable local C++ runs.'
    Write-Output 'execution: LIMITED learning can continue without local C++ execution.'
    Write-Output 'LIMITED'
    exit 0
}

Write-Output "compiler: READY $($compiler.Family) $($compiler.Path)"
Write-Output 'execution: READY local C++ compile-and-run is available.'
Write-Output 'READY'
