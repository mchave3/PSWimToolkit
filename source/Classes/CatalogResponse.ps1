class CatalogResponse {
    [HtmlAgilityPack.HtmlNode[]] $Rows
    [string] $EventArgument
    [string] $EventValidation
    [string] $ViewState
    [string] $ViewStateGenerator
    [string] $NextPage

    CatalogResponse([HtmlAgilityPack.HtmlDocument] $Document) {
        if ($null -eq $Document) {
            throw [System.ArgumentNullException]::new('Document')
        }

        $table = $Document.GetElementbyId('ctl00_catalogBody_updateMatches')
        if ($null -eq $table) {
            $this.Rows = @()
        } else {
            $this.Rows = $table.SelectNodes('tr') | Where-Object { $_.Id -and $_.Id -ne 'headerRow' }
        }

        $this.EventArgument = $Document.GetElementbyId('__EVENTARGUMENT')?.Attributes['value']?.Value
        $this.EventValidation = $Document.GetElementbyId('__EVENTVALIDATION')?.Attributes['value']?.Value
        $this.ViewState = $Document.GetElementbyId('__VIEWSTATE')?.Attributes['value']?.Value
        $this.ViewStateGenerator = $Document.GetElementbyId('__VIEWSTATEGENERATOR')?.Attributes['value']?.Value

        $nextPageNode = $Document.GetElementbyId('ctl00_catalogBody_nextPageLink')
        $this.NextPage = if ($nextPageNode) { $nextPageNode.InnerText.Trim() } else { $null }
    }

    [bool] HasNextPage() {
        return -not [string]::IsNullOrWhiteSpace($this.NextPage)
    }

    [HtmlAgilityPack.HtmlNode[]] GetRows() {
        return $this.Rows
    }
}
