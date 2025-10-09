function Remove-WimCache {
    <#
    .SYNOPSIS
        Removes the cache file associated with a WIM file.

    .DESCRIPTION
        Deletes the JSON cache file for a given WIM file. This should be called
        when a WIM file is deleted to clean up associated cache data.

    .PARAMETER WimPath
        The full path to the WIM file.

    .EXAMPLE
        Remove-WimCache -WimPath "C:\Images\Windows11.wim"

    .OUTPUTS
        [bool] $true if cache was removed successfully or didn't exist, $false on error.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WimPath
    )

    try {
        $cacheFilePath = Get-WimCacheFilePath -WimPath $WimPath
        if (-not $cacheFilePath) {
            return $true
        }

        if (Test-Path -LiteralPath $cacheFilePath -PathType Leaf) {
            Remove-Item -LiteralPath $cacheFilePath -Force -ErrorAction Stop
            Write-ToolkitLog -Message "Removed cache file for '$WimPath'" -Type Debug -Source 'Remove-WimCache'
        }

        return $true

    } catch {
        Write-ToolkitLog -Message "Failed to remove cache for '$WimPath': $($_.Exception.Message)" -Type Warning -Source 'Remove-WimCache'
        return $false
    }
}
