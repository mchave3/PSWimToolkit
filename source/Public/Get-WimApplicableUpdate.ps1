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
        [string[]] $UpdateType = @('Cumulative Updates')
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
                Write-ToolkitLog -Message "Failed to gather WIM metadata for '$wimPath'. $($_.Exception.Message)" -Type Error -Source 'Get-WimApplicableUpdate'
                continue
            }

            foreach ($info in $wimInfos) {
                $catalogProfile = Resolve-WimCatalogProfile -WimInfo $info
                Write-ToolkitLog -Message ("Auto-detect using {0} {1} ({2}) for {3} [Index {4}]" -f $catalogProfile.OperatingSystem, $catalogProfile.Release, $catalogProfile.Architecture, $info.Path, $info.Index) -Type Stage -Source 'Get-WimApplicableUpdate'

                $params = @{
                    OperatingSystem = $catalogProfile.OperatingSystem
                    Version         = $catalogProfile.Release
                    Architecture    = $catalogProfile.Architecture
                    IncludePreview  = $IncludePreview.IsPresent
                    AllPages        = $AllPages.IsPresent
                    UpdateType      = $UpdateType
                    ErrorAction     = 'Stop'
                }

                try {
                    $updates = Find-WindowsUpdate @params
                } catch {
                    Write-ToolkitLog -Message ("Catalog lookup failed for {0} {1}: {2}" -f $catalogProfile.OperatingSystem, $catalogProfile.Release, $_.Exception.Message) -Type Error -Source 'Get-WimApplicableUpdate'
                    continue
                }

                if ($updates) {
                    foreach ($update in $updates) {
                        if (-not $update.OperatingSystem) {
                            $update.OperatingSystem = $catalogProfile.OperatingSystem
                        }
                        if (-not $update.Release) {
                            $update.Release = $catalogProfile.Release
                        }
                        if (-not $update.Architecture -and $catalogProfile.Architecture) {
                            $update.Architecture = $catalogProfile.Architecture
                        }
                        if (-not $update.UpdateTypeHint -and $UpdateType -and $UpdateType.Count -gt 0) {
                            $update.UpdateTypeHint = $UpdateType[0]
                        }
                    }
                }

                foreach ($update in $updates) {
                    [pscustomobject]@{
                        WimPath         = $info.Path
                        WimIndex        = $info.Index
                        WimName         = $info.Name
                        OperatingSystem = $catalogProfile.OperatingSystem
                        Release         = $catalogProfile.Release
                        Architecture    = $catalogProfile.Architecture
                        UpdateType      = $UpdateType
                        Update          = $update
                    }
                }
            }
        }
    }
}
