function New-WimItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [int] $Index = 1
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    [pscustomobject]@{
        Name     = $name
        Path     = $Path
        Index    = $Index
        Status   = 'Pending'
        Details  = ''
        Metadata = $null
    }
}

function Get-WimMetadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [switch] $Refresh
    )

    $state = $Context.State
    $resolved = [System.IO.Path]::GetFullPath($Path)

    if (-not $Refresh.IsPresent -and $state.WimMetadataCache.ContainsKey($resolved)) {
        return $state.WimMetadataCache[$resolved]
    }

    try {
        $metadata = Get-WimImageInfo -Path $resolved -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Path         = $_.Path
                Index        = $_.Index
                Name         = $_.Name
                Architecture = $_.Architecture
                Version      = $_.Version.ToString()
                SizeGB       = [Math]::Round($_.Size / 1GB, 2)
                Description  = $_.Description
            }
        }
    } catch {
        Write-Warning "Failed to gather WIM metadata for $resolved : $($_.Exception.Message)"
        $metadata = @()
    }

    if ($metadata) {
        $state.WimMetadataCache[$resolved] = [System.Collections.Generic.List[psobject]]::new()
        foreach ($entry in $metadata) {
            $null = $state.WimMetadataCache[$resolved].Add($entry)
        }
    }

    return $metadata
}

function Refresh-WimItemDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Item,

        [Parameter()]
        [switch] $Force
    )

    if (-not $Item) {
        return
    }

    $metadata = Get-WimMetadata -Context $Context -Path $Item.Path -Refresh:$Force.IsPresent
    if (-not $metadata -or $metadata.Count -eq 0) {
        return
    }

    $primary = $metadata | Where-Object { $_.Index -eq $Item.Index } | Select-Object -First 1
    if (-not $primary) {
        $primary = $metadata | Select-Object -First 1
    }

    if (-not $primary) {
        return
    }

    $Item.Details = '{0} ({1})' -f $primary.Name, $primary.Architecture
    $Item.Metadata = $metadata
}

function Add-WimEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $wimItems = $Context.WimItems

    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
    } catch {
        Write-Warning "Unable to resolve WIM path '$Path': $($_.Exception.Message)"
        return $null
    }

    $existing = $wimItems | Where-Object {
        try {
            [System.IO.Path]::GetFullPath($_.Path) -eq $resolved
        } catch {
            $false
        }
    }

    if ($existing) {
        return $existing | Select-Object -First 1
    }

    $item = New-WimItem -Path $resolved
    $wimItems.Add($item) | Out-Null
    Refresh-WimItemDetails -Context $Context -Item $item -Force

    if ($item.Metadata -and $item.Metadata.Count -gt 0 -and -not $item.Index) {
        $item.Index = $item.Metadata[0].Index
    }

    return $item
}

function Copy-WimIntoImport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath
    )

    $state = $Context.State
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath

    if (-not (Test-Path -LiteralPath $state.ImportRoot -PathType Container)) {
        New-Item -Path $state.ImportRoot -ItemType Directory -Force | Out-Null
    }

    $importRootFull = [System.IO.Path]::GetFullPath($state.ImportRoot)
    $sourceFull = [System.IO.Path]::GetFullPath($resolvedSource)

    if ($sourceFull.StartsWith($importRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $sourceFull
    }

    $fileName = [System.IO.Path]::GetFileName($sourceFull)
    $destination = Join-Path -Path $importRootFull -ChildPath $fileName

    if (Test-Path -LiteralPath $destination) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        do {
            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $candidate = Join-Path -Path $importRootFull -ChildPath ("{0}_{1}{2}" -f $base, $timestamp, $extension)
        } while (Test-Path -LiteralPath $candidate)

        $destination = $candidate
    }

    Copy-Item -LiteralPath $sourceFull -Destination $destination -Force:$false -ErrorAction Stop
    return $destination
}

