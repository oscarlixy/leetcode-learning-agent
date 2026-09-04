Set-StrictMode -Version Latest

$script:DefaultCandidateCommands = @('cl.exe', 'clang++.exe', 'g++.exe')

function Get-CppCompilerFamily {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $leaf = [System.IO.Path]::GetFileName($CommandName).ToLowerInvariant()
    switch -Regex ($leaf) {
        '^cl(\.exe)?$' { return 'msvc' }
        '^clang\+\+(\.exe)?$' { return 'clang' }
        '^g\+\+(\.exe)?$' { return 'gnu' }
        default { return $null }
    }
}

function Resolve-CppCompilerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidateCommand
    )

    $family = Get-CppCompilerFamily -CommandName $CandidateCommand
    if ($null -eq $family) {
        return $null
    }

    $hasDirectorySeparator = $CandidateCommand.Contains([System.IO.Path]::DirectorySeparatorChar) -or `
        $CandidateCommand.Contains([System.IO.Path]::AltDirectorySeparatorChar)

    if ([System.IO.Path]::IsPathRooted($CandidateCommand) -or $hasDirectorySeparator) {
        if (-not (Test-Path -LiteralPath $CandidateCommand -PathType Leaf)) {
            return $null
        }

        return [pscustomobject]@{
            Family = $family
            Path = (Resolve-Path -LiteralPath $CandidateCommand).Path
        }
    }

    $command = Get-Command -Name $CandidateCommand -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    return [pscustomobject]@{
        Family = $family
        Path = $command.Path
    }
}

function Find-CppCompiler {
    [CmdletBinding()]
    param(
        [string[]]$CandidateCommands = $script:DefaultCandidateCommands
    )

    foreach ($candidateCommand in $CandidateCommands) {
        $compiler = Resolve-CppCompilerCommand -CandidateCommand $candidateCommand
        if ($null -ne $compiler) {
            return $compiler
        }
    }

    return $null
}

function Join-ChildPathPreservingStyle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParentPath,

        [Parameter(Mandatory = $true)]
        [string]$ChildName
    )

    $separator = if ($ParentPath.Contains('/') -and -not $ParentPath.Contains('\')) { '/' } else { '\' }
    return "$($ParentPath.TrimEnd('\', '/'))$separator$ChildName"
}

function Get-ParentPathPreservingStyle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lastSeparatorIndex = [Math]::Max($Path.LastIndexOf('/'), $Path.LastIndexOf('\'))
    if ($lastSeparatorIndex -lt 0) {
        throw "Path [$Path] does not include a parent directory."
    }

    return $Path.Substring(0, $lastSeparatorIndex)
}

function Get-CppCompileCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Compiler,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    switch ($Compiler.Family) {
        'msvc' {
            $outputDirectory = Get-ParentPathPreservingStyle -Path $OutputPath
            $objectFileName = ([System.IO.Path]::GetFileNameWithoutExtension($SourcePath)) + '.obj'
            $objectPath = Join-ChildPathPreservingStyle -ParentPath $outputDirectory -ChildName $objectFileName
            $arguments = @('/nologo', '/std:c++20', '/W4', '/EHsc', $SourcePath, "/Fe:$OutputPath", "/Fo:$objectPath")
            break
        }
        'clang' {
            $arguments = @('-std=c++20', '-Wall', '-Wextra', '-Wpedantic', $SourcePath, '-o', $OutputPath)
            break
        }
        'gnu' {
            $arguments = @('-std=c++20', '-Wall', '-Wextra', '-Wpedantic', $SourcePath, '-o', $OutputPath)
            break
        }
        default {
            throw "Unsupported compiler family [$($Compiler.Family)]."
        }
    }

    return [pscustomobject]@{
        Path = $Compiler.Path
        Arguments = $arguments
    }
}

function Join-ProcessOutput {
    param(
        [AllowEmptyString()]
        [string]$StandardOutput,

        [AllowEmptyString()]
        [string]$StandardError
    )

    return @($StandardOutput, $StandardError) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.TrimEnd() } |
        Join-String -Separator [Environment]::NewLine
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processStartInfo.FileName = $FilePath
    $processStartInfo.WorkingDirectory = $WorkingDirectory
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.RedirectStandardError = $true

    foreach ($argument in $Arguments) {
        [void]$processStartInfo.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processStartInfo

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $timedOut = -not $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
    if ($timedOut) {
        try {
            $process.Kill($true)
        }
        catch {
            if (-not $process.HasExited) {
                $process.Kill()
            }
        }
        $process.WaitForExit()
    }

    [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask))
    $stopwatch.Stop()

    $output = Join-ProcessOutput -StandardOutput $stdoutTask.Result -StandardError $stderrTask.Result

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        Output = $output
        DurationMs = [int][Math]::Round($stopwatch.Elapsed.TotalMilliseconds)
        TimedOut = $timedOut
    }
}

function New-CppTestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [AllowNull()]
        $Compiler,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [int]$DurationMs
    )

    return [pscustomobject]@{
        Status = $Status
        Compiler = $Compiler
        ExitCode = $ExitCode
        Output = $Output
        DurationMs = $DurationMs
    }
}

function Invoke-CppProblemTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProblemPath,

        [int]$TimeoutSeconds = 5,

        [string]$CompilerPath,

        [scriptblock]$NativeProcessInvoker
    )

    $overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $compiler = $null

    try {
        $resolvedProblemPath = (Resolve-Path -LiteralPath $ProblemPath -ErrorAction Stop).Path
        $testsPath = Join-Path $resolvedProblemPath 'tests.cpp'
        if (-not (Test-Path -LiteralPath $testsPath -PathType Leaf)) {
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $null -ExitCode 1 -Output 'tests.cpp was not found.'
        }

        $compiler = if ($PSBoundParameters.ContainsKey('CompilerPath')) {
            Find-CppCompiler -CandidateCommands @($CompilerPath)
        } else {
            Find-CppCompiler
        }

        if ($null -eq $compiler) {
            $requestedCompiler = if ($PSBoundParameters.ContainsKey('CompilerPath')) {
                $CompilerPath
            } else {
                'cl.exe, clang++.exe, or g++.exe'
            }
            $skipMessage = "No supported C++ compiler is available. Install $requestedCompiler to run local problem tests."
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'SKIPPED' -Compiler $null -ExitCode 0 -Output $skipMessage
        }

        $buildDirectory = Join-Path $resolvedProblemPath '.build'
        [void][System.IO.Directory]::CreateDirectory($buildDirectory)
        if (-not (Test-Path -LiteralPath $buildDirectory -PathType Container)) {
            throw "Build path [$buildDirectory] is not a directory."
        }

        $executablePath = Join-Path $buildDirectory 'tests.exe'
        if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
            [System.IO.File]::Delete($executablePath)
        }
        $compileCommand = Get-CppCompileCommand -Compiler $compiler -SourcePath $testsPath -OutputPath $executablePath

        $compileResult = Invoke-CppNativeOperation `
            -Invoker $NativeProcessInvoker `
            -FilePath $compileCommand.Path `
            -Arguments $compileCommand.Arguments `
            -WorkingDirectory $resolvedProblemPath `
            -TimeoutSeconds $TimeoutSeconds

        if ($compileResult.TimedOut) {
            $timeoutMessage = "Compilation timed out after $TimeoutSeconds seconds."
            $compileOutput = if ([string]::IsNullOrWhiteSpace($compileResult.Output)) {
                $timeoutMessage
            } else {
                "$timeoutMessage$([Environment]::NewLine)$($compileResult.Output)"
            }
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode $compileResult.ExitCode -Output $compileOutput
        }

        if ($compileResult.ExitCode -ne 0) {
            $failureMessage = if ([string]::IsNullOrWhiteSpace($compileResult.Output)) {
                'Compilation failed.'
            } else {
                $compileResult.Output
            }
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode $compileResult.ExitCode -Output $failureMessage
        }

        if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode 1 -Output 'Compilation reported success but did not create the expected executable output.'
        }

        $runResult = Invoke-CppNativeOperation `
            -Invoker $NativeProcessInvoker `
            -FilePath $executablePath `
            -WorkingDirectory $resolvedProblemPath `
            -TimeoutSeconds $TimeoutSeconds

        if ($runResult.TimedOut) {
            $timeoutMessage = "Execution timed out after $TimeoutSeconds seconds."
            $runOutput = if ([string]::IsNullOrWhiteSpace($runResult.Output)) {
                $timeoutMessage
            } else {
                "$timeoutMessage$([Environment]::NewLine)$($runResult.Output)"
            }
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode $runResult.ExitCode -Output $runOutput
        }

        if ($runResult.ExitCode -ne 0) {
            $failureMessage = if ([string]::IsNullOrWhiteSpace($runResult.Output)) {
                'Test execution failed.'
            } else {
                $runResult.Output
            }
            return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode $runResult.ExitCode -Output $failureMessage
        }

        $successMessage = if ([string]::IsNullOrWhiteSpace($runResult.Output)) {
            'Tests passed.'
        } else {
            $runResult.Output
        }
        return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'PASS' -Compiler $compiler -ExitCode $runResult.ExitCode -Output $successMessage
    }
    catch {
        $failureMessage = "C++ test setup or process invocation failed: $($_.Exception.Message)"
        return Complete-CppTestResult -Stopwatch $overallStopwatch -Status 'FAIL' -Compiler $compiler -ExitCode 1 -Output $failureMessage
    }
}

function Invoke-CppNativeOperation {
    param(
        [AllowNull()]
        [scriptblock]$Invoker,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    if ($null -ne $Invoker) {
        return & $Invoker -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
    }

    return Invoke-NativeProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
}

function Complete-CppTestResult {
    param(
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [string]$Status,
        [AllowNull()]$Compiler,
        [int]$ExitCode,
        [AllowEmptyString()][string]$Output
    )

    if ($Stopwatch.IsRunning) {
        $Stopwatch.Stop()
    }
    return New-CppTestResult `
        -Status $Status `
        -Compiler $Compiler `
        -ExitCode $ExitCode `
        -Output $Output `
        -DurationMs ([int][Math]::Round($Stopwatch.Elapsed.TotalMilliseconds))
}

Export-ModuleMember -Function Find-CppCompiler, Get-CppCompileCommand, Invoke-CppProblemTest
