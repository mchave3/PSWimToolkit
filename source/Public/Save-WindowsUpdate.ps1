function Save-WindowsUpdate {
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    [OutputType([UpdatePackage])]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByObject')]
        [CatalogUpdate] $InputObject,

        [Parameter(ParameterSetName = 'ByGuid', Mandatory = $true)]
        [string[]] $Guid,

        [Parameter()]
        [string] $Destination = (Get-Location).Path,

        [switch] $DownloadAll,
        [switch] $Force
    )

    begin {
        $resolvedDestination = Resolve-Path -LiteralPath $Destination -ErrorAction SilentlyContinue
        if (-not $resolvedDestination) {
            try {
                $resolvedDestination = New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop
                Write-ToolkitLog -Message "Created download directory at '$($resolvedDestination.FullName)'." -Type Info -Source 'Save-WindowsUpdate'
            } catch {
                Write-ToolkitLog -Message "Unable to create download directory '$Destination'. $($_.Exception.Message)" -Type Error -Source 'Save-WindowsUpdate'
                throw
            }
        }

        $script:Downloads = [System.Collections.Generic.List[CatalogUpdate]]::new()
        $script:Guids = [System.Collections.Generic.List[string]]::new()
        $script:DestinationPath = $resolvedDestination.ProviderPath
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject' -and $null -ne $InputObject) {
            $script:Downloads.Add($InputObject)
        }

        if ($Guid) {
            foreach ($item in $Guid) {
                if (-not [string]::IsNullOrWhiteSpace($item)) {
                    $script:Guids.Add($item)
                }
            }
        }
    }

    end {
        $targets = @()
        if ($script:Downloads.Count -gt 0) {
            $targets += $script:Downloads
        }

        if ($script:Guids.Count -gt 0) {
            foreach ($id in $script:Guids) {
                $targets += [CatalogUpdate]@{
                    Guid = $id
                    Title = "Update $id"
                }
            }
        }

        if (-not $targets) {
            Write-ToolkitLog -Message 'No updates to download.' -Type Warning -Source 'Save-WindowsUpdate'
            return
        }

        foreach ($update in $targets) {
            if (-not $update.Guid) {
                Write-ToolkitLog -Message "Skipping update without GUID: $($update.Title)" -Type Warning -Source 'Save-WindowsUpdate'
                continue
            }

            Write-ToolkitLog -Message "Retrieving download links for $($update.Title) ($($update.Guid))." -Type Stage -Source 'Save-WindowsUpdate'
            $links = Get-UpdateLinks -Guid $update.Guid
            if (-not $links) {
                Write-ToolkitLog -Message "No download links returned for $($update.Guid)." -Type Warning -Source 'Save-WindowsUpdate'
                continue
            }

            $selectedLinks = if ($DownloadAll) { $links } else { $links | Select-Object -First 1 }

            $total = $selectedLinks.Count
            $index = 0

            foreach ($link in $selectedLinks) {
                $index++
                $uri = $link.URL
                $fileName = $uri.Split('/')[-1]
                $destinationFile = Join-Path -Path $script:DestinationPath -ChildPath $fileName

                if ((Test-Path -LiteralPath $destinationFile) -and -not $Force) {
                    Write-ToolkitLog -Message "File '$fileName' already exists. Use -Force to re-download." -Type Info -Source 'Save-WindowsUpdate'
                    [UpdatePackage]::new($destinationFile, $link.KB)
                    continue
                }

                Write-Progress -Activity "Downloading $fileName" -Status "File $index of $total" -PercentComplete (($index / [double]$total) * 100)
                Write-ToolkitLog -Message "Downloading $fileName from $uri." -Type Info -Source 'Save-WindowsUpdate'

                try {
                    Set-SecurityProtocol
                    Invoke-WebRequest -Uri $uri -OutFile $destinationFile -UseBasicParsing -ErrorAction Stop
                    Write-ToolkitLog -Message "Download complete for $fileName." -Type Success -Source 'Save-WindowsUpdate'
                } catch {
                    Write-ToolkitLog -Message "Download failed for $fileName. $($_.Exception.Message)" -Type Error -Source 'Save-WindowsUpdate'
                    if (Test-Path -LiteralPath $destinationFile) {
                        Remove-Item -LiteralPath $destinationFile -Force -ErrorAction SilentlyContinue
                    }
                    continue
                } finally {
                    Set-SecurityProtocol -ResetToDefault
                    Write-Progress -Activity "Downloading $fileName" -Completed
                }

                try {
                    [UpdatePackage]::new($destinationFile, $link.KB)
                } catch {
                    Write-ToolkitLog -Message "Failed to create UpdatePackage for $fileName. $($_.Exception.Message)" -Type Warning -Source 'Save-WindowsUpdate'
                }
            }
        }
    }
}
