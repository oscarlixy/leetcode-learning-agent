Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$RepoRoot/tools/lib/Compiler.psm1" -Force

function New-CppProblemFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-cpp-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests.cpp') -Value @'
#include <cassert>
int main() {
    assert(true);
    return 0;
}
'@ -Encoding utf8

    return (Resolve-Path -LiteralPath $fixtureRoot).Path
}

$none = Find-CppCompiler -CandidateCommands @('leetcode-compiler-that-does-not-exist')
Assert-Equal $null $none 'Missing compiler must return null.'

$gnu = [pscustomobject]@{ Family = 'gnu'; Path = 'g++' }
$gnuCommand = Get-CppCompileCommand $gnu 'C:/work/tests.cpp' 'C:/work/tests.exe'
Assert-True ($gnuCommand.Arguments -contains '-std=c++20') 'GNU command lacks C++20.'
Assert-True ($gnuCommand.Arguments -contains '-Wall') 'GNU command lacks warnings.'
Assert-True ($gnuCommand.Arguments -contains '-Wextra') 'GNU command lacks extra warnings.'
Assert-True ($gnuCommand.Arguments -contains '-Wpedantic') 'GNU command lacks pedantic warnings.'

$msvc = [pscustomobject]@{ Family = 'msvc'; Path = 'cl.exe' }
$msvcCommand = Get-CppCompileCommand $msvc 'C:/work/tests.cpp' 'C:/work/tests.exe'
Assert-True ($msvcCommand.Arguments -contains '/std:c++20') 'MSVC command lacks C++20.'
Assert-True ($msvcCommand.Arguments -contains '/W4') 'MSVC command lacks warnings.'
Assert-True ($msvcCommand.Arguments -contains '/EHsc') 'MSVC command lacks exception handling mode.'

$problemRoot = New-CppProblemFixture
try {
    $result = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath 'leetcode-compiler-that-does-not-exist.exe'
    Assert-Equal 'SKIPPED' $result.Status 'Missing compiler should skip execution.'
    Assert-Equal 0 $result.ExitCode 'Missing compiler should return exit code 0.'
    Assert-True ($result.Output -match 'compiler') 'Missing compiler output must mention compiler installation.'

    $cliOutput = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/test-cpp.ps1') `
        -ProblemPath $problemRoot `
        -CompilerPath 'leetcode-compiler-that-does-not-exist.exe' 2>&1
    $cliExitCode = $LASTEXITCODE
    Assert-Equal 0 $cliExitCode 'test-cpp should not fail when the compiler is missing.'
    Assert-True (($cliOutput -join [Environment]::NewLine) -match '^SKIPPED\b') 'test-cpp output must begin with SKIPPED when no compiler is available.'
}
finally {
    if (Test-Path -LiteralPath $problemRoot) {
        Remove-Item -LiteralPath $problemRoot -Recurse -Force
    }
}
