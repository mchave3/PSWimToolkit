function Initialize-HtmlParser {
    [CmdletBinding()]
    param ()

    if (-not ('HtmlAgilityPack.HtmlDocument' -as [type])) {
        $assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Types\netstandard2.0\HtmlAgilityPack.dll'
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("HtmlAgilityPack assembly not found at '$assemblyPath'.")
        }

        Add-Type -Path $assemblyPath
        Write-ProvisioningLog -Message 'HtmlAgilityPack assembly loaded by Initialize-HtmlParser.' -Type Debug -Source 'Initialize-HtmlParser'
    }
}
