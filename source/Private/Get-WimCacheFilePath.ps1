function Get-WimCacheFilePath {
    <#
    .SYNOPSIS
        Returns the cache file path for a WIM file.

    .DESCRIPTION
        Generates the path to the JSON cache file that stores metadata for a given WIM file.
        The cache file is stored alongside the WIM with a hidden prefix.

    .PARAMETER WimPath
        The full path to the WIM file.

    .EXAMPLE
        Get-WimCacheFilePath -WimPath "C:\Images\Windows11.wim"
        Returns: C:\Images\.Windows11.wim.cache.json

    .OUTPUTS
        [string] The full path to the cache file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WimPath
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($WimPath)
        $directory = [System.IO.Path]::GetDirectoryName($fullPath)
        $fileName = [System.IO.Path]::GetFileName($fullPath)
        $cacheFileName = ".{0}.cache.json" -f $fileName

        return Join-Path -Path $directory -ChildPath $cacheFileName
    } catch {
        Write-ToolkitLog -Message "Failed to generate cache file path for '$WimPath': $($_.Exception.Message)" -Type Warning -Source 'Get-WimCacheFilePath'
        return $null
    }
}
