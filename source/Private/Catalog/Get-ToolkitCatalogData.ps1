function Get-ToolkitCatalogData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    if (-not (Get-Variable -Name ToolkitCatalogData -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ToolkitCatalogData = $null
    }

    if (-not $script:ToolkitCatalogData) {
        Write-ToolkitLog -Message "Initializing catalog data..." -Type Debug -Source 'Get-ToolkitCatalogData'

        $command = Get-Command -Name Find-WindowsUpdate -Module PSWimToolkit -ErrorAction SilentlyContinue
        $architectures = @('x64', 'x86', 'arm64')
        $operatingSystems = @('Windows 11', 'Windows 10', 'Windows Server')
        $updateTypes = @(
            'Security Updates',
            'Updates',
            'Critical Updates',
            'Feature Packs',
            'Service Packs',
            'Tools',
            'Update Rollups',
            'Cumulative Updates',
            'Security Quality Updates',
            'Driver Updates'
        )

        if ($command) {
            $getValidValues = {
                param($parameterName)
                $param = $command.Parameters[$parameterName]
                if (-not $param) { return @() }
                foreach ($attr in $param.Attributes) {
                    if ($attr -is [System.Management.Automation.ValidateSetAttribute]) {
                        return $attr.ValidValues
                    }
                }
                return @()
            }

            $archValues = & $getValidValues 'Architecture'
            if ($archValues.Count -gt 0) { $architectures = $archValues }

            $osValues = & $getValidValues 'OperatingSystem'
            if ($osValues.Count -gt 0) { $operatingSystems = $osValues }

            $typeValues = & $getValidValues 'UpdateType'
            if ($typeValues.Count -gt 0) { $updateTypes = $typeValues }
        }

        $releaseMatrix = @(
            [pscustomobject]@{
                Name     = 'Windows 11'
                Releases = @(
                    [pscustomobject]@{ Name = '25H2'; Query = 'Windows 11 25H2'; Architectures = @('x64', 'arm64'); Build = 26200 }
                    [pscustomobject]@{ Name = '24H2'; Query = 'Windows 11 24H2'; Architectures = @('x64', 'arm64'); Build = 26100 }
                    [pscustomobject]@{ Name = '23H2'; Query = 'Windows 11 23H2'; Architectures = @('x64', 'arm64'); Build = 22631 }
                    [pscustomobject]@{ Name = '22H2'; Query = 'Windows 11 22H2'; Architectures = @('x64', 'arm64'); Build = 22621 }
                    [pscustomobject]@{ Name = '21H2'; Query = 'Windows 11 21H2'; Architectures = @('x64', 'arm64'); Build = 22000 }
                )
            }
            [pscustomobject]@{
                Name     = 'Windows 10'
                Releases = @(
                    [pscustomobject]@{ Name = '22H2'; Query = 'Windows 10 22H2'; Architectures = @('x64', 'x86', 'arm64'); Build = 19045 }
                    [pscustomobject]@{ Name = '21H2'; Query = 'Windows 10 21H2'; Architectures = @('x64', 'x86', 'arm64'); Build = 19044 }
                    [pscustomobject]@{ Name = '21H1'; Query = 'Windows 10 21H1'; Architectures = @('x64', 'x86'); Build = 19043 }
                    [pscustomobject]@{ Name = '20H2'; Query = 'Windows 10 20H2'; Architectures = @('x64', 'x86'); Build = 19042 }
                    [pscustomobject]@{ Name = '2004'; Query = 'Windows 10 2004'; Architectures = @('x64', 'x86'); Build = 19041 }
                    [pscustomobject]@{ Name = '1909'; Query = 'Windows 10 1909'; Architectures = @('x64', 'x86'); Build = 18363 }
                    [pscustomobject]@{ Name = '1903'; Query = 'Windows 10 1903'; Architectures = @('x64', 'x86'); Build = 18362 }
                    [pscustomobject]@{ Name = '1809'; Query = 'Windows 10 1809'; Architectures = @('x64', 'x86'); Build = 17763 }
                    [pscustomobject]@{ Name = '1803'; Query = 'Windows 10 1803'; Architectures = @('x64', 'x86'); Build = 17134 }
                    [pscustomobject]@{ Name = '1709'; Query = 'Windows 10 1709'; Architectures = @('x64', 'x86'); Build = 16299 }
                    [pscustomobject]@{ Name = '1703'; Query = 'Windows 10 1703'; Architectures = @('x64', 'x86'); Build = 15063 }
                    [pscustomobject]@{ Name = '1607'; Query = 'Windows 10 1607'; Architectures = @('x64', 'x86'); Build = 14393 }
                    [pscustomobject]@{ Name = '1511'; Query = 'Windows 10 1511'; Architectures = @('x64', 'x86'); Build = 10586 }
                    [pscustomobject]@{ Name = '1507'; Query = 'Windows 10 1507'; Architectures = @('x64', 'x86'); Build = 10240 }
                )
            }
            [pscustomobject]@{
                Name     = 'Windows Server'
                Releases = @(
                    [pscustomobject]@{ Name = '2025'; Query = 'Windows Server 2025'; Architectures = @('x64', 'arm64'); Build = 26100 }
                    [pscustomobject]@{ Name = '23H2'; Query = 'Windows Server 23H2'; Architectures = @('x64'); Build = 25398 }
                    [pscustomobject]@{ Name = '2022'; Query = 'Windows Server 2022'; Architectures = @('x64', 'x86'); Build = 20348 }
                    [pscustomobject]@{ Name = '20H2'; Query = 'Windows Server 20H2'; Architectures = @('x64', 'x86'); Build = 19042 }
                    [pscustomobject]@{ Name = '2019'; Query = 'Windows Server 2019'; Architectures = @('x64', 'x86'); Build = 17763 }
                    [pscustomobject]@{ Name = '2016'; Query = 'Windows Server 2016'; Architectures = @('x64', 'x86'); Build = 14393 }
                )
            }
        )

        $script:ToolkitCatalogData = @{
            OperatingSystems = $releaseMatrix |
                Where-Object { $operatingSystems -contains $_.Name }
            Architectures    = $architectures
            UpdateTypes      = $updateTypes
        }

        Write-ToolkitLog -Message "Catalog data initialized: $($script:ToolkitCatalogData.OperatingSystems.Count) OS, $($architectures.Count) architectures, $($updateTypes.Count) update types" -Type Info -Source 'Get-ToolkitCatalogData'
    }

    return $script:ToolkitCatalogData
}
