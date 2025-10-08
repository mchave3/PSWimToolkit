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

                try {
                    $imageInfos = Get-WindowsImage -ImagePath $fileInfo.FullName -ErrorAction Stop
                } catch {
                    Write-ToolkitLog -Message ("Failed to read image metadata for {0}: {1}" -f $fileInfo.FullName, $_.Exception.Message) -Type Error -Source 'Get-WimImageInfo'
                    continue
                }

                $selectedInfos = if ($Index) {
                    $imageInfos | Where-Object { $Index -contains $_.ImageIndex }
                } else {
                    $imageInfos
                }

                foreach ($info in $selectedInfos) {
                    $wimImage = [WimImage]::new($fileInfo.FullName, $info.ImageIndex)
                    $wimImage.Name = $info.ImageName
                    $wimImage.Description = $info.ImageDescription
                    $wimImage.Version = [Version]$info.Version
                    $wimImage.Size = [UInt64]$info.ImageSize
                    $wimImage.Architecture = $info.ImageArchitecture

                    Write-ToolkitLog -Message ("Found Index {0} ({1}) in {2}" -f $wimImage.Index, $wimImage.Name, $fileInfo.FullName) -Type Info -Source 'Get-WimImageInfo'
                    Write-Output $wimImage
                }
            }
        }
    }
}
