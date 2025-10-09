function Import-WimFromIso {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [Parameter()]
        [string] $Destination = (Join-Path -Path (Get-ToolkitDataPath) -ChildPath 'Imports'),

        [Parameter()]
        [switch] $SkipEsdConversion,

        [Parameter()]
        [switch] $Force
    )

    begin {
        if (-not (Test-Path -LiteralPath $Destination)) {
            $null = New-Item -ItemType Directory -Path $Destination -Force
        }

        if (-not (Get-Command -Name Mount-DiskImage -ErrorAction SilentlyContinue)) {
            throw 'Mount-DiskImage is not available on this system. Import the Storage module or use a supported Windows build.'
        }

        if (-not (Get-Command -Name Get-Volume -ErrorAction SilentlyContinue)) {
            throw 'Get-Volume is required to resolve mounted ISO volumes. Import the Storage module on Windows 10/11.'
        }

        $results = [System.Collections.Generic.List[psobject]]::new()
    }

    process {
        foreach ($item in $Path) {
            try {
                $resolvedIso = Resolve-Path -Path $item -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "ISO path '$item' could not be resolved. $($_.Exception.Message)" -Type Error -Source 'Import-WimFromIso'
                continue
            }

            $isoPath = $resolvedIso.ProviderPath
            Write-ToolkitLog -Message "Mounting ISO $isoPath for WIM extraction." -Type Stage -Source 'Import-WimFromIso'

            $diskImage = $null
            $mountedVolumes = $null
            try {
                $diskImage = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
                Start-Sleep -Milliseconds 300
                $mountedVolumes = Get-Volume -DiskImage $diskImage -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "Failed to mount ISO $isoPath. $($_.Exception.Message)" -Type Error -Source 'Import-WimFromIso'
                if ($diskImage) {
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
                }
                continue
            }

            try {
                $volumeRoot = $mountedVolumes | Select-Object -First 1
                if (-not $volumeRoot) {
                    throw "No volume discovered after mounting $isoPath."
                }

                $drivePrefix = if ($volumeRoot.DriveLetter) {
                    '{0}:\' -f $volumeRoot.DriveLetter
                } elseif ($volumeRoot.Path) {
                    $volumeRoot.Path
                } else {
                    throw "Unable to determine mount point for $isoPath."
                }

                $sourcesPath = Join-Path -Path $drivePrefix -ChildPath 'sources'
                $wimFiles = Get-ChildItem -LiteralPath $sourcesPath -Filter '*.wim' -File -ErrorAction SilentlyContinue
                $esdFiles = Get-ChildItem -LiteralPath $sourcesPath -Filter '*.esd' -File -ErrorAction SilentlyContinue

                $copied = @()

                if ($wimFiles -and $wimFiles.Count -gt 0) {
                    foreach ($wim in $wimFiles) {
                        $targetName = '{0}_{1}' -f ([System.IO.Path]::GetFileNameWithoutExtension($isoPath)), $wim.Name
                        $targetPath = Join-Path -Path $Destination -ChildPath $targetName
                        if (-not $Force -and (Test-Path -LiteralPath $targetPath)) {
                            $uniqueName = '{0}_{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($targetPath), (Get-Date -Format 'yyyyMMddHHmmss'), [System.IO.Path]::GetExtension($targetPath)
                            $targetPath = Join-Path -Path $Destination -ChildPath $uniqueName
                        }
                        Copy-Item -LiteralPath $wim.FullName -Destination $targetPath -Force:$Force.IsPresent
                        Write-ToolkitLog -Message "Copied $($wim.Name) to $targetPath." -Type Info -Source 'Import-WimFromIso'
                        $copied += [pscustomobject]@{
                            IsoPath       = $isoPath
                            Source        = $wim.FullName
                            Destination   = $targetPath
                            SourceType    = 'WIM'
                        }
                    }
                }

                if (-not $copied -and $esdFiles -and $esdFiles.Count -gt 0) {
                    foreach ($esd in $esdFiles) {
                        $targetName = '{0}_{1}.wim' -f ([System.IO.Path]::GetFileNameWithoutExtension($isoPath)), [System.IO.Path]::GetFileNameWithoutExtension($esd.Name)
                        $targetPath = Join-Path -Path $Destination -ChildPath $targetName
                        if (-not $Force -and (Test-Path -LiteralPath $targetPath)) {
                            $targetPath = Join-Path -Path $Destination -ChildPath ("$([System.IO.Path]::GetFileNameWithoutExtension($targetName))_{0}.wim" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                        }

                        if ($SkipEsdConversion) {
                            $esdTarget = $targetPath.Replace('.wim', '.esd')
                            Copy-Item -LiteralPath $esd.FullName -Destination $esdTarget -Force:$Force.IsPresent
                            Write-ToolkitLog -Message "Copied $($esd.Name) to $esdTarget (conversion skipped)." -Type Info -Source 'Import-WimFromIso'
                            $copied += [pscustomobject]@{
                                IsoPath       = $isoPath
                                Source        = $esd.FullName
                                Destination   = $esdTarget
                                SourceType    = 'ESD'
                            }
                            continue
                        }

                        if (-not (Get-Command -Name Export-WindowsImage -ErrorAction SilentlyContinue)) {
                            Import-Module -Name Dism -ErrorAction Stop
                        }

                        $images = Get-WindowsImage -ImagePath $esd.FullName -ErrorAction Stop
                        $first = $true
                        foreach ($image in $images) {
                            $exportParams = @{
                                SourceImagePath      = $esd.FullName
                                SourceIndex          = $image.ImageIndex
                                DestinationImagePath = $targetPath
                                DestinationName      = $image.ImageName
                                Compression          = 'Max'
                                CheckIntegrity       = $true
                            }
                            if (-not $first) {
                                $exportParams['Append'] = $true
                            }

                            Export-WindowsImage @exportParams | Out-Null
                            $first = $false
                        }

                        Write-ToolkitLog -Message "Converted $($esd.Name) to multi-index WIM at $targetPath." -Type Info -Source 'Import-WimFromIso'
                        $copied += [pscustomobject]@{
                            IsoPath       = $isoPath
                            Source        = $esd.FullName
                            Destination   = $targetPath
                            SourceType    = 'ESD'
                        }
                    }
                }

                if (-not $copied) {
                    Write-ToolkitLog -Message "No WIM or ESD images located under $sourcesPath." -Type Warning -Source 'Import-WimFromIso'
                } else {
                    foreach ($entry in $copied) {
                        $results.Add($entry)
                    }
                }
            } finally {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            return $results.ToArray()
        }
    }
}
