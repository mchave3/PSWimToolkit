function Get-WimImageInfo {
    [CmdletBinding()]
    [OutputType([WimImage])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [Parameter()]
        [int[]] $Index
    )

    begin {
        if (-not (Get-Command -Name Get-WindowsImage -ErrorAction SilentlyContinue)) {
            try {
                Import-Module -Name Dism -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "Unable to import DISM module: $($_.Exception.Message)" -Type Error -Source 'Get-WimImageInfo'
                throw
            }
        }
    }

    process {
        foreach ($inputPath in $Path) {
            try {
                $resolvedPaths = Resolve-Path -Path $inputPath -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "WIM path '$inputPath' could not be resolved. $($_.Exception.Message)" -Type Error -Source 'Get-WimImageInfo'
                continue
            }

            foreach ($resolvedPath in $resolvedPaths) {
                $fileInfo = Get-Item -LiteralPath $resolvedPath.ProviderPath -ErrorAction Stop
                if ($fileInfo.PSIsContainer) {
                    Write-ToolkitLog -Message "Skipping directory '$($fileInfo.FullName)' when gathering WIM info." -Type Debug -Source 'Get-WimImageInfo'
                    continue
                }

                Write-ToolkitLog -Message ("Inspecting WIM image {0}" -f $fileInfo.FullName) -Type Stage -Source 'Get-WimImageInfo'

                # Try to load from cache first
                $cacheFilePath = Get-WimCacheFilePath -WimPath $fileInfo.FullName
                $useCache = $false
                $cachedImages = @()

                if ($cacheFilePath -and (Test-WimCacheValidity -WimPath $fileInfo.FullName -CacheFilePath $cacheFilePath)) {
                    $cachedImages = Read-WimCache -CacheFilePath $cacheFilePath
                    if ($cachedImages -and $cachedImages.Count -gt 0) {
                        $useCache = $true
                        Write-ToolkitLog -Message ("Loaded metadata from cache for {0} ({1} image(s))" -f $fileInfo.FullName, $cachedImages.Count) -Type Info -Source 'Get-WimImageInfo'
                    }
                }

                if ($useCache) {
                    # Use cached data
                    $imagesToOutput = if ($Index) {
                        $cachedImages | Where-Object { $Index -contains $_.Index }
                    } else {
                        $cachedImages
                    }

                    foreach ($wimImage in $imagesToOutput) {
                        Write-ToolkitLog -Message ("Found Index {0} ({1}) in {2} (from cache)" -f $wimImage.Index, $wimImage.Name, $fileInfo.FullName) -Type Info -Source 'Get-WimImageInfo'
                        Write-Output $wimImage
                    }
                } else {
                    # Cache invalid or missing - scan the WIM file
                    Write-ToolkitLog -Message ("Scanning WIM file {0} (cache unavailable or invalid)" -f $fileInfo.FullName) -Type Info -Source 'Get-WimImageInfo'

                    # First, get basic info to determine available indices
                    try {
                        $basicImageInfos = Get-WindowsImage -ImagePath $fileInfo.FullName -ErrorAction Stop
                    } catch {
                        Write-ToolkitLog -Message ("Failed to read image metadata for {0}: {1}" -f $fileInfo.FullName, $_.Exception.Message) -Type Error -Source 'Get-WimImageInfo'
                        continue
                    }

                    # Filter indices if specified
                    $indicesToProcess = if ($Index) {
                        $basicImageInfos | Where-Object { $Index -contains $_.ImageIndex } | Select-Object -ExpandProperty ImageIndex
                    } else {
                        $basicImageInfos | Select-Object -ExpandProperty ImageIndex
                    }

                    # Get detailed info for each index in parallel (PowerShell 7+)
                    # We collect results first, then log them to avoid module import issues in parallel runspaces
                    $wimFilePath = $fileInfo.FullName
                    $wimImages = $indicesToProcess | ForEach-Object -ThrottleLimit 5 -Parallel {
                        $imageIndex = $_
                        $wimPath = $using:wimFilePath

                        try {
                            # Get-WindowsImage with -Index returns detailed WimImageInfoObject
                            $detailedInfo = Get-WindowsImage -ImagePath $wimPath -Index $imageIndex -ErrorAction Stop

                            # Create a simple object to return (avoid class constructor issues in parallel)
                            [PSCustomObject]@{
                                Path            = $wimPath
                                Index           = $imageIndex
                                Name            = $detailedInfo.ImageName
                                Description     = $detailedInfo.ImageDescription
                                MajorVersion    = $detailedInfo.MajorVersion
                                MinorVersion    = $detailedInfo.MinorVersion
                                Build           = $detailedInfo.Build
                                SPBuild         = $detailedInfo.SPBuild
                                Size            = $detailedInfo.ImageSize
                                Architecture    = $detailedInfo.Architecture
                                Success         = $true
                                Error           = $null
                            }
                        } catch {
                            [PSCustomObject]@{
                                Path    = $wimPath
                                Index   = $imageIndex
                                Success = $false
                                Error   = $_.Exception.Message
                            }
                        }
                    }

                    # Process results and create WimImage objects with proper logging
                    $scannedImages = @()
                    foreach ($result in $wimImages) {
                        if ($result.Success) {
                            # Skip refresh because metadata is set manually from collected details
                            $wimImage = [WimImage]::new($result.Path, $result.Index, $true)
                            $wimImage.Name = $result.Name
                            $wimImage.Description = $result.Description
                            $versionString = "{0}.{1}.{2}.{3}" -f $result.MajorVersion, $result.MinorVersion, $result.Build, $result.SPBuild
                            $wimImage.Version = [Version]$versionString
                            $wimImage.Size = [UInt64]$result.Size
                            $wimImage.Architecture = $result.Architecture

                            $scannedImages += $wimImage

                            Write-ToolkitLog -Message ("Found Index {0} ({1}) in {2}" -f $wimImage.Index, $wimImage.Name, $result.Path) -Type Info -Source 'Get-WimImageInfo'
                            Write-Output $wimImage
                        } else {
                            Write-ToolkitLog -Message ("Failed to read detailed metadata for index {0} in {1}: {2}" -f $result.Index, $result.Path, $result.Error) -Type Error -Source 'Get-WimImageInfo'
                        }
                    }

                    # Save to cache for future use (only if we scanned all indices)
                    if (-not $Index -and $scannedImages.Count -gt 0) {
                        $null = Save-WimCache -WimPath $fileInfo.FullName -WimImages $scannedImages
                    }
                }
            }
        }
    }
}
