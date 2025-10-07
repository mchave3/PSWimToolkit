function Invoke-CatalogRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [hashtable] $Body,

        [Parameter()]
        [ValidateSet('Get', 'Post')]
        [string] $Method = 'Get'
    )

    Initialize-HtmlParser

    $headers = @{
        'Cache-Control' = 'no-cache'
        'Pragma'        = 'no-cache'
        'User-Agent'    = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) PSWimToolkit/0.0.1'
    }

    $invokeParams = @{
        Uri             = $Uri
        Method          = $Method
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
        Headers         = $headers
    }

    if ($Method -eq 'Post') {
        $invokeParams['Body'] = $Body
        if (-not $invokeParams['ContentType']) {
            $invokeParams['ContentType'] = 'application/x-www-form-urlencoded'
        }
    }

    try {
        Set-SecurityProtocol
        Write-ProvisioningLog -Message "Submitting catalog request to $Uri ($Method)." -Type Debug -Source 'Invoke-CatalogRequest'
        $response = Invoke-WebRequest @invokeParams

        $htmlDoc = [HtmlAgilityPack.HtmlDocument]::new()
        $htmlDoc.LoadHtml($response.Content)

        $noResultsNode = $htmlDoc.GetElementbyId('ctl00_catalogBody_noResultText')
        $errorNode = $htmlDoc.GetElementbyId('errorPageDisplayedError')

        if ($null -eq $noResultsNode -and $null -eq $errorNode) {
            return [CatalogResponse]::new($htmlDoc)
        }

        if ($errorNode) {
            $message = $errorNode.InnerText.Trim()
            if ($message -match '8DDD0010') {
                throw [System.Exception]::new('Microsoft Update Catalog returned error code 8DDD0010. Please retry later.')
            }

            throw [System.Exception]::new("Microsoft Update Catalog error: $message")
        }

        Write-ProvisioningLog -Message "No catalog results for request $Uri." -Type Info -Source 'Invoke-CatalogRequest'
        return $null
    } catch {
        Write-ProvisioningLog -Message "Catalog request to $Uri failed. $($_.Exception.Message)" -Type Error -Source 'Invoke-CatalogRequest'
        throw
    } finally {
        Set-SecurityProtocol -ResetToDefault
    }
}
