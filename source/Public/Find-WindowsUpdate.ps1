function Find-WindowsUpdate {
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    [OutputType([CatalogUpdate[]])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Search', Position = 0)]
        [string] $Search,

        [Parameter(Mandatory = $true, ParameterSetName = 'OperatingSystem')]
        [ValidateSet('Windows 11', 'Windows 10', 'Windows Server')]
        [string] $OperatingSystem,

        [Parameter(ParameterSetName = 'OperatingSystem')]
        [string] $Version,

        [Parameter()]
        [ValidateSet('All', 'x64', 'x86', 'ARM64')]
        [string] $Architecture = 'All',

        [Parameter()]
        [ValidateSet(
            'Cumulative',
            'Security',
            'Critical',
            'Feature',
            'Service Pack',
            'Tools',
            'Update Rollup',
            'Driver',
            'Security Quality'
        )]
        [string[]] $UpdateType,

        [switch] $AllPages,
        [switch] $IncludePreview,
        [switch] $ExcludeFramework,
        [switch] $IncludeFileNames
    )

    begin {
        $searchQuery = switch ($PSCmdlet.ParameterSetName) {
            'OperatingSystem' {
                $parts = @()
                $parts += $OperatingSystem
                if ($Version) { $parts += $Version }
                if ($Architecture -ne 'All') { $parts += "$Architecture-based" }
                if ($UpdateType) { $parts += $UpdateType }
                $parts -join ' '
            }
            default { $Search }
        }

        if (-not $searchQuery) {
            throw [System.ArgumentException]::new('A search query must be specified.')
        }

        Write-ToolkitLog -Message "Catalog search starting for '$searchQuery'." -Type Stage -Source 'Find-WindowsUpdate'
        $encodedQuery = [uri]::EscapeDataString($searchQuery)
        $baseUri = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encodedQuery"
        $responses = @()

        try {
            $response = Invoke-CatalogRequest -Uri $baseUri
            if ($null -eq $response) {
                Write-ToolkitLog -Message "No updates returned for '$searchQuery'." -Type Info -Source 'Find-WindowsUpdate'
                return
            }

            $responses += $response

            if ($AllPages) {
                $pageNumber = 1
                while ($response.HasNextPage() -and $pageNumber -lt 40) {
                    $pagedUri = "$baseUri&p=$pageNumber"
                    $response = Invoke-CatalogRequest -Uri $pagedUri
                    if ($response) {
                        $responses += $response
                    } else {
                        break
                    }
                    $pageNumber++
                }
            }
        } catch {
            Write-ToolkitLog -Message "Catalog search failed for '$searchQuery'. $($_.Exception.Message)" -Type Error -Source 'Find-WindowsUpdate'
            throw
        }

        $rows = $responses | ForEach-Object { $_.GetRows() }
        if (-not $rows) {
            Write-ToolkitLog -Message "No rows located for '$searchQuery'." -Type Info -Source 'Find-WindowsUpdate'
            return
        }

        $updates = foreach ($row in $rows) {
            try {
                [CatalogUpdate]::new($row, $IncludeFileNames.IsPresent)
            } catch {
                Write-ToolkitLog -Message "Failed to parse catalog row. $($_.Exception.Message)" -Type Warning -Source 'Find-WindowsUpdate'
            }
        }

        $updates = $updates | Where-Object { $_ }

        if ($PSCmdlet.ParameterSetName -eq 'OperatingSystem') {
            $updates = $updates | Where-Object {
                $_.Products -like "*$OperatingSystem*" -and
                (-not $Version -or $_.Title -like "*$Version*" -or $_.Products -like "*$Version*")
            }
        }

        if ($Architecture -ne 'All') {
            $updates = $updates | Where-Object {
                switch ($Architecture.ToLowerInvariant()) {
                    'x64' { $_.Title -match '(?i)x64|64-?bit|64-?based' -and $_.Title -notmatch '(?i)x86|32-?bit|arm64' }
                    'x86' { $_.Title -match '(?i)x86|32-?bit|32-?based' -and $_.Title -notmatch '(?i)x64|64-?bit|arm64' }
                    'arm64' { $_.Title -match '(?i)arm64|arm-?based' }
                }
            }
        }

        if ($UpdateType) {
            $updates = $updates | Where-Object {
                $classification = $_.Classification
                $title = $_.Title
                $match = $false
                foreach ($type in $UpdateType) {
                    switch ($type) {
                        'Cumulative' { if ($classification -like '*Cumulative*' -or $title -like '*Cumulative*') { $match = $true } }
                        'Security' { if ($classification -like '*Security*') { $match = $true } }
                        'Critical' { if ($classification -like '*Critical*') { $match = $true } }
                        'Feature' { if ($classification -like '*Feature*') { $match = $true } }
                        'Service Pack' { if ($classification -like '*Service Pack*') { $match = $true } }
                        'Tools' { if ($classification -like '*Tools*') { $match = $true } }
                        'Update Rollup' { if ($classification -like '*Rollup*') { $match = $true } }
                        'Driver' { if ($classification -like '*Driver*' -or $title -like '*Driver*') { $match = $true } }
                        'Security Quality' { if ($classification -like '*Security Quality*') { $match = $true } }
                    }
                }
                $match
            }
        }

        if (-not $IncludePreview) {
            $updates = $updates | Where-Object { $_.Title -notlike '*Preview*' }
        }

        if ($ExcludeFramework) {
            $updates = $updates | Where-Object { $_.Title -notlike '*Framework*' }
        }

        $updates = $updates | Sort-Object LastUpdated -Descending
        Write-ToolkitLog -Message ("Catalog search '{0}' returned {1} update(s)." -f $searchQuery, $updates.Count) -Type Success -Source 'Find-WindowsUpdate'
        $updates
    }
}
