function Clear-WimCache {
    <#
    .SYNOPSIS
        Clears WIM metadata cache files.

    .DESCRIPTION
        Removes cache files (.cache.json) for WIM files. Can target specific WIM files
        or clean up orphaned cache files (cache files without corresponding WIM files).

    .PARAMETER Path
        Path to WIM file(s) or directory containing WIM files. Supports wildcards.
        If not specified, searches the default import directory.

    .PARAMETER RemoveOrphaned
        If specified, removes cache files that don't have a corresponding WIM file.

    .PARAMETER Recurse
        If specified, searches subdirectories for WIM files.

    .EXAMPLE
        Clear-WimCache -Path "C:\Images\*.wim"
        Removes cache files for all WIM files in C:\Images

    .EXAMPLE
        Clear-WimCache -RemoveOrphaned
        Removes orphaned cache files in the default import directory

    .EXAMPLE
        Clear-WimCache -Path "C:\Images" -Recurse
        Removes cache files for all WIM files in C:\Images and subdirectories

    .OUTPUTS
        [pscustomobject] Summary of removed cache files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [Parameter()]
        [switch] $RemoveOrphaned,

        [Parameter()]
        [switch] $Recurse
    )

    begin {
        $removedCount = 0
        $failedCount = 0
        $searchPaths = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Path) {
            foreach ($p in $Path) {
                $searchPaths.Add($p)
            }
        }
    }

    end {
        # If no path specified, use default import directory
        if ($searchPaths.Count -eq 0) {
            $defaultPath = Join-Path -Path (Get-ToolkitDataPath) -ChildPath 'Imports'
            if (Test-Path -LiteralPath $defaultPath -PathType Container) {
                $searchPaths.Add($defaultPath)
            } else {
                Write-ToolkitLog -Message "No paths specified and default import directory does not exist" -Type Warning -Source 'Clear-WimCache'
                return [pscustomobject]@{
                    RemovedCount = 0
                    FailedCount  = 0
                }
            }
        }

        foreach ($searchPath in $searchPaths) {
            try {
                $resolvedPaths = Resolve-Path -Path $searchPath -ErrorAction SilentlyContinue
                if (-not $resolvedPaths) {
                    Write-ToolkitLog -Message "Path not found: '$searchPath'" -Type Warning -Source 'Clear-WimCache'
                    continue
                }

                foreach ($resolvedPath in $resolvedPaths) {
                    $item = Get-Item -LiteralPath $resolvedPath.ProviderPath -ErrorAction Stop

                    if ($item.PSIsContainer) {
                        # Directory - find WIM files
                        $wimFiles = Get-ChildItem -Path $item.FullName -Filter '*.wim' -File -Recurse:$Recurse -ErrorAction SilentlyContinue
                        foreach ($wim in $wimFiles) {
                            if ($PSCmdlet.ShouldProcess($wim.FullName, "Remove cache")) {
                                if (Remove-WimCache -WimPath $wim.FullName) {
                                    $removedCount++
                                } else {
                                    $failedCount++
                                }
                            }
                        }

                        # Handle orphaned cache files if requested
                        if ($RemoveOrphaned) {
                            $cacheFiles = Get-ChildItem -Path $item.FullName -Filter '.*.wim.cache.json' -File -Recurse:$Recurse -ErrorAction SilentlyContinue
                            foreach ($cache in $cacheFiles) {
                                # Extract WIM filename from cache filename
                                $wimName = $cache.Name -replace '^\.' -replace '\.cache\.json$'
                                $wimPath = Join-Path -Path $cache.DirectoryName -ChildPath $wimName

                                if (-not (Test-Path -LiteralPath $wimPath -PathType Leaf)) {
                                    if ($PSCmdlet.ShouldProcess($cache.FullName, "Remove orphaned cache")) {
                                        try {
                                            Remove-Item -LiteralPath $cache.FullName -Force -ErrorAction Stop
                                            Write-ToolkitLog -Message "Removed orphaned cache: $($cache.FullName)" -Type Info -Source 'Clear-WimCache'
                                            $removedCount++
                                        } catch {
                                            Write-ToolkitLog -Message "Failed to remove orphaned cache '$($cache.FullName)': $($_.Exception.Message)" -Type Warning -Source 'Clear-WimCache'
                                            $failedCount++
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        # Single WIM file
                        if ($item.Extension -eq '.wim') {
                            if ($PSCmdlet.ShouldProcess($item.FullName, "Remove cache")) {
                                if (Remove-WimCache -WimPath $item.FullName) {
                                    $removedCount++
                                } else {
                                    $failedCount++
                                }
                            }
                        }
                    }
                }
            } catch {
                Write-ToolkitLog -Message "Error processing path '$searchPath': $($_.Exception.Message)" -Type Error -Source 'Clear-WimCache'
                $failedCount++
            }
        }

        Write-ToolkitLog -Message "Cache cleanup complete: $removedCount removed, $failedCount failed" -Type Info -Source 'Clear-WimCache'

        return [pscustomobject]@{
            RemovedCount = $removedCount
            FailedCount  = $failedCount
        }
    }
}
