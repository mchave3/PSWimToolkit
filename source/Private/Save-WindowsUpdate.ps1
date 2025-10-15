function Save-WindowsUpdate {
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    [OutputType([UpdatePackage])]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByObject')]
        [CatalogUpdate] $InputObject,

        [Parameter(ParameterSetName = 'ByGuid', Mandatory = $true)]
        [string[]] $Guid,

        [Parameter()]
        [string] $Destination,

        [Parameter()]
        [string] $OperatingSystem,

        [Parameter()]
        [string] $Release,

        [Parameter()]
        [string] $UpdateType,

        [switch] $DownloadAll,
        [switch] $Force
    )

    function Resolve-UpdateDestinationFolder {
        param (
            [Parameter()]
            [CatalogUpdate] $Update
        )

        if ($script:ExplicitDestination) {
            return $script:DestinationPath
        }

        $osName = if ($OperatingSystem) {
            $OperatingSystem
        } elseif ($Update -and $Update.OperatingSystem) {
            $Update.OperatingSystem
        } else {
            'General'
        }

        $releaseName = if ($Release) {
            $Release
        } elseif ($Update -and $Update.Release) {
            $Update.Release
        } else {
            'Unspecified'
        }

        $typeName = if ($UpdateType) {
            $UpdateType
        } elseif ($Update -and $Update.UpdateTypeHint) {
            $Update.UpdateTypeHint
        } elseif ($Update -and $Update.Classification) {
            $Update.Classification
        } else {
            'Updates'
        }

        $updatePath = Resolve-ToolkitUpdatePath -OperatingSystem $osName -Release $releaseName -UpdateType $typeName -Ensure
        if ($Update) {
            if (-not $Update.OperatingSystem) { $Update.OperatingSystem = $osName }
            if (-not $Update.Release) { $Update.Release = $releaseName }
            if (-not $Update.UpdateTypeHint) { $Update.UpdateTypeHint = $typeName }
        }

        return $updatePath
    }

    begin {
        $script:DownloadTargets = [System.Collections.Generic.List[CatalogUpdate]]::new()
        $script:TargetGuids = [System.Collections.Generic.List[string]]::new()
        $script:ExplicitDestination = $false

        try {
            if ($Destination) {
                if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
                    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
                    Write-ToolkitLog -Message "Created download directory at '$Destination'." -Type Info -Source 'Save-WindowsUpdate'
                }
                $script:DestinationPath = (Resolve-Path -LiteralPath $Destination).ProviderPath
                $script:ExplicitDestination = $true
            } else {
                $script:DestinationPath = Get-ToolkitUpdatesRoot
            }
        } catch {
            Write-ToolkitLog -Message "Cannot prepare download directory '$Destination'. $($_.Exception.Message)" -Type Error -Source 'Save-WindowsUpdate'
            throw
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject' -and $InputObject) {
            $script:DownloadTargets.Add($InputObject)
        }

        if ($Guid) {
            foreach ($id in $Guid) {
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $script:TargetGuids.Add($id.Trim())
                }
            }
        }
    }

    end {
        $targets = @()
        if ($script:DownloadTargets.Count -gt 0) {
            $targets += $script:DownloadTargets
        }

        if ($script:TargetGuids.Count -gt 0) {
            foreach ($id in $script:TargetGuids) {
                $targets += [CatalogUpdate]@{
                    Title = "Update $id"
                    Guid  = $id
                }
            }
        }

        if (-not $targets) {
            Write-ToolkitLog -Message 'No updates provided to Save-WindowsUpdate.' -Type Warning -Source 'Save-WindowsUpdate'
            return
        }

        $packages = @()
        foreach ($update in $targets) {
            if (-not $update.Guid) {
                Write-ToolkitLog -Message "Skipping catalog entry without GUID ($($update.Title))." -Type Warning -Source 'Save-WindowsUpdate'
                continue
            }

            Write-ToolkitLog -Message "Resolving download links for GUID $($update.Guid)." -Type Stage -Source 'Save-WindowsUpdate'
            $links = Get-UpdateLinks -Guid $update.Guid
            if (-not $links -or $links.Count -eq 0) {
                Write-ToolkitLog -Message "No download links returned for $($update.Guid)." -Type Warning -Source 'Save-WindowsUpdate'
                continue
            }

            $selectedLinks = if ($DownloadAll) { $links } else { $links | Select-Object -First 1 }
            $linkIndex = 0
            $totalLinks = $selectedLinks.Count
            $resolvedFolder = Resolve-UpdateDestinationFolder -Update $update
            if (-not (Test-Path -LiteralPath $resolvedFolder -PathType Container)) {
                try {
                    New-Item -Path $resolvedFolder -ItemType Directory -Force | Out-Null
                } catch {
                    Write-ToolkitLog -Message "Unable to create update workspace '$resolvedFolder'. $($_.Exception.Message)" -Type Error -Source 'Save-WindowsUpdate'
                    continue
                }
            }

            foreach ($link in $selectedLinks) {
                $linkIndex++
                $uri = $link.URL
                $fileName = $uri.Split('/')[-1]
                $targetPath = Join-Path -Path $resolvedFolder -ChildPath $fileName

                if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
                    Write-ToolkitLog -Message "Skipping existing file '$fileName'. Use -Force to overwrite." -Type Info -Source 'Save-WindowsUpdate'
                    try {
                        $packages += [UpdatePackage]::new($targetPath, $link.KB)
                    } catch {
                        Write-ToolkitLog -Message "Failed to register existing package '$fileName': $($_.Exception.Message)" -Type Debug -Source 'Save-WindowsUpdate'
                    }
                    continue
                }

                Write-Progress -Activity "Downloading $fileName" -Status "File $linkIndex of $totalLinks" -PercentComplete (($linkIndex / [double]$totalLinks) * 100)
                Write-ToolkitLog -Message "Downloading $fileName from $uri." -Type Info -Source 'Save-WindowsUpdate'

                try {
                    Set-SecurityProtocol
                    Invoke-WebRequest -Uri $uri -OutFile $targetPath -UseBasicParsing -ErrorAction Stop
                    Write-ToolkitLog -Message "Completed download for $fileName." -Type Success -Source 'Save-WindowsUpdate'
                    try {
                        $packages += [UpdatePackage]::new($targetPath, $link.KB)
                    } catch {
                        Write-ToolkitLog -Message "Failed to initialize UpdatePackage for $fileName. $($_.Exception.Message)" -Type Warning -Source 'Save-WindowsUpdate'
                    }
                } catch {
                    Write-ToolkitLog -Message "Download failed for $fileName. $($_.Exception.Message)" -Type Error -Source 'Save-WindowsUpdate'
                    if (Test-Path -LiteralPath $targetPath) {
                        Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                    }
                } finally {
                    Set-SecurityProtocol -ResetToDefault
                    Write-Progress -Activity "Downloading $fileName" -Completed
                }
            }
        }

        if ($packages.Count -gt 0) {
            $destinationNote = if ($script:ExplicitDestination) { $script:DestinationPath } else { Get-ToolkitUpdatesRoot }
            Write-ToolkitLog -Message ("Saved {0} update file(s) to {1}." -f $packages.Count, $destinationNote) -Type Success -Source 'Save-WindowsUpdate'
            $packages
        } else {
            Write-ToolkitLog -Message 'No update packages were downloaded.' -Type Warning -Source 'Save-WindowsUpdate'
        }
    }
}
