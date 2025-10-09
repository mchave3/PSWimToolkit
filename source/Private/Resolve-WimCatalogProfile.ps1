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
        [string] $PreferredArchitecture
    )

    $catalogData = Get-ToolkitCatalogData
    $archSeed = $PreferredArchitecture ?? $WimInfo.Architecture ?? 'x64'
    $archNormalized = switch -Regex ($archSeed.ToString().ToLowerInvariant()) {
        'amd64' { 'x64' }
        'x64'   { 'x64' }
        'arm64' { 'arm64' }
        'aarch64' { 'arm64' }
        'x86'   { 'x86' }
        '86'    { 'x86' }
        default { 'x64' }
    }

    $buildNumber = $null
    if ($WimInfo.Version -and $WimInfo.Version -is [Version]) {
        $buildNumber = $WimInfo.Version.Build
    }

    $label = @($WimInfo.Name, $WimInfo.Description) -join ' '

    $candidates = @()
    foreach ($os in $catalogData.OperatingSystems) {
        foreach ($release in $os.Releases) {
            $buildMatch = $false
            if ($buildNumber) {
                if ($release.BuildMax) {
                    $buildMatch = ($buildNumber -ge $release.BuildMin) -and ($buildNumber -le $release.BuildMax)
                } else {
                    $buildMatch = $buildNumber -ge $release.BuildMin
                }
            }

            $labelMatch = $false
            if (-not $labelMatch -and $label) {
                $labelMatch = ($label -like "*$($os.Name)*") -or ($label -like "*$($release.Name)*")
            }

            if ($buildMatch -or $labelMatch) {
                $candidates += [pscustomobject]@{
                    OperatingSystem = $os
                    Release         = $release
                }
            }
        }
    }

    $selection = $null
    if ($PreferredRelease) {
        $selection = $candidates | Where-Object { $_.Release.Name -eq $PreferredRelease } | Select-Object -First 1
    }

    if (-not $selection) {
        $selection = $candidates | Select-Object -First 1
    }

    if (-not $selection) {
        $fallbackName = if ($label -match '(?i)server') {
            'Windows Server'
        } elseif ($buildNumber -and $buildNumber -ge 22000) {
            'Windows 11'
        } else {
            'Windows 10'
        }

        $fallbackOs = $catalogData.OperatingSystems | Where-Object { $_.Name -eq $fallbackName } | Select-Object -First 1
        $fallbackRelease = $fallbackOs.Releases | Sort-Object -Property BuildMin -Descending | Select-Object -First 1
        $selection = [pscustomobject]@{
            OperatingSystem = $fallbackOs
            Release         = $fallbackRelease
        }
    }

    if ($selection.Release.Architectures -and ($selection.Release.Architectures -notcontains $archNormalized)) {
        $archNormalized = $selection.Release.Architectures | Select-Object -First 1
    }

    [pscustomobject]@{
        OperatingSystem = $selection.OperatingSystem.Name
        Release         = $selection.Release.Name
        Query           = $selection.Release.Query
        Architecture    = $archNormalized
        Build           = $buildNumber
    }
}
