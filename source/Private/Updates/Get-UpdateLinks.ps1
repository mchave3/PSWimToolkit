function Get-UpdateLinks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string] $Guid
    )

    if ([string]::IsNullOrWhiteSpace($Guid)) {
        throw [System.ArgumentException]::new('Update GUID must be provided.', 'Guid')
    }

    Write-ToolkitLog -Message "Resolving download links for GUID $Guid." -Type Debug -Source 'Get-UpdateLinks'

    $post = @{ size = 0; UpdateID = $Guid; UpdateIDInfo = $Guid } | ConvertTo-Json -Compress
    $body = @{ UpdateIDs = "[$post]" }

    $params = @{
        Uri             = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'
        Body            = $body
        ContentType     = 'application/x-www-form-urlencoded'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
        Method          = 'Post'
    }

    try {
        Set-SecurityProtocol
        $response = Invoke-WebRequest @params
        $content = $response.Content -replace 'www\.download\.windowsupdate', 'download.windowsupdate'

        $regexPrimary = "downloadInformation\[0\]\.files\[\d+\]\.url\s*=\s*'([^']*kb(\d+)[^']*)'"
        $matches = [regex]::Matches($content, $regexPrimary)

        if ($matches.Count -eq 0) {
            $regexFallback = "downloadInformation\[0\]\.files\[\d+\]\.url\s*=\s*'([^']*)'"
            $matches = [regex]::Matches($content, $regexFallback)
        }

        if ($matches.Count -eq 0) {
            Write-ToolkitLog -Message "No download links found for GUID $Guid." -Type Warning -Source 'Get-UpdateLinks'
            return @()
        }

        $links = foreach ($match in $matches) {
            [PSCustomObject]@{
                URL = $match.Groups[1].Value
                KB  = if ($match.Groups.Count -gt 2 -and $match.Groups[2].Success) { [int]$match.Groups[2].Value } else { 0 }
            }
        }

        return $links | Sort-Object KB -Descending
    } catch {
        Write-ToolkitLog -Message "Failed to retrieve download links for GUID $Guid. $_" -Type Error -Source 'Get-UpdateLinks'
        return @()
    } finally {
        Set-SecurityProtocol -ResetToDefault
    }
}
