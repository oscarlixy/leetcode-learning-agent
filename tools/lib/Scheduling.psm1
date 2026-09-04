Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -Force

function Get-LearnerToday {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [datetimeoffset]$Instant = [datetimeoffset]::UtcNow
    )

    $profile = Validation\Read-JsonDocument ([System.IO.Path]::GetFullPath($ProfilePath))
    Validation\Assert-ProfileDocument $profile
    $timeZone = Resolve-LearnerTimeZone -TimeZoneId $profile.timezone
    $learnerTime = [System.TimeZoneInfo]::ConvertTime($Instant, $timeZone)
    return $learnerTime.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-LearnerReviewDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3650)]
        [int]$Days,

        [datetimeoffset]$Instant = [datetimeoffset]::UtcNow
    )

    $todayText = Get-LearnerToday -ProfilePath $ProfilePath -Instant $Instant
    $today = [datetime]::ParseExact(
        $todayText,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None
    )
    return $today.AddDays($Days).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Resolve-LearnerTimeZone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TimeZoneId
    )

    try {
        return [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    }
    catch {
        $windowsTimeZoneId = $null
        try {
            if ([System.TimeZoneInfo]::TryConvertIanaIdToWindowsId($TimeZoneId, [ref]$windowsTimeZoneId)) {
                return [System.TimeZoneInfo]::FindSystemTimeZoneById($windowsTimeZoneId)
            }
        }
        catch {
            # Preserve one stable, actionable error below on runtimes without IANA conversion support.
        }

        throw "Learner timezone [$TimeZoneId] is not available on this system."
    }
}

Export-ModuleMember -Function @(
    'Get-LearnerToday',
    'Get-LearnerReviewDate'
)
