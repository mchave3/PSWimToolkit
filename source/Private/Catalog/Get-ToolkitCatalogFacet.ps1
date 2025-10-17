function Get-ToolkitCatalogFacet {
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter()]
        [ValidateSet('All', 'OperatingSystems', 'Releases', 'Architectures', 'UpdateTypes')]
        [string] $Facet = 'All',

        [Parameter()]
        [string] $OperatingSystem,

        [Parameter()]
        [string] $Release
    )

    Write-ToolkitLog -Message "Retrieving catalog facet: $Facet" -Type Debug -Source 'Get-ToolkitCatalogFacet'

    $data = Get-ToolkitCatalogData

    switch ($Facet) {
        'OperatingSystems' {
            Write-ToolkitLog -Message "Returning $($data.OperatingSystems.Count) operating system(s)" -Type Info -Source 'Get-ToolkitCatalogFacet'
            return $data.OperatingSystems | Select-Object -Property Name, Releases
        }
        'Architectures' {
            Write-ToolkitLog -Message "Returning $($data.Architectures.Count) architecture(s)" -Type Info -Source 'Get-ToolkitCatalogFacet'
            return $data.Architectures
        }
        'UpdateTypes' {
            Write-ToolkitLog -Message "Returning $($data.UpdateTypes.Count) update type(s)" -Type Info -Source 'Get-ToolkitCatalogFacet'
            return $data.UpdateTypes
        }
        'Releases' {
            if ($OperatingSystem) {
                $osEntry = $data.OperatingSystems | Where-Object { $_.Name -eq $OperatingSystem } | Select-Object -First 1
                if ($osEntry) {
                    Write-ToolkitLog -Message "Returning $($osEntry.Releases.Count) release(s) for $OperatingSystem" -Type Info -Source 'Get-ToolkitCatalogFacet'
                    return $osEntry.Releases | Select-Object -Property Name, Query, Architectures, Build
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
                        Build           = $release.Build
                    }
                }
            }
            Write-ToolkitLog -Message "Returning $($releaseList.Count) total release(s)" -Type Info -Source 'Get-ToolkitCatalogFacet'
            return $releaseList
        }
        default {
            Write-ToolkitLog -Message "Returning all catalog facets" -Type Info -Source 'Get-ToolkitCatalogFacet'
            return [pscustomobject]@{
                OperatingSystems = $data.OperatingSystems
                Architectures    = $data.Architectures
                UpdateTypes      = $data.UpdateTypes
            }
        }
    }
}
