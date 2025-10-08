class CatalogUpdate {
    [string] $Title
    [string] $Products
    [string] $Classification
    [datetime] $LastUpdated
    [string] $Version
    [string] $Size
    [UInt64] $SizeInBytes
    [string] $Guid
    [string[]] $FileNames

    CatalogUpdate() {}

    CatalogUpdate([HtmlAgilityPack.HtmlNode] $Row, [bool] $IncludeFileNames) {
        if ($null -eq $Row) {
            throw [System.ArgumentNullException]::new('Row')
        }

        $cells = $Row.SelectNodes('td')
        if ($null -eq $cells -or $cells.Count -lt 8) {
            throw [System.InvalidOperationException]::new('Catalog update row is missing expected columns.')
        }

        $this.Title = $cells[1].InnerText.Trim()
        $this.Products = $cells[2].InnerText.Trim()
        $this.Classification = $cells[3].InnerText.Trim()
        $this.LastUpdated = Invoke-ParseDate -DateString $cells[4].InnerText.Trim()
        $this.Version = $cells[5].InnerText.Trim()

        $sizeNodes = $cells[6].SelectNodes('span')
        if ($sizeNodes.Count -ge 1) {
            $this.Size = $sizeNodes[0].InnerText.Trim()
        }
        if ($sizeNodes.Count -ge 2) {
            $sizeValue = $sizeNodes[1].InnerText.Trim()
            [void][UInt64]::TryParse($sizeValue, [ref]$this.SizeInBytes)
        }

        $guidNode = $cells[7].SelectNodes('input') | Select-Object -First 1
        if ($null -eq $guidNode) {
            throw [System.InvalidOperationException]::new('Unable to locate GUID input field in catalog row.')
        }

        $this.Guid = $guidNode.Id

        if ($IncludeFileNames) {
            try {
                $links = Get-UpdateLinks -Guid $this.Guid
                if ($links) {
                    $this.FileNames = $links | ForEach-Object { $_.URL.Split('/')[-1] }
                } else {
                    $this.FileNames = @()
                }
            } catch {
                $this.FileNames = @()
                Write-ToolkitLog -Message "CatalogUpdate failed to resolve filenames for GUID $($this.Guid): $($_.Exception.Message)" -Type Warning -Source 'CatalogUpdate'
            }
        }
    }

    [System.Collections.Generic.IEnumerable[pscustomobject]] GetDownloadLinks() {
        return Get-UpdateLinks -Guid $this.Guid
    }
}
