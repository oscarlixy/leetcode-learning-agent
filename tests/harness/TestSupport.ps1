Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Throws {
    param([scriptblock]$Script, [string]$MessagePattern)
    try { & $Script } catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "Exception did not match [$MessagePattern]: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected exception matching [$MessagePattern]"
}
