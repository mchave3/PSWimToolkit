function Invoke-ParseDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $DateString
    )

    if ([string]::IsNullOrWhiteSpace($DateString)) {
        throw [System.ArgumentException]::new('DateString cannot be empty.', 'DateString')
    }

    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($DateString, $culture, $styles, [ref]$parsed)) {
        return $parsed
    }

    # Fallback for catalog-specific format (MM/DD/YYYY)
    $segments = $DateString.Split('/', '-', '.').Where({ $_ -ne '' })
    if ($segments.Count -eq 3) {
        $month = [int]$segments[0]
        $day = [int]$segments[1]
        $year = [int]$segments[2]
        return Get-Date -Year $year -Month $month -Day $day
    }

    Write-ToolkitLog -Message "Unable to parse catalog date string '$DateString'." -Type Warning -Source 'Invoke-ParseDate'
    return Get-Date
}
