Set-StrictMode -Version Latest

. "$PSScriptRoot/TestSupport.ps1"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $RepoRoot 'tools/lib/Compiler.psm1') -Force

function New-CppFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-compiler-failure-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests.cpp') -Value 'int main() { return 0; }' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'g++.exe') -Value 'fake compiler command seam' -Encoding utf8
    return (Resolve-Path -LiteralPath $fixtureRoot).Path
}

function Reset-CppBuild {
    param([string]$ProblemRoot)

    $buildPath = Join-Path $ProblemRoot '.build'
    if (Test-Path -LiteralPath $buildPath) {
        Remove-Item -LiteralPath $buildPath -Recurse -Force
    }
}

function New-FakeNativeResult {
    param(
        [int]$ExitCode,
        [string]$Output = '',
        [bool]$TimedOut = $false
    )

    return [pscustomobject]@{
        ExitCode = $ExitCode
        Output = $Output
        DurationMs = 1
        TimedOut = $TimedOut
    }
}

function New-QueuedInvoker {
    param(
        [object[]]$Results,
        [bool]$CreateCompileOutput = $false,
        [int]$ThrowOnCall = 0,
        [string]$ThrowMessage = 'native process start exploded'
    )

    $queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($result in $Results) {
        $queue.Enqueue($result)
    }
    $counter = [pscustomobject]@{ Value = 0 }

    return {
        param(
            [string]$FilePath,
            [string[]]$Arguments,
            [string]$WorkingDirectory,
            [int]$TimeoutSeconds
        )

        $counter.Value += 1
        if ($ThrowOnCall -eq $counter.Value) {
            throw $ThrowMessage
        }

        if ($CreateCompileOutput -and $counter.Value -eq 1) {
            $outputIndex = -1
            for ($index = 0; $index -lt $Arguments.Count; $index++) {
                if ($Arguments[$index] -ceq '-o') {
                    $outputIndex = $index + 1
                    break
                }
            }
            if ($outputIndex -lt 1 -or $outputIndex -ge $Arguments.Count) {
                throw 'Fake compiler could not find its output argument.'
            }
            [System.IO.File]::WriteAllText($Arguments[$outputIndex], 'fake executable')
        }

        if ($queue.Count -eq 0) {
            throw 'Fake process queue was unexpectedly exhausted.'
        }
        return $queue.Dequeue()
    }.GetNewClosure()
}

$problemRoot = New-CppFixture
try {
    $compilerPath = Join-Path $problemRoot 'g++.exe'

    # Break caught: no injectable process seam existed to deterministically classify starts/results.
    $successInvoker = New-QueuedInvoker -CreateCompileOutput $true -Results @(
        (New-FakeNativeResult -ExitCode 0 -Output 'compiled'),
        (New-FakeNativeResult -ExitCode 0 -Output 'ran')
    )
    $success = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $successInvoker
    Assert-Equal 'PASS' $success.Status 'Compiler success path must return PASS.'
    Assert-Equal 0 $success.ExitCode 'Compiler success path must return zero.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $compileFailureInvoker = New-QueuedInvoker -Results @(
        (New-FakeNativeResult -ExitCode 2 -Output 'compile failed deterministically')
    )
    $compileFailure = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $compileFailureInvoker
    Assert-Equal 'FAIL' $compileFailure.Status 'Compile failures must return FAIL.'
    Assert-Equal 2 $compileFailure.ExitCode 'Compile failure exit code mismatch.'
    Assert-True ($compileFailure.Output -match 'compile failed deterministically') 'Compile failure output was lost.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $runtimeFailureInvoker = New-QueuedInvoker -CreateCompileOutput $true -Results @(
        (New-FakeNativeResult -ExitCode 0),
        (New-FakeNativeResult -ExitCode 7 -Output 'runtime failed deterministically')
    )
    $runtimeFailure = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $runtimeFailureInvoker
    Assert-Equal 'FAIL' $runtimeFailure.Status 'Runtime failures must return FAIL.'
    Assert-Equal 7 $runtimeFailure.ExitCode 'Runtime failure exit code mismatch.'
    Assert-True ($runtimeFailure.Output -match 'runtime failed deterministically') 'Runtime failure output was lost.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $missingOutputInvoker = New-QueuedInvoker -Results @(
        (New-FakeNativeResult -ExitCode 0)
    )
    $missingOutput = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $missingOutputInvoker
    Assert-Equal 'FAIL' $missingOutput.Status 'Compiler success without an executable must return FAIL.'
    Assert-True ($missingOutput.Output -match '(?i)executable|output') 'Missing compiler output must be explained.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $compileStartExceptionInvoker = New-QueuedInvoker -ThrowOnCall 1 -ThrowMessage 'compiler process start exploded' -Results @()
    $compileStartException = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $compileStartExceptionInvoker
    Assert-Equal 'FAIL' $compileStartException.Status 'Compiler start exceptions must return FAIL.'
    Assert-True ($compileStartException.Output -match 'compiler process start exploded') 'Compiler start exception detail was lost.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $runtimeStartExceptionInvoker = New-QueuedInvoker -CreateCompileOutput $true -ThrowOnCall 2 -ThrowMessage 'runtime process start exploded' -Results @(
        (New-FakeNativeResult -ExitCode 0)
    )
    $runtimeStartException = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $runtimeStartExceptionInvoker
    Assert-Equal 'FAIL' $runtimeStartException.Status 'Runtime start exceptions must return FAIL.'
    Assert-True ($runtimeStartException.Output -match 'runtime process start exploded') 'Runtime start exception detail was lost.'

    Reset-CppBuild -ProblemRoot $problemRoot
    $timeoutInvoker = New-QueuedInvoker -Results @(
        (New-FakeNativeResult -ExitCode -1 -TimedOut $true)
    )
    $timeout = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker $timeoutInvoker -TimeoutSeconds 1
    Assert-Equal 'FAIL' $timeout.Status 'Compiler timeout must return FAIL.'
    Assert-True ($timeout.Output -match '(?i)timed out') 'Compiler timeout must be explained.'

    Reset-CppBuild -ProblemRoot $problemRoot
    Set-Content -LiteralPath (Join-Path $problemRoot '.build') -Value 'blocks directory creation' -Encoding utf8
    $buildPreparation = Invoke-CppProblemTest -ProblemPath $problemRoot -CompilerPath $compilerPath -NativeProcessInvoker (New-QueuedInvoker -Results @())
    Assert-Equal 'FAIL' $buildPreparation.Status 'Build-directory preparation errors must return FAIL.'
    Assert-True ($buildPreparation.Output -match '(?i)build|directory|container') 'Build-directory failure must be explained.'
}
finally {
    if (Test-Path -LiteralPath $problemRoot) {
        Remove-Item -LiteralPath $problemRoot -Recurse -Force
    }
}

# The CLI wrapper must structure even setup errors before any PowerShell diagnostic text.
$missingProblemPath = Join-Path ([System.IO.Path]::GetTempPath()) ("leetcode-missing-problem-" + [System.Guid]::NewGuid().ToString('N'))
$cliOutput = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/test-cpp.ps1') -ProblemPath $missingProblemPath 2>&1
$cliExitCode = $LASTEXITCODE
$cliText = $cliOutput -join [Environment]::NewLine
Assert-Equal 1 $cliExitCode 'Missing problem path must make test-cpp exit 1.'
Assert-True ($cliText -match '^FAIL(?:\r?\n|$)') "test-cpp output must begin with structured FAIL. Output=[$cliText]"
