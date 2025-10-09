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

                # Get detailed info for each index
                $wimFilePath = $fileInfo.FullName
                $indicesToProcess | ForEach-Object -ThrottleLimit 5 -Parallel {
                    $imageIndex = $_
                    $wimPath = $using:wimFilePath

                    try {
                        # Get-WindowsImage with -Index returns detailed WimImageInfoObject
                        $detailedInfo = Get-WindowsImage -ImagePath $wimPath -Index $imageIndex -ErrorAction Stop

                        $wimImage = [WimImage]::new($wimPath, $imageIndex)
                        $wimImage.Name = $detailedInfo.ImageName
                        $wimImage.Description = $detailedInfo.ImageDescription
                        $versionString = "{0}.{1}.{2}.{3}" -f $detailedInfo.MajorVersion, $detailedInfo.MinorVersion, $detailedInfo.Build, $detailedInfo.SPBuild
                        $wimImage.Version = [Version]$versionString
                        $wimImage.Size = [UInt64]$detailedInfo.ImageSize
                        $wimImage.Architecture = $detailedInfo.Architecture

                        Write-ToolkitLog -Message ("Found Index {0} ({1}) in {2}" -f $wimImage.Index, $wimImage.Name, $wimPath) -Type Info -Source 'Get-WimImageInfo'
                        Write-Output $wimImage
                    } catch {
                        Write-ToolkitLog -Message ("Failed to read detailed metadata for index {0} in {1}: {2}" -f $imageIndex, $wimPath, $_.Exception.Message) -Type Error -Source 'Get-WimImageInfo'
                    }
                }
            }
        }
    }
}
