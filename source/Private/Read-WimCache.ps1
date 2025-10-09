function Read-WimCache {
    <#
    .SYNOPSIS
        Reads WIM metadata from a cache file.

    .DESCRIPTION
        Deserializes the JSON cache file and converts it back into WimImage objects.

    .PARAMETER CacheFilePath
        The full path to the cache JSON file.

    .EXAMPLE
        Read-WimCache -CacheFilePath "C:\Images\.Windows11.wim.cache.json"

    .OUTPUTS
        [WimImage[]] Array of WimImage objects from the cache.
    #>
    [CmdletBinding()]
    [OutputType([WimImage[]])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CacheFilePath
    )

    try {
        $cacheContent = Get-Content -LiteralPath $CacheFilePath -Raw -ErrorAction Stop
        $cache = $cacheContent | ConvertFrom-Json -ErrorAction Stop

        $wimImages = @()
        foreach ($img in $cache.Images) {
            $wimImage = [WimImage]::new($cache.WimPath, $img.Index)
            $wimImage.Name = $img.Name
            $wimImage.Description = $img.Description
            $wimImage.Version = [Version]$img.Version
            $wimImage.Size = [UInt64]$img.Size
            $wimImage.Architecture = $img.Architecture

            $wimImages += $wimImage
        }

        Write-ToolkitLog -Message "Loaded $($wimImages.Count) image(s) from cache for '$($cache.WimPath)'" -Type Debug -Source 'Read-WimCache'
        return $wimImages

    } catch {
        Write-ToolkitLog -Message "Failed to read cache from '$CacheFilePath': $($_.Exception.Message)" -Type Warning -Source 'Read-WimCache'
        return @()
    }
}
