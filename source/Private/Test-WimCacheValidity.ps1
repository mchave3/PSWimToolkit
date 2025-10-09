function Test-WimCacheValidity {
    <#
    .SYNOPSIS
        Validates if a WIM cache file is still valid.

    .DESCRIPTION
        Checks if the cache file exists and if the cached metadata matches the current WIM file
        (file size and last modified date). Returns $true if cache is valid, $false otherwise.

    .PARAMETER WimPath
        The full path to the WIM file.

    .PARAMETER CacheFilePath
        The full path to the cache JSON file.

    .EXAMPLE
        Test-WimCacheValidity -WimPath "C:\Images\Windows11.wim" -CacheFilePath "C:\Images\.Windows11.wim.cache.json"

    .OUTPUTS
        [bool] $true if cache is valid, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WimPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CacheFilePath
    )

    # Check if cache file exists
    if (-not (Test-Path -LiteralPath $CacheFilePath -PathType Leaf)) {
        Write-ToolkitLog -Message "Cache file does not exist for '$WimPath'" -Type Debug -Source 'Test-WimCacheValidity'
        return $false
    }

    # Check if WIM file exists
    if (-not (Test-Path -LiteralPath $WimPath -PathType Leaf)) {
        Write-ToolkitLog -Message "WIM file does not exist: '$WimPath'" -Type Debug -Source 'Test-WimCacheValidity'
        return $false
    }

    try {
        # Read cache metadata
        $cacheContent = Get-Content -LiteralPath $CacheFilePath -Raw -ErrorAction Stop
        $cache = $cacheContent | ConvertFrom-Json -ErrorAction Stop

        # Get current WIM file info
        $wimFile = Get-Item -LiteralPath $WimPath -ErrorAction Stop

        # Validate cache version
        if (-not $cache.CacheVersion -or $cache.CacheVersion -ne '1.0') {
            Write-ToolkitLog -Message "Cache version mismatch or missing for '$WimPath'" -Type Debug -Source 'Test-WimCacheValidity'
            return $false
        }

        # Validate file size
        if ($cache.FileSize -ne $wimFile.Length) {
            Write-ToolkitLog -Message "Cache invalidated for '$WimPath': File size changed (cached: $($cache.FileSize), actual: $($wimFile.Length))" -Type Debug -Source 'Test-WimCacheValidity'
            return $false
        }

        # Validate last modified date (with 1 second tolerance for filesystem precision)
        $cachedLastModified = [DateTime]::Parse($cache.LastModified)
        $timeDiff = [Math]::Abs(($cachedLastModified - $wimFile.LastWriteTimeUtc).TotalSeconds)
        if ($timeDiff -gt 1) {
            Write-ToolkitLog -Message "Cache invalidated for '$WimPath': Last modified date changed" -Type Debug -Source 'Test-WimCacheValidity'
            return $false
        }

        Write-ToolkitLog -Message "Cache is valid for '$WimPath'" -Type Debug -Source 'Test-WimCacheValidity'
        return $true

    } catch {
        Write-ToolkitLog -Message "Failed to validate cache for '$WimPath': $($_.Exception.Message)" -Type Warning -Source 'Test-WimCacheValidity'
        return $false
    }
}
