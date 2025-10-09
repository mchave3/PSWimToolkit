function Find-WindowsUpdate {
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    [OutputType([CatalogUpdate[]])]
    param (
        [Parameter()]
        [ValidateSet('All', 'x64', 'x86', 'arm64')]
        [string] $Architecture = 'All',

        [Parameter()]
        [switch] $Descending,

        [Parameter()]
        [switch] $ExcludeFramework,

        [Parameter()]
        [datetime] $FromDate,

        [Parameter()]
        [ValidateSet('Default', 'CSV', 'JSON', 'XML')]
        [string] $Format = 'Default',

        [Parameter()]
        [switch] $GetFramework,

        [Parameter()]
        [switch] $AllPages,

        [Parameter()]
        [switch] $IncludeDynamic,

        [Parameter()]
        [switch] $IncludeFileNames,

        [Parameter()]
        [switch] $IncludePreview,

        [Parameter()]
        [int] $LastDays,

        [Parameter()]
        [double] $MaxSize,

        [Parameter()]
        [double] $MinSize,

        [Parameter(Mandatory, ParameterSetName = 'OperatingSystem')]
        [ValidateSet('Windows 11', 'Windows 10', 'Windows Server')]
        [string] $OperatingSystem,

        [Parameter()]
        [string[]] $Properties,

        [Parameter(Mandatory, ParameterSetName = 'Search', Position = 0)]
        [string] $Search,

        [Parameter()]
        [ValidateSet('MB', 'GB')]
        [string] $SizeUnit = 'MB',

        [Parameter()]
        [ValidateSet('Date', 'Size', 'Title', 'Classification', 'Product')]
        [string] $SortBy = 'Date',

        [Parameter()]
        [switch] $Strict,

        [Parameter()]
        [datetime] $ToDate,

        [Parameter()]
        [ValidateSet(
            'Security Updates',
            'Updates',
            'Critical Updates',
            'Feature Packs',
            'Service Packs',
            'Tools',
            'Update Rollups',
            'Cumulative Updates',
            'Security Quality Updates',
            'Driver Updates'
        )]
        [string[]] $UpdateType,

        [Parameter(ParameterSetName = 'OperatingSystem')]
        [string] $Version
    )

    begin {
        if (-not ('CatalogUpdate' -as [type])) {
            $classPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Classes\CatalogUpdate.ps1'
            if (Test-Path -LiteralPath $classPath -PathType Leaf) {
                . $classPath
            } else {
                throw "CatalogUpdate class file not found at: $classPath"
            }
        }

        $globalUpdates = @()
        $searchContext = switch ($PSCmdlet.ParameterSetName) {
            'OperatingSystem' {
                $parts = @($OperatingSystem)
                if ($Version) { $parts += $Version }
                if ($Architecture -and $Architecture -ne 'All') { $parts += "$Architecture-based" }
                if ($UpdateType) { $parts += $UpdateType }
                $parts -join ' '
            }
            default { $Search }
        }

        if (-not $searchContext) {
            throw [System.ArgumentException]::new('A search term or operating system must be supplied.')
        }

        $encodedSearch = if ($Strict) {
            [uri]::EscapeDataString('"' + $searchContext + '"')
        } elseif ($GetFramework) {
            [uri]::EscapeDataString("*$searchContext*")
        } else {
            [uri]::EscapeDataString($searchContext)
        }

        $baseUri = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encodedSearch"
        Write-ToolkitLog -Message "Submitting catalog query '$searchContext'." -Type Stage -Source 'Find-WindowsUpdate'
    }

    process {
        $response = Invoke-CatalogRequest -Uri $baseUri
        if (-not $response) {
            Write-ToolkitLog -Message "Catalog returned no data for '$searchContext'." -Type Info -Source 'Find-WindowsUpdate'
            return
        }

        $rows = @()
        if ($response.Rows) { $rows += $response.Rows }

        if ($AllPages) {
            $pageCount = 0
            while ($response.HasNextPage() -and $pageCount -lt 39) {
                $pageCount++
                $pageUri = "$baseUri&p=$pageCount"
                $response = Invoke-CatalogRequest -Uri $pageUri
                if (-not $response) { break }
                if ($response.Rows) { $rows += $response.Rows }
            }
        }

        if (-not $rows -or $rows.Count -eq 0) {
            Write-ToolkitLog -Message "No catalog rows discovered for '$searchContext'." -Type Info -Source 'Find-WindowsUpdate'
            return
        }

        $filteredRows = @()
        foreach ($row in $rows) {
            $cells = $row.SelectNodes('td')
            if (-not $cells -or $cells.Count -lt 8) { continue }

            $title = $cells[1].InnerText.Trim()
            $classification = $cells[3].InnerText.Trim()

            $include = $true
            if (-not $IncludeDynamic -and $title -like '*Dynamic*') { $include = $false }
            if (-not $IncludePreview -and $title -like '*Preview*') { $include = $false }

            if ($GetFramework -and $title -notlike '*Framework*') { $include = $false }
            if ($ExcludeFramework -and $title -like '*Framework*') { $include = $false }

            if ($PSCmdlet.ParameterSetName -eq 'OperatingSystem') {
                if ($OperatingSystem -eq 'Windows Server') {
                    if (($title -notlike '*Microsoft*Server*') -and ($title -notlike '*Server Operating System*')) {
                        $include = $false
                    }
                } elseif ($title -notlike "*$OperatingSystem*") {
                    $include = $false
                }

                if ($Version -and $title -notlike "*$Version*") {
                    $include = $false
                }
            }

            if ($include -and $UpdateType -and $UpdateType.Count -gt 0) {
                $matched = $false
                foreach ($type in $UpdateType) {
                    switch ($type) {
                        'Security Updates' {
                            if ($classification -eq 'Security Updates') { $matched = $true }
                        }
                        'Cumulative Updates' {
                            if ($title -like '*Cumulative Update*') { $matched = $true }
                        }
                        'Critical Updates' {
                            if ($classification -eq 'Critical Updates') { $matched = $true }
                        }
                        'Updates' {
                            if ($classification -eq 'Updates') { $matched = $true }
                        }
                        'Feature Packs' {
                            if ($classification -eq 'Feature Packs') { $matched = $true }
                        }
                        'Service Packs' {
                            if ($classification -eq 'Service Packs') { $matched = $true }
                        }
                        'Tools' {
                            if ($classification -eq 'Tools') { $matched = $true }
                        }
                        'Update Rollups' {
                            if ($classification -eq 'Update Rollups') { $matched = $true }
                        }
                        'Security Quality Updates' {
                            if ($classification -eq 'Security Updates' -and $title -like '*Quality*') { $matched = $true }
                        }
                        'Driver Updates' {
                            if ($title -like '*Driver*') { $matched = $true }
                        }
                        default {
                            if ($title -like "*$type*") { $matched = $true }
                        }
                    }
                    if ($matched) { break }
                }
                if (-not $matched) { $include = $false }
            }

            if ($include) { $filteredRows += $row }
        }

        if ($Architecture -and $Architecture -ne 'All') {
            $architectureValue = $Architecture.ToLowerInvariant()
            $architectureRows = @()
            foreach ($row in $filteredRows) {
                $cells = $row.SelectNodes('td')
                if (-not $cells -or $cells.Count -lt 2) { continue }
                $title = $cells[1].InnerText.Trim()
                $match = switch ($architectureValue) {
                    'x64' { ($title -match 'x64|64.?bit|64.?based') -and ($title -notmatch 'x86|32.?bit|arm64') }
                    'x86' { ($title -match 'x86|32.?bit|32.?based') -and ($title -notmatch '64.?bit|arm64') }
                    'arm64' { $title -match 'arm64|arm.?based' }
                    default { $true }
                }
                if ($match) { $architectureRows += $row }
            }
            $filteredRows = $architectureRows
        }

        $updates = @()
        foreach ($row in $filteredRows) {
            try {
                $updates += [CatalogUpdate]::new($row, $IncludeFileNames.IsPresent)
            } catch {
                Write-ToolkitLog -Message "Failed to parse catalog row: $($_.Exception.Message)" -Type Warning -Source 'Find-WindowsUpdate'
            }
        }

        $updates = $updates | Where-Object { $_ }

        if ($FromDate) {
            $updates = $updates | Where-Object { $_.LastUpdated -ge $FromDate }
        }
        if ($ToDate) {
            $updates = $updates | Where-Object { $_.LastUpdated -le $ToDate }
        }
        if ($LastDays) {
            $cutoff = (Get-Date).AddDays(-1 * [math]::Abs($LastDays))
            $updates = $updates | Where-Object { $_.LastUpdated -ge $cutoff }
        }

        if ($MinSize -or $MaxSize) {
            $sizeMultiplier = if ($SizeUnit -eq 'GB') { 1024 } else { 1 }
            $updates = $updates | Where-Object {
                $sizeInMb = ConvertTo-ToolkitSizeInMb $_.Size
                $meetsMin = (-not $MinSize) -or ($sizeInMb -ge ($MinSize * $sizeMultiplier))
                $meetsMax = (-not $MaxSize) -or ($sizeInMb -le ($MaxSize * $sizeMultiplier))
                $meetsMin -and $meetsMax
            }
        }

        switch ($SortBy) {
            'Date' { $updates = $updates | Sort-Object LastUpdated -Descending:$Descending.IsPresent }
            'Size' { $updates = $updates | Sort-Object { ConvertTo-ToolkitSizeInMb $_.Size } -Descending:$Descending.IsPresent }
            'Title' { $updates = $updates | Sort-Object Title -Descending:$Descending.IsPresent }
            'Classification' { $updates = $updates | Sort-Object Classification -Descending:$Descending.IsPresent }
            'Product' { $updates = $updates | Sort-Object Products -Descending:$Descending.IsPresent }
        }

        if ($updates) {
            foreach ($update in $updates) {
                if (-not $update) { continue }

                if ($PSCmdlet.ParameterSetName -eq 'OperatingSystem') {
                    if ($OperatingSystem) { $update.OperatingSystem = $OperatingSystem }
                    if ($Version) { $update.Release = $Version }
                }

                if (-not $update.Architecture -and $Architecture -and $Architecture -ne 'All') {
                    $update.Architecture = $Architecture
                }

                if (-not $update.UpdateTypeHint) {
                    if ($UpdateType -and $UpdateType.Count -eq 1) {
                        $update.UpdateTypeHint = $UpdateType[0]
                    } elseif ($update.Classification) {
                        $update.UpdateTypeHint = $update.Classification
                    }
                }
            }
        }

        $globalUpdates += $updates
    }

    end {
        $globalUpdates = @($globalUpdates | Sort-Object LastUpdated -Descending)
        $count = $globalUpdates.Count
        Write-ToolkitLog -Message ("Catalog search '{0}' produced {1} matching update(s)." -f $searchContext, $count) -Type Success -Source 'Find-WindowsUpdate'

        switch ($Format) {
            'CSV' {
                if ($Properties) {
                    $globalUpdates | Select-Object $Properties | ConvertTo-Csv -NoTypeInformation
                } else {
                    $globalUpdates | ConvertTo-Csv -NoTypeInformation
                }
            }
            'JSON' {
                if ($Properties) {
                    $globalUpdates | Select-Object $Properties | ConvertTo-Json -Depth 6
                } else {
                    $globalUpdates | ConvertTo-Json -Depth 6
                }
            }
            'XML' {
                if ($Properties) {
                    $globalUpdates | Select-Object $Properties | ConvertTo-Xml -As String -Depth 6
                } else {
                    $globalUpdates | ConvertTo-Xml -As String -Depth 6
                }
            }
            default {
                if ($Properties) {
                    $globalUpdates | Select-Object $Properties
                } else {
                    $globalUpdates
                }
            }
        }
    }
}

function ConvertTo-ToolkitSizeInMb {
    param (
        [Parameter(Mandatory)]
        [string] $SizeString
    )

    if ([string]::IsNullOrWhiteSpace($SizeString)) {
        return 0
    }

    $normalized = $SizeString.Trim()
    if ($normalized -match '([\d\.,]+)\s*(KB|MB|GB)') {
        $numericValue = $matches[1].Replace(',', '')
        $value = [double]::Parse($numericValue, [System.Globalization.CultureInfo]::InvariantCulture)
        switch ($matches[2].ToUpperInvariant()) {
            'KB' { return $value / 1024 }
            'GB' { return $value * 1024 }
            default { return $value }
        }
    }

    return 0
}
