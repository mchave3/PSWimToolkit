function Test-WimImageVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath
    )

    $resolvedMountPath = (Resolve-Path -LiteralPath $MountPath -ErrorAction Stop).ProviderPath
    $softwareHive = Join-Path -Path $resolvedMountPath -ChildPath 'Windows\System32\config\SOFTWARE'

    if (-not (Test-Path -LiteralPath $softwareHive -PathType Leaf)) {
        Write-ProvisioningLog -Message "SOFTWARE hive not found under $resolvedMountPath." -Type Error -Source 'Test-WimImageVersion'
        throw [System.IO.FileNotFoundException]::new("Unable to locate SOFTWARE registry hive for mounted image.")
    }

    $registryKeyName = "PSWimToolkit_$([System.Guid]::NewGuid().ToString('N'))"
    $loadArgs = @('LOAD', "HKLM\$registryKeyName", $softwareHive)
    $unloadArgs = @('UNLOAD', "HKLM\$registryKeyName")

    try {
        Write-ProvisioningLog -Message "Loading offline registry hive for version detection." -Type Debug -Source 'Test-WimImageVersion'
        $loadResult = & reg.exe @loadArgs
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe LOAD failed with exit code $LASTEXITCODE. $loadResult"
        }

        $regPath = "Registry::HKEY_LOCAL_MACHINE\$registryKeyName\Microsoft\Windows NT\CurrentVersion"
        $osInfo = Get-ItemProperty -Path $regPath -ErrorAction Stop

        $major = $osInfo.CurrentMajorVersionNumber
        if (-not $major) { $major = 10 }
        $minor = $osInfo.CurrentMinorVersionNumber
        if (-not $minor) { $minor = 0 }
        $build = [int]$osInfo.CurrentBuildNumber
        $ubrValue = if ($null -ne $osInfo.UBR) { [int]$osInfo.UBR } else { 0 }

        $versionString = '{0}.{1}.{2}.{3}' -f $major, $minor, $build, $ubrValue
        $version = [version]$versionString

        $channel = if ($version.Build -ge 26100) {
            'Windows 11 24H2'
        } elseif ($version.Build -ge 22621) {
            'Windows 11'
        } elseif ($version.Build -ge 19041) {
            'Windows 10'
        } else {
            'Windows'
        }

        $result = [pscustomobject]@{
            ProductName    = $osInfo.ProductName
            EditionID      = $osInfo.EditionID
            ReleaseId      = $osInfo.ReleaseId
            DisplayVersion = $osInfo.DisplayVersion
            CurrentBuild   = $osInfo.CurrentBuild
            UBR            = $osInfo.UBR
            Version        = $version
            Channel        = $channel
        }

        Write-ProvisioningLog -Message ("Detected {0} ({1}) version {2}" -f $result.ProductName, $result.Channel, $result.Version) -Type Info -Source 'Test-WimImageVersion'
        return $result
    } catch {
        Write-ProvisioningLog -Message ("Failed to detect image version at {0}. {1}" -f $resolvedMountPath, $_.Exception.Message) -Type Error -Source 'Test-WimImageVersion'
        throw
    } finally {
        try {
            & reg.exe @unloadArgs | Out-Null
        } catch {
            Write-ProvisioningLog -Message ("Failed to unload offline registry hive {0}: {1}" -f $registryKeyName, $_.Exception.Message) -Type Warning -Source 'Test-WimImageVersion'
        }
    }
}
