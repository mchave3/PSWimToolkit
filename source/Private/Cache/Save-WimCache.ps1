function Save-WimCache {
    <#
    .SYNOPSIS
        Saves WIM metadata to a cache file.

    .DESCRIPTION
        Serializes WimImage objects to a JSON cache file alongside the WIM file.
        The cache includes file size and last modified date for validation.

    .PARAMETER WimPath
        The full path to the WIM file.

    .PARAMETER WimImages
        Array of WimImage objects to cache.

    .EXAMPLE
        Save-WimCache -WimPath "C:\Images\Windows11.wim" -WimImages $images

    .OUTPUTS
        [bool] $true if cache was saved successfully, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WimPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [WimImage[]] $WimImages
    )

    try {
        $cacheFilePath = Get-WimCacheFilePath -WimPath $WimPath
        if (-not $cacheFilePath) {
            return $false
        }

        # Get WIM file info
        $wimFile = Get-Item -LiteralPath $WimPath -ErrorAction Stop

        # Build cache object
        $cacheData = [ordered]@{
            WimPath      = $WimPath
            FileSize     = $wimFile.Length
            LastModified = $wimFile.LastWriteTimeUtc.ToString('o')
            CacheVersion = '1.0'
            LastScanned  = (Get-Date).ToUniversalTime().ToString('o')
            Images       = @()
        }

        $imagesToPersist = $WimImages | Sort-Object -Property Index

        foreach ($img in $imagesToPersist) {
            $cacheData.Images += [ordered]@{
                Index        = $img.Index
                Name         = $img.Name
                Description  = $img.Description
                Version      = $img.Version.ToString()
                Size         = $img.Size
                Architecture = $img.Architecture
            }
        }

        # Save to JSON
        $json = $cacheData | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -LiteralPath $cacheFilePath -Value $json -Encoding UTF8 -ErrorAction Stop

        # Set hidden attribute on cache file
        try {
            $cacheFile = Get-Item -LiteralPath $cacheFilePath -ErrorAction Stop
            $cacheFile.Attributes = $cacheFile.Attributes -bor [System.IO.FileAttributes]::Hidden
        } catch {
            # Ignore if we can't set hidden attribute - not critical
            Write-ToolkitLog -Message "Could not set hidden attribute on cache file: $($_.Exception.Message)" -Type Debug -Source 'Save-WimCache'
        }

        Write-ToolkitLog -Message "Saved cache with $($WimImages.Count) image(s) for '$WimPath'" -Type Debug -Source 'Save-WimCache'
        return $true

    } catch [System.UnauthorizedAccessException] {
        Write-ToolkitLog -Message "No write permission to save cache for '$WimPath'. Cache will not be created." -Type Warning -Source 'Save-WimCache'
        return $false
    } catch {
        Write-ToolkitLog -Message "Failed to save cache for '$WimPath': $($_.Exception.Message)" -Type Warning -Source 'Save-WimCache'
        return $false
    }
}