function Remove-WimEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Item,

        [Parameter()]
        [switch] $DeleteFile
    )

    $wimItems = $Context.WimItems
    $state = $Context.State
    $removed = $false

    if ($Item) {
        $removed = $wimItems.Remove($Item)
        $resolved = $null

        if ($Item.Path) {
            try {
                $resolved = [System.IO.Path]::GetFullPath($Item.Path)
            } catch {
                $resolved = $Item.Path
            }

            if ($resolved -and $state.WimMetadataCache.ContainsKey($resolved)) {
                $null = $state.WimMetadataCache.Remove($resolved)
            }

            if ($DeleteFile -and $resolved -and (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                $importRootFull = [System.IO.Path]::GetFullPath($state.ImportRoot)

                if ($resolved.StartsWith($importRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    try {
                        Remove-Item -LiteralPath $resolved -Force -ErrorAction Stop
                        Remove-WimCache -WimPath $resolved | Out-Null
                    } catch {
                        Write-Warning "Failed to delete WIM '$resolved': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    return $removed
}

function Load-WimsFromImport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $state = $Context.State

    if (-not (Test-Path -LiteralPath $state.ImportRoot -PathType Container)) {
        return
    }

    $existing = Get-ChildItem -Path $state.ImportRoot -Filter '*.wim' -File -Recurse -ErrorAction SilentlyContinue

    foreach ($entry in $existing) {
        Add-WimEntry -Context $Context -Path $entry.FullName | Out-Null
    }
}

function Get-SelectedWimItems {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $controls = $Context.Controls
    $wimItems = $Context.WimItems

    $selection = @($controls.WimGrid.SelectedItems)
    if ($selection.Count -eq 0) {
        return @($wimItems)
    }

    return $selection
}

function Show-WimDetailsDialog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [psobject[]] $Items,

        [Parameter()]
        [switch] $ForceRefresh
    )

    if (-not $Items -or $Items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one WIM entry to review details.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
        return
    }

    $dialogPath = Join-Path -Path $Context.GuiRoot -ChildPath 'WimDetailsDialog.xaml'

    if (-not (Test-Path -LiteralPath $dialogPath -PathType Leaf)) {
        throw "Unable to locate details dialog layout at $dialogPath."
    }

    [xml]$dialogXml = Get-Content -LiteralPath $dialogPath -Raw
    $dialogReader = New-Object System.Xml.XmlNodeReader $dialogXml
    $dialog = [Windows.Markup.XamlReader]::Load($dialogReader)
    $dialog.Owner = $Context.Window

    Add-SharedGuiStyles -Context $Context -Target $dialog

    $detailsControls = @{
        HeaderText     = $dialog.FindName('HeaderText')
        WimDetailsList = $dialog.FindName('WimDetailsList')
        StatusText     = $dialog.FindName('StatusText')
        CopyButton     = $dialog.FindName('CopyDetailsButton')
        RefreshButton  = $dialog.FindName('RefreshButton')
        CloseButton    = $dialog.FindName('CloseButton')
    }

    foreach ($key in $detailsControls.Keys) {
        if (-not $detailsControls[$key]) {
            throw "Unable to locate WIM details dialog control '$key'."
        }
    }

    $detailItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $detailsControls.WimDetailsList.ItemsSource = $detailItems

    function Populate-WimDetails {
        param (
            [psobject] $Context,
            [psobject[]] $Items,
            [System.Collections.ObjectModel.ObservableCollection[psobject]] $DetailItems,
            [hashtable] $Controls,
            [bool] $RefreshMetadata
        )

        $DetailItems.Clear()

        foreach ($item in $Items) {
            $metadata = Get-WimMetadata -Context $Context -Path $item.Path -Refresh:$RefreshMetadata

            foreach ($meta in $metadata) {
                $DetailItems.Add([pscustomobject]@{
                    Path         = $meta.Path
                    WimName      = [System.IO.Path]::GetFileName($meta.Path)
                    Index        = $meta.Index
                    Name         = $meta.Name
                    Architecture = $meta.Architecture
                    Version      = $meta.Version
                    SizeGB       = $meta.SizeGB
                    Description  = $meta.Description
                }) | Out-Null
            }
        }

        $Controls.HeaderText.Text = "WIM details for {0} selection(s)" -f $Items.Count
        $Controls.StatusText.Text = "Loaded $($DetailItems.Count) index record(s)."
    }

    Populate-WimDetails -Context $Context -Items $Items -DetailItems $detailItems -Controls $detailsControls -RefreshMetadata:$ForceRefresh.IsPresent

    $detailsControls.RefreshButton.Add_Click({
        Populate-WimDetails -Context $Context -Items $Items -DetailItems $detailItems -Controls $detailsControls -RefreshMetadata:$true
    })

    $detailsControls.CopyButton.Add_Click({
        $selection = @($detailsControls.WimDetailsList.SelectedItems)
        if ($selection.Count -eq 0) {
            $selection = @($detailItems)
        }

        if ($selection.Count -eq 0) { return }

        $payload = $selection | ForEach-Object {
            "Path: {0}`r`nIndex: {1}`r`nName: {2}`r`nArchitecture: {3}`r`nVersion: {4}`r`nSize (GB): {5}`r`nDescription: {6}" -f $_.Path, $_.Index, $_.Name, $_.Architecture, $_.Version, $_.SizeGB, $_.Description
        }

        [System.Windows.Clipboard]::SetText(($payload -join "`r`n`r`n"))
        $detailsControls.StatusText.Text = "Copied $($selection.Count) record(s) to clipboard."
    })

    $detailsControls.CloseButton.Add_Click({
        $dialog.Close()
    })

    $null = $dialog.ShowDialog()
}
