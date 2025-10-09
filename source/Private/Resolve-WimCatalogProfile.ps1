function Resolve-WimCatalogProfile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        $WimInfo,

        [Parameter()]
        [string] $PreferredRelease,

        [Parameter()]
        [string] $PreferredChannel
    )

    $catalogData = Get-ToolkitCatalogData
    $archValue = ($WimInfo.Architecture ?? 'x64')
    $archNormalized = switch -Regex ($archValue.ToString().ToLowerInvariant()) {
        'amd64' { 'x64'; break }
        'x64'   { 'x64'; break }
        '64'    { 'x64'; break }
        'arm64' { 'ARM64'; break }
        'aarch64' { 'ARM64'; break }
        'x86'   { 'x86'; break }
        '86'    { 'x86'; break }
        default { 'x64' }
    }

    $buildNumber = $null
    if ($WimInfo.Version -and $WimInfo.Version -is [Version]) {
        $buildNumber = $WimInfo.Version.Build
    }

    $nameString = $WimInfo.Name ?? ''
    $descriptionString = $WimInfo.Description ?? ''
    $combinedLabel = "$nameString $descriptionString"

    $matchCandidates = foreach ($os in $catalogData.OperatingSystems) {
        foreach ($release in $os.Releases) {
            $buildMatch = $false
            if ($null -ne $buildNumber) {
                if ($release.BuildMax) {
                    if (($buildNumber -ge $release.BuildMin) -and ($buildNumber -le $release.BuildMax)) {
                        $buildMatch = $true
                    }
                } elseif ($buildNumber -ge $release.BuildMin) {
                    $buildMatch = $true
                }
            }

            $labelMatch = $combinedLabel -like "*$($os.Name)*" -or $combinedLabel -like "*$($release.Name)*"
            if ($buildMatch -or $labelMatch) {
                [pscustomobject]@{
                    OperatingSystem = $os
                    Release         = $release
                }
            }
        }
    }

    $selected = $null
    if ($PreferredRelease) {
        $selected = $matchCandidates | Where-Object { $_.Release.Name -eq $PreferredRelease } | Select-Object -First 1
    }

    if (-not $selected) {
        $selected = $matchCandidates | Select-Object -First 1
    }

    if (-not $selected) {
        if ($combinedLabel -match '(?i)server') {
            $fallbackOs = $catalogData.OperatingSystems | Where-Object { $_.Name -eq 'Windows Server' } | Select-Object -First 1
        } elseif ($buildNumber -and $buildNumber -ge 22000) {
            $fallbackOs = $catalogData.OperatingSystems | Where-Object { $_.Name -eq 'Windows 11' } | Select-Object -First 1
        } else {
            $fallbackOs = $catalogData.OperatingSystems | Where-Object { $_.Name -eq 'Windows 10' } | Select-Object -First 1
        }

        $fallbackRelease = $fallbackOs.Releases | Sort-Object -Property BuildMin -Descending | Select-Object -First 1
        $selected = [pscustomobject]@{
            OperatingSystem = $fallbackOs
            Release         = $fallbackRelease
        }
    }

    $channel = if ($PreferredChannel) {
        $PreferredChannel
    } elseif ($selected.OperatingSystem.Channels -contains 'General Availability') {
        'General Availability'
    } else {
        $selected.OperatingSystem.Channels | Select-Object -First 1
    }

    if ($selected.Release.Architectures -notcontains $archNormalized) {
        $archNormalized = $selected.Release.Architectures | Select-Object -First 1
    }

    return [pscustomobject]@{
        OperatingSystem = $selected.OperatingSystem.Name
        Release         = $selected.Release.Name
        Query           = $selected.Release.Query
        Architecture    = $archNormalized
        Channel         = $channel
        Build           = $buildNumber
    }
}
