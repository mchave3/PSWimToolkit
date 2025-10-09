function Get-WimApplicableUpdate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [Parameter()]
        [int[]] $Index,

        [Parameter()]
        [switch] $IncludePreview,

        [Parameter()]
        [switch] $AllPages,

        [Parameter()]
        [string] $Channel
    )

    begin {
        $resolvedInputs = @()
    }

    process {
        foreach ($item in $Path) {
            try {
                $resolvedInputs += Resolve-Path -Path $item -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "Unable to resolve WIM path '$item'. $($_.Exception.Message)" -Type Error -Source 'Get-WimApplicableUpdate'
            }
        }
    }

    end {
        foreach ($resolved in $resolvedInputs) {
            $wimPath = $resolved.ProviderPath
            $queryIndexes = $Index
            try {
                $wimInfos = if ($queryIndexes) {
                    Get-WimImageInfo -Path $wimPath -Index $queryIndexes -ErrorAction Stop
                } else {
                    Get-WimImageInfo -Path $wimPath -ErrorAction Stop
                }
            } catch {
                Write-ToolkitLog -Message "Failed to read WIM metadata for '$wimPath'. $($_.Exception.Message)" -Type Error -Source 'Get-WimApplicableUpdate'
                continue
            }

            foreach ($info in $wimInfos) {
                $catalogProfile = Resolve-WimCatalogProfile -WimInfo $info -PreferredChannel $Channel
                Write-ToolkitLog -Message ("Auto-detect using {0} {1} ({2}) for {3} [Index {4}]" -f $catalogProfile.OperatingSystem, $catalogProfile.Release, $catalogProfile.Architecture, $info.Path, $info.Index) -Type Stage -Source 'Get-WimApplicableUpdate'

                try {
                    $updates = Find-WindowsUpdate -OperatingSystem $catalogProfile.OperatingSystem -Version $catalogProfile.Release -Architecture $catalogProfile.Architecture -IncludePreview:$IncludePreview.IsPresent -AllPages:$AllPages.IsPresent -ErrorAction Stop
                } catch {
                    Write-ToolkitLog -Message ("Auto-detect catalog lookup failed for {0} {1}: {2}" -f $catalogProfile.OperatingSystem, $catalogProfile.Release, $_.Exception.Message) -Type Error -Source 'Get-WimApplicableUpdate'
                    continue
                }

                foreach ($update in $updates) {
                    [pscustomobject]@{
                        WimPath          = $info.Path
                        WimIndex         = $info.Index
                        WimName          = $info.Name
                        OperatingSystem  = $catalogProfile.OperatingSystem
                        Release          = $catalogProfile.Release
                        Architecture     = $catalogProfile.Architecture
                        Channel          = $catalogProfile.Channel
                        Update           = $update
                    }
                }
            }
        }
    }
}
