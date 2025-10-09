function Get-ToolkitCatalogFacet {
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter()]
        [ValidateSet('All', 'OperatingSystems', 'Releases', 'Architectures', 'Channels')]
        [string] $Facet = 'All',

        [Parameter()]
        [string] $OperatingSystem,

        [Parameter()]
        [string] $Release
    )

    $data = Get-ToolkitCatalogData

    switch ($Facet) {
        'OperatingSystems' {
            return $data.OperatingSystems | Select-Object -Property Name, Channels, Releases
        }
        'Architectures' {
            return $data.Architectures
        }
        'Channels' {
            return $data.Channels
        }
        'Releases' {
            if ($OperatingSystem) {
                $osEntry = $data.OperatingSystems | Where-Object { $_.Name -eq $OperatingSystem } | Select-Object -First 1
                if ($osEntry) {
                    return $osEntry.Releases | Select-Object -Property Name, Query, Architectures, BuildMin, BuildMax
                }
                Write-ToolkitLog -Message "No catalog facet releases found for operating system '$OperatingSystem'." -Type Warning -Source 'Get-ToolkitCatalogFacet'
                return @()
            }

            $releaseList = @()
            foreach ($os in $data.OperatingSystems) {
                foreach ($release in $os.Releases) {
                    $releaseList += [pscustomobject]@{
                        OperatingSystem = $os.Name
                        Name            = $release.Name
                        Query           = $release.Query
                        Architectures   = $release.Architectures
                        BuildMin        = $release.BuildMin
                        BuildMax        = $release.BuildMax
                    }
                }
            }
            return $releaseList
        }
        default {
            return [pscustomobject]@{
                OperatingSystems = $data.OperatingSystems
                Architectures    = $data.Architectures
                Channels         = $data.Channels
            }
        }
    }
}
