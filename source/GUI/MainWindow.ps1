function Show-PSWimToolkitMainWindow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $ModulePath
    )

    if (-not $IsWindows) {
        throw 'The provisioning GUI is only supported on Windows platforms.'
    }

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        throw 'Start-PSWimToolkit must be invoked from an STA thread. Launch PowerShell with -STA and retry.'
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    Add-Type -AssemblyName System.Windows.Forms

    $xamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        throw "Unable to locate GUI layout at $xamlPath."
    }

    [xml]$xamlContent = Get-Content -LiteralPath $xamlPath -Raw
    $xamlReader = New-Object System.Xml.XmlNodeReader $xamlContent
    $window = [Windows.Markup.XamlReader]::Load($xamlReader)

    $stylesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Styles.xaml'
    if (Test-Path -LiteralPath $stylesPath -PathType Leaf) {
        try {
            [xml]$stylesContent = Get-Content -LiteralPath $stylesPath -Raw
            $stylesReader = New-Object System.Xml.XmlNodeReader $stylesContent
            $stylesDictionary = [Windows.Markup.XamlReader]::Load($stylesReader)
            $window.Resources.MergedDictionaries.Add($stylesDictionary)
        } catch {
            Write-Warning "Failed to load GUI styles: $($_.Exception.Message)"
        }
    }

    $controls = @{
        OpenConfigMenuItem    = $window.FindName('OpenConfigMenuItem')
        SaveConfigMenuItem    = $window.FindName('SaveConfigMenuItem')
        ExitMenuItem          = $window.FindName('ExitMenuItem')
        DownloadUpdatesMenuItem = $window.FindName('DownloadUpdatesMenuItem')
        ClearLogsMenuItem     = $window.FindName('ClearLogsMenuItem')
        ExportLogsMenuItem    = $window.FindName('ExportLogsMenuItem')
        ToggleLogViewMenuItem = $window.FindName('ToggleLogViewMenuItem')
        AboutMenuItem         = $window.FindName('AboutMenuItem')
        DocumentationMenuItem = $window.FindName('DocumentationMenuItem')
        AddWimButton          = $window.FindName('AddWimButton')
        ImportIsoButton       = $window.FindName('ImportIsoButton')
        WimDetailsButton      = $window.FindName('WimDetailsButton')
        RemoveWimButton       = $window.FindName('RemoveWimButton')
        DeleteWimButton       = $window.FindName('DeleteWimButton')
        ClearWimButton        = $window.FindName('ClearWimButton')
        WimGrid               = $window.FindName('WimGrid')
        UpdatePathTextBox     = $window.FindName('UpdatePathTextBox')
        BrowseUpdateButton    = $window.FindName('BrowseUpdateButton')
        SxSPathTextBox        = $window.FindName('SxSPathTextBox')
        BrowseSxSButton       = $window.FindName('BrowseSxSButton')
        OutputPathTextBox     = $window.FindName('OutputPathTextBox')
        BrowseOutputButton    = $window.FindName('BrowseOutputButton')
        EnableNetFxCheckBox   = $window.FindName('EnableNetFxCheckBox')
        ForceCheckBox         = $window.FindName('ForceCheckBox')
        VerboseLogCheckBox    = $window.FindName('VerboseLogCheckBox')
        IncludePreviewCheckBox = $window.FindName('IncludePreviewCheckBox')
        AutoDetectButton      = $window.FindName('AutoDetectButton')
        SearchCatalogButton   = $window.FindName('SearchCatalogButton')
        StartButton           = $window.FindName('StartButton')
        StopButton            = $window.FindName('StopButton')
        ThrottleSlider        = $window.FindName('ThrottleSlider')
        ThrottleValueText     = $window.FindName('ThrottleValueText')
        StatusTextBlock       = $window.FindName('StatusTextBlock')
        OverallProgressBar    = $window.FindName('OverallProgressBar')
        ProgressList          = $window.FindName('ProgressList')
        LogLevelComboBox      = $window.FindName('LogLevelComboBox')
        LogList               = $window.FindName('LogList')
        AutoScrollCheckBox    = $window.FindName('AutoScrollCheckBox')
        SaveLogsButton        = $window.FindName('SaveLogsButton')
        ClearLogsButton       = $window.FindName('ClearLogsButton')
        OpenLogFolderButton   = $window.FindName('OpenLogFolderButton')
        LogPathTextBlock      = $window.FindName('LogPathTextBlock')
        LogViewerGroup        = $window.FindName('LogViewerGroup')
    }

    foreach ($key in $controls.Keys) {
        if (-not $controls[$key]) {
            throw "Unable to locate expected GUI control '$key'."
        }
    }

    # Maximize the window at startup and force it to surface in the foreground
    $window.WindowState = [System.Windows.WindowState]::Maximized
    $window.Add_ContentRendered({
        param($sender, $eventArgs)
        $sender.Topmost = $true
        $sender.Activate()
        $sender.Topmost = $false
    })

    $stopBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38))
    $controls.StopButton.Background = $stopBrush
    $controls.StopButton.BorderBrush = $stopBrush

    $wimItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $controls.WimGrid.ItemsSource = $wimItems
    $controls.ProgressList.ItemsSource = $wimItems

    $logItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $controls.LogList.ItemsSource = $logItems

    $logItemStyle = $window.Resources['LogListViewItemStyle']
    if ($null -ne $logItemStyle) {
        $controls.LogList.ItemContainerStyle = $logItemStyle
    }

    $moduleInfo = Get-Module -Name PSWimToolkit | Select-Object -First 1
    $moduleVersion = if ($moduleInfo) { $moduleInfo.Version.ToString() } else { 'Unknown' }
    $workspaceRoot = Get-ToolkitDataPath
    $mountRoot = $script:WorkspacePaths.Mounts
    $logRoot = $script:WorkspacePaths.Logs
    $importRoot = $script:WorkspacePaths.Imports
    $updatesRoot = Get-ToolkitUpdatesRoot
    $sxsRoot = Get-ToolkitDataPath -Child 'SxS'
    $outputRoot = Get-ToolkitDataPath -Child 'Output'

    $state = [pscustomobject]@{
        Job               = $null
        Timer             = $null
        LogRoot           = $null
        KnownLogEntries   = [System.Collections.Generic.HashSet[string]]::new()
        AllLogData        = [System.Collections.Generic.List[psobject]]::new()
        ModulePath        = $ModulePath
        ModuleVersion     = $moduleVersion
        MountRoot         = $mountRoot
        LogBase           = $logRoot
        ImportRoot        = $importRoot
        UpdatesRoot       = $updatesRoot
        SxSRoot           = $sxsRoot
        OutputRoot        = $outputRoot
        WimMetadataCache  = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[psobject]]]::new()
        CatalogFacets     = $null
    }

    if (-not (Test-Path -LiteralPath $state.MountRoot)) {
        New-Item -Path $state.MountRoot -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $state.LogBase)) {
        New-Item -Path $state.LogBase -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $state.ImportRoot)) {
        New-Item -Path $state.ImportRoot -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $state.SxSRoot)) {
        New-Item -Path $state.SxSRoot -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $state.OutputRoot)) {
        New-Item -Path $state.OutputRoot -ItemType Directory -Force | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($controls.UpdatePathTextBox.Text)) {
        $controls.UpdatePathTextBox.Text = $state.UpdatesRoot
    }

    if ([string]::IsNullOrWhiteSpace($controls.SxSPathTextBox.Text)) {
        $controls.SxSPathTextBox.Text = $state.SxSRoot
    }

    if ([string]::IsNullOrWhiteSpace($controls.OutputPathTextBox.Text)) {
        $controls.OutputPathTextBox.Text = $state.OutputRoot
    }

    function Invoke-UiAction {
        param (
            [System.Windows.Threading.Dispatcher] $Dispatcher,
            [scriptblock] $Action
        )

        if ($Dispatcher.CheckAccess()) {
            & $Action
        } else {
            $Dispatcher.Invoke($Action)
        }
    }

    function New-WimItem {
        param (
            [string] $Path,
            [int] $Index = 1
        )

        $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        [pscustomobject]@{
            Name    = $name
            Path    = $Path
            Index   = $Index
            Status  = 'Pending'
            Details = ''
            Metadata = $null
        }
    }

    function Open-FolderPath {
        param (
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $DisplayName
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            [System.Windows.MessageBox]::Show("No path configured for $DisplayName.", 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }

        $resolvedPath = $Path
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                New-Item -Path $Path -ItemType Directory -Force | Out-Null
            }
            $resolvedPath = [System.IO.Path]::GetFullPath($Path)
        } catch {
            [System.Windows.MessageBox]::Show("Unable to prepare $DisplayName folder: $($_.Exception.Message)", 'PSWimToolkit', 'OK', 'Error') | Out-Null
            return
        }

        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList @("`"$resolvedPath`"") -WindowStyle Normal | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Unable to open $DisplayName folder: $($_.Exception.Message)", 'PSWimToolkit', 'OK', 'Error') | Out-Null
        }
    }

    function Get-WimMetadata {
        param (
            [Parameter(Mandatory)]
            [string] $Path,
            [switch] $Refresh
        )

        $resolved = [System.IO.Path]::GetFullPath($Path)
        if (-not $Refresh -and $state.WimMetadataCache.ContainsKey($resolved)) {
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
                $state.WimMetadataCache[$resolved].Add($entry) | Out-Null
            }
        }

        return $metadata
    }

    function Refresh-WimItemDetails {
        param (
            [psobject] $Item,
            [switch] $Force
        )

        if (-not $Item) { return }
        $metadata = Get-WimMetadata -Path $Item.Path -Refresh:$Force.IsPresent
        if ($metadata -and $metadata.Count -gt 0) {
            $primary = $metadata | Where-Object { $_.Index -eq $Item.Index } | Select-Object -First 1
            if (-not $primary) { $primary = $metadata | Select-Object -First 1 }
            if ($primary) {
                $Item.Details = "{0} ({1})" -f $primary.Name, $primary.Architecture
                $Item.Metadata = $metadata
            }
        }
    }

    function Add-WimEntry {
        param (
            [Parameter(Mandatory)]
            [string] $Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

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
        $wimItems.Add($item)
        Refresh-WimItemDetails -Item $item -Force
        if ($item.Metadata -and $item.Metadata.Count -gt 0 -and -not $item.Index) {
            $item.Index = $item.Metadata[0].Index
        }
        return $item
    }

    function Copy-WimIntoImport {
        param (
            [Parameter(Mandatory)]
            [string] $SourcePath
        )

        $resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath
        $importRoot = $state.ImportRoot
        if (-not (Test-Path -LiteralPath $importRoot -PathType Container)) {
            New-Item -Path $importRoot -ItemType Directory -Force | Out-Null
        }

        $importRootFull = [System.IO.Path]::GetFullPath($importRoot)
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
                $timestamp = (Get-Date -Format 'yyyyMMddHHmmss')
                $candidate = Join-Path -Path $importRootFull -ChildPath ("{0}_{1}{2}" -f $base, $timestamp, $extension)
            } while (Test-Path -LiteralPath $candidate)
            $destination = $candidate
        }

        Copy-Item -LiteralPath $sourceFull -Destination $destination -Force:$false -ErrorAction Stop
        return $destination
    }

    function Remove-WimEntry {
        param (
            [Parameter(Mandatory)]
            [psobject] $Item,
            [switch] $DeleteFile
        )

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
                            # Also remove the cache file if it exists
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
        $importRoot = $state.ImportRoot
        if (-not (Test-Path -LiteralPath $importRoot -PathType Container)) {
            return
        }

        $existing = Get-ChildItem -Path $importRoot -Filter '*.wim' -File -Recurse -ErrorAction SilentlyContinue
        foreach ($entry in $existing) {
            Add-WimEntry -Path $entry.FullName | Out-Null
        }
    }

    function Get-SelectedWimItems {
        $selection = @($controls.WimGrid.SelectedItems)
        if ($selection.Count -eq 0) {
            return @($wimItems)
        }
        return $selection
    }

    function Update-Status {
        param (
            [string] $Message,
            [Windows.Media.Brush] $Brush = $(New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x2B,0x57,0x9A)))
        )

        Invoke-UiAction -Dispatcher $window.Dispatcher -Action {
            $controls.StatusTextBlock.Text = $Message
            $controls.StatusTextBlock.Foreground = $Brush
        }
    }

    function Refresh-ThrottleText {
        param (
            [double] $Value
        )
        $controls.ThrottleValueText.Text = [Math]::Round($Value).ToString()
    }

    function Reset-LogCollections {
        $state.KnownLogEntries.Clear() | Out-Null
        $state.AllLogData.Clear()
        $logItems.Clear()
        Update-LogView
    }

    function Save-LogsToFile {
        param (
            [Parameter(Mandatory)]
            [string] $Destination
        )

        if ($state.AllLogData.Count -eq 0) {
            return
        }

        $lines = $state.AllLogData | Sort-Object Timestamp | ForEach-Object {
            '[{0}] [{1}] [{2}] {3}' -f $_.Timestamp, $_.Level, $_.Source, $_.Message
        }

        Set-Content -LiteralPath $Destination -Value $lines -Encoding UTF8
    }

    function Load-Configuration {
        param (
            [Parameter(Mandatory)]
            [string] $Path
        )

        try {
            $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 6 -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load configuration: $($_.Exception.Message)", 'PSWimToolkit', 'OK', 'Error') | Out-Null
            return
        }

        $wimItems.Clear()
        if ($config.WimFiles) {
            foreach ($entry in $config.WimFiles) {
                if (-not $entry.Path) { continue }
                $indexValue = if ($entry.Index) { [int]$entry.Index } else { 1 }
                $item = New-WimItem -Path $entry.Path -Index $indexValue
                Refresh-WimItemDetails -Item $item -Force
                $wimItems.Add($item)
            }
        }
        $controls.WimGrid.Items.Refresh()
        $controls.ProgressList.Items.Refresh()

        if ($config.UpdatePath) { $controls.UpdatePathTextBox.Text = $config.UpdatePath } else { $controls.UpdatePathTextBox.Text = $state.UpdatesRoot }
        if ($config.SxSPath) { $controls.SxSPathTextBox.Text = $config.SxSPath } else { $controls.SxSPathTextBox.Text = $state.SxSRoot }
        if ($config.OutputPath) { $controls.OutputPathTextBox.Text = $config.OutputPath } else { $controls.OutputPathTextBox.Text = $state.OutputRoot }

        $controls.EnableNetFxCheckBox.IsChecked = $config.EnableNetFx3
        $controls.ForceCheckBox.IsChecked = $config.Force
        $controls.VerboseLogCheckBox.IsChecked = $config.Verbose
        $controls.IncludePreviewCheckBox.IsChecked = $config.IncludePreview

        if ($config.ThrottleLimit) {
            $controls.ThrottleSlider.Value = [Math]::Min([Math]::Max([double]$config.ThrottleLimit, $controls.ThrottleSlider.Minimum), $controls.ThrottleSlider.Maximum)
        }

        Refresh-ThrottleText -Value $controls.ThrottleSlider.Value
        Update-Status -Message "Configuration loaded from $Path"
    }

    function Save-Configuration {
        param (
            [Parameter(Mandatory)]
            [string] $Path
        )

        $config = [pscustomobject]@{
            UpdatePath    = $controls.UpdatePathTextBox.Text
            SxSPath       = $controls.SxSPathTextBox.Text
            OutputPath    = $controls.OutputPathTextBox.Text
            EnableNetFx3  = [bool]$controls.EnableNetFxCheckBox.IsChecked
            Force         = [bool]$controls.ForceCheckBox.IsChecked
            Verbose       = [bool]$controls.VerboseLogCheckBox.IsChecked
            IncludePreview = [bool]$controls.IncludePreviewCheckBox.IsChecked
            ThrottleLimit = [int][Math]::Round($controls.ThrottleSlider.Value)
            WimFiles      = $wimItems | ForEach-Object {
                [pscustomobject]@{
                    Path  = $_.Path
                    Index = $_.Index
                }
            }
        }

        $json = $config | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
        Update-Status -Message "Configuration saved to $Path"
    }

    function Show-WimDetailsDialog {
        param (
            [Parameter(Mandatory)]
            [psobject[]] $Items,
            [switch] $ForceRefresh
        )

        if (-not $Items -or $Items.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Select at least one WIM entry to review details.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }

        $detailsXamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'WimDetailsDialog.xaml'
        if (-not (Test-Path -LiteralPath $detailsXamlPath -PathType Leaf)) {
            throw "Unable to locate details dialog layout at $detailsXamlPath."
        }

        [xml]$detailsXml = Get-Content -LiteralPath $detailsXamlPath -Raw
        $detailsReader = New-Object System.Xml.XmlNodeReader $detailsXml
        $dialog = [Windows.Markup.XamlReader]::Load($detailsReader)
        $dialog.Owner = $window

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
                [bool] $RefreshMetadata
            )

            $detailItems.Clear()
            foreach ($item in $Items) {
                $metadata = Get-WimMetadata -Path $item.Path -Refresh:$RefreshMetadata
                foreach ($meta in $metadata) {
                    $detailItems.Add([pscustomobject]@{
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

            $detailsControls.HeaderText.Text = "WIM details for {0} selection(s)" -f $Items.Count
            $detailsControls.StatusText.Text = "Loaded $($detailItems.Count) index record(s)."
        }

        Populate-WimDetails -RefreshMetadata:$ForceRefresh.IsPresent

        $detailsControls.RefreshButton.Add_Click({
            Populate-WimDetails -RefreshMetadata:$true
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

    function Show-CatalogDialog {
        $catalogXamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'CatalogDialog.xaml'
        if (-not (Test-Path -LiteralPath $catalogXamlPath -PathType Leaf)) {
            throw "Unable to locate catalog dialog layout at $catalogXamlPath."
        }

        [xml]$catalogXml = Get-Content -LiteralPath $catalogXamlPath -Raw
        $catalogReader = New-Object System.Xml.XmlNodeReader $catalogXml
        $dialog = [Windows.Markup.XamlReader]::Load($catalogReader)
        $dialog.Owner = $window

        $catalogControls = @{
            SearchTextBox           = $dialog.FindName('SearchTextBox')
            SearchButton            = $dialog.FindName('SearchButton')
            OperatingSystemComboBox = $dialog.FindName('OperatingSystemComboBox')
            ReleaseComboBox         = $dialog.FindName('ReleaseComboBox')
            ArchitectureComboBox    = $dialog.FindName('ArchitectureComboBox')
            UpdateTypeComboBox      = $dialog.FindName('UpdateTypeComboBox')
            AllPagesCheckBox        = $dialog.FindName('AllPagesCheckBox')
            IncludePreviewCheckBox  = $dialog.FindName('IncludePreviewCheckBox')
            IncludeDynamicCheckBox  = $dialog.FindName('IncludeDynamicCheckBox')
            GetFrameworkCheckBox    = $dialog.FindName('GetFrameworkCheckBox')
            ExcludeFrameworkCheckBox = $dialog.FindName('ExcludeFrameworkCheckBox')
            StrictCheckBox          = $dialog.FindName('StrictCheckBox')
            IncludeFileNamesCheckBox = $dialog.FindName('IncludeFileNamesCheckBox')
            LastDaysTextBox         = $dialog.FindName('LastDaysTextBox')
            MinSizeTextBox          = $dialog.FindName('MinSizeTextBox')
            MaxSizeTextBox          = $dialog.FindName('MaxSizeTextBox')
            SizeUnitComboBox        = $dialog.FindName('SizeUnitComboBox')
            ResultsList             = $dialog.FindName('ResultsList')
            DownloadButton          = $dialog.FindName('DownloadButton')
            CopyButton              = $dialog.FindName('CopyButton')
            CloseButton             = $dialog.FindName('CloseButton')
            StatusText              = $dialog.FindName('CatalogStatusText')
        }

        foreach ($key in $catalogControls.Keys) {
            if (-not $catalogControls[$key]) {
                throw "Unable to locate catalog dialog control '$key'."
            }
        }

        if (-not $state.CatalogFacets) {
            $state.CatalogFacets = Get-ToolkitCatalogData
        }

        $catalogControls.IncludePreviewCheckBox.IsChecked = $controls.IncludePreviewCheckBox.IsChecked

        $operatingSystems = $state.CatalogFacets.OperatingSystems
        $architectures = @('All') + $state.CatalogFacets.Architectures
        $updateTypes = @('Any') + $state.CatalogFacets.UpdateTypes

        $catalogControls.OperatingSystemComboBox.Items.Clear()
        foreach ($os in $operatingSystems) {
            $null = $catalogControls.OperatingSystemComboBox.Items.Add($os.Name)
        }

        $catalogControls.ArchitectureComboBox.Items.Clear()
        foreach ($arch in $architectures) {
            $null = $catalogControls.ArchitectureComboBox.Items.Add($arch)
        }
        $catalogControls.ArchitectureComboBox.SelectedIndex = 0

        $catalogControls.UpdateTypeComboBox.Items.Clear()
        foreach ($type in $updateTypes) {
            $null = $catalogControls.UpdateTypeComboBox.Items.Add($type)
        }
        $catalogControls.UpdateTypeComboBox.SelectedIndex = 0

        if ($catalogControls.SizeUnitComboBox) {
            $catalogControls.SizeUnitComboBox.SelectedIndex = 0
        }

        function Set-ReleaseOptions {
            param (
                [string] $OperatingSystemName
            )

            $catalogControls.ReleaseComboBox.Items.Clear()
            if (-not $OperatingSystemName) { return }

            $osEntry = $operatingSystems | Where-Object { $_.Name -eq $OperatingSystemName } | Select-Object -First 1
            if (-not $osEntry) { return }

            foreach ($release in $osEntry.Releases) {
                $null = $catalogControls.ReleaseComboBox.Items.Add($release.Name)
            }
            $catalogControls.ReleaseComboBox.SelectedIndex = 0
        }

        $catalogControls.OperatingSystemComboBox.Add_SelectionChanged({
            $selectedOs = [string]$catalogControls.OperatingSystemComboBox.SelectedItem
            Set-ReleaseOptions -OperatingSystemName $selectedOs
        })

        if ($catalogControls.OperatingSystemComboBox.Items.Count -gt 0) {
            $catalogControls.OperatingSystemComboBox.SelectedItem = 'Windows 11'
            if (-not $catalogControls.OperatingSystemComboBox.SelectedItem) {
                $catalogControls.OperatingSystemComboBox.SelectedIndex = 0
            }
        }

        $resultItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
        $catalogControls.ResultsList.ItemsSource = $resultItems

        function Set-CatalogStatus {
            param (
                [string] $Message,
                [Windows.Media.Brush] $Brush = $(New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x2B,0x57,0x9A)))
            )
            $catalogControls.StatusText.Text = $Message
            $catalogControls.StatusText.Foreground = $Brush
        }

        $catalogControls.SearchButton.Add_Click({
            $params = @{}
            $query = $catalogControls.SearchTextBox.Text
            $selectedOs = [string]$catalogControls.OperatingSystemComboBox.SelectedItem
            $selectedRelease = [string]$catalogControls.ReleaseComboBox.SelectedItem
            $selectedArch = [string]$catalogControls.ArchitectureComboBox.SelectedItem
            $selectedUpdateType = [string]$catalogControls.UpdateTypeComboBox.SelectedItem

            if (-not [string]::IsNullOrWhiteSpace($selectedOs)) {
                $params['OperatingSystem'] = $selectedOs
                if (-not [string]::IsNullOrWhiteSpace($selectedRelease)) {
                    $params['Version'] = $selectedRelease
                }
            } elseif ([string]::IsNullOrWhiteSpace($query)) {
                Set-CatalogStatus -Message 'Provide a search term or select an operating system.'
                return
            } else {
                $params['Search'] = $query
            }

            if ($selectedArch -and $selectedArch -ne 'All') {
                $params['Architecture'] = $selectedArch
            }

            if ($selectedUpdateType -and $selectedUpdateType -ne 'Any') {
                $params['UpdateType'] = @($selectedUpdateType)
            }

            if ($catalogControls.IncludePreviewCheckBox.IsChecked) { $params['IncludePreview'] = $true }
            if ($catalogControls.IncludeDynamicCheckBox.IsChecked) { $params['IncludeDynamic'] = $true }
            if ($catalogControls.GetFrameworkCheckBox.IsChecked) { $params['GetFramework'] = $true }
            if ($catalogControls.ExcludeFrameworkCheckBox.IsChecked) { $params['ExcludeFramework'] = $true }
            if ($catalogControls.StrictCheckBox.IsChecked) { $params['Strict'] = $true }
            if ($catalogControls.IncludeFileNamesCheckBox.IsChecked) { $params['IncludeFileNames'] = $true }
            if ($catalogControls.AllPagesCheckBox.IsChecked) { $params['AllPages'] = $true }

            $lastDaysValue = $catalogControls.LastDaysTextBox.Text
            if (-not [string]::IsNullOrWhiteSpace($lastDaysValue) -and [int]::TryParse($lastDaysValue, [ref]([int]$null))) {
                $params['LastDays'] = [int]$lastDaysValue
            }

            $minSize = $catalogControls.MinSizeTextBox.Text
            if (-not [string]::IsNullOrWhiteSpace($minSize) -and [double]::TryParse($minSize, [ref]([double]$null))) {
                $params['MinSize'] = [double]$minSize
            }

            $maxSize = $catalogControls.MaxSizeTextBox.Text
            if (-not [string]::IsNullOrWhiteSpace($maxSize) -and [double]::TryParse($maxSize, [ref]([double]$null))) {
                $params['MaxSize'] = [double]$maxSize
            }

            $sizeUnitItem = $catalogControls.SizeUnitComboBox.SelectedItem
            if ($sizeUnitItem -and $sizeUnitItem.Content) {
                $params['SizeUnit'] = $sizeUnitItem.Content.ToString()
            }

            $descriptor = if ($params.ContainsKey('OperatingSystem')) {
                "{0} {1}" -f $params['OperatingSystem'], ($params['Version'] ?? '')
            } else {
                $params['Search']
            }

            $catalogControls.SearchButton.IsEnabled = $false
            $resultItems.Clear()
            Set-CatalogStatus -Message ("Searching catalog for {0}..." -f $descriptor)

            try {
                $found = Find-WindowsUpdate @params
                foreach ($update in $found) {
                    $resultItems.Add($update) | Out-Null
                }

                if ($resultItems.Count -eq 0) {
                    Set-CatalogStatus -Message 'No updates found for the specified criteria.'
                } else {
                    Set-CatalogStatus -Message ("Found {0} update(s)." -f $resultItems.Count)
                }
            } catch {
                $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1,0x34,0x38))
                Set-CatalogStatus -Message "Catalog search failed: $($_.Exception.Message)" -Brush $errorBrush
            } finally {
                $catalogControls.SearchButton.IsEnabled = $true
            }
        })

        $catalogControls.DownloadButton.Add_Click({
            $selected = @($catalogControls.ResultsList.SelectedItems)
            if (-not $selected -or $selected.Count -eq 0) {
                Set-CatalogStatus -Message 'Select one or more updates to download.'
                return
            }

            $destination = $controls.UpdatePathTextBox.Text
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                $dialogFolder = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dialogFolder.Description = 'Select destination folder for downloaded updates'
                if ($dialogFolder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $destination = $dialogFolder.SelectedPath
                    $controls.UpdatePathTextBox.Text = $destination
                } else {
                    Set-CatalogStatus -Message 'Download cancelled.'
                    return
                }
            }

            try {
                Set-CatalogStatus -Message 'Downloading selected updates...'
                Save-WindowsUpdate -InputObject $selected -Destination $destination -DownloadAll:$true -Force:$true -ErrorAction Stop | Out-Null
                Set-CatalogStatus -Message ("Downloaded {0} update(s) to {1}." -f $selected.Count, $destination)
                $controls.UpdatePathTextBox.Text = $destination
            } catch {
                $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1,0x34,0x38))
                Set-CatalogStatus -Message "Download failed: $($_.Exception.Message)" -Brush $errorBrush
            }
        })

        $catalogControls.CopyButton.Add_Click({
            $selected = @($catalogControls.ResultsList.SelectedItems)
            if (-not $selected -or $selected.Count -eq 0) {
                Set-CatalogStatus -Message 'Select an update to copy its details.'
                return
            }

            $text = $selected | ForEach-Object {
                "Title: $($_.Title)`r`nClassification: $($_.Classification)`r`nLast Updated: $($_.LastUpdated)`r`nSize: $($_.Size)`r`nProducts: $($_.Products)`r`nGuid: $($_.Guid)`r`n"
            }
            [System.Windows.Clipboard]::SetText($text -join "`r`n")
            Set-CatalogStatus -Message 'Selected update details copied to clipboard.'
        })

        $catalogControls.ResultsList.Add_MouseDoubleClick({
            $catalogControls.CopyButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        })

        $catalogControls.CloseButton.Add_Click({
            $dialog.Close()
        })

        $null = $dialog.ShowDialog()
        $controls.IncludePreviewCheckBox.IsChecked = $catalogControls.IncludePreviewCheckBox.IsChecked
    }

    function Show-AutoDetectDialog {
        param (
            [Parameter(Mandatory)]
            [psobject[]] $Items
        )

        if (-not $Items -or $Items.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Select at least one WIM entry before running auto detect.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }

        $dialogPath = Join-Path -Path $PSScriptRoot -ChildPath 'AutoDetectDialog.xaml'
        if (-not (Test-Path -LiteralPath $dialogPath -PathType Leaf)) {
            throw "Unable to locate auto detect dialog layout at $dialogPath."
        }

        [xml]$dialogXml = Get-Content -LiteralPath $dialogPath -Raw
        $dialogReader = New-Object System.Xml.XmlNodeReader $dialogXml
        $dialog = [Windows.Markup.XamlReader]::Load($dialogReader)
        $dialog.Owner = $window

        $detectControls = @{
            DownloadPathTextBox             = $dialog.FindName('DownloadPathTextBox')
            BrowseDownloadPathButton        = $dialog.FindName('BrowseDownloadPathButton')
            AutoDetectUpdateTypeComboBox    = $dialog.FindName('AutoDetectUpdateTypeComboBox')
            AutoDetectIncludePreviewCheckBox = $dialog.FindName('AutoDetectIncludePreviewCheckBox')
            AutoDetectResults               = $dialog.FindName('AutoDetectResults')
            QueueDownloadButton             = $dialog.FindName('QueueDownloadButton')
            CopyUpdatesButton               = $dialog.FindName('CopyUpdatesButton')
            CloseButton                     = $dialog.FindName('CloseButton')
            StatusText                      = $dialog.FindName('AutoDetectStatusText')
        }

        foreach ($key in $detectControls.Keys) {
            if (-not $detectControls[$key]) {
                throw "Unable to locate auto-detect dialog control '$key'."
            }
        }

        if (-not $state.CatalogFacets) {
            $state.CatalogFacets = Get-ToolkitCatalogData
        }

        $detectControls.AutoDetectUpdateTypeComboBox.Items.Clear()
        foreach ($type in @('Cumulative Updates') + $state.CatalogFacets.UpdateTypes) {
            if (-not $detectControls.AutoDetectUpdateTypeComboBox.Items.Contains($type)) {
                $null = $detectControls.AutoDetectUpdateTypeComboBox.Items.Add($type)
            }
        }
        $detectControls.AutoDetectUpdateTypeComboBox.SelectedItem = 'Cumulative Updates'

        $downloadPath = if (-not [string]::IsNullOrWhiteSpace($controls.UpdatePathTextBox.Text)) {
            $controls.UpdatePathTextBox.Text
        } else {
            $state.ImportRoot
        }

        $detectControls.DownloadPathTextBox.Text = $downloadPath
        $detectControls.AutoDetectIncludePreviewCheckBox.IsChecked = $controls.IncludePreviewCheckBox.IsChecked

        $resultCollection = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
        $detectControls.AutoDetectResults.ItemsSource = $resultCollection

        function Update-AutoDetectStatus {
            param ([string] $Message)
            $detectControls.StatusText.Text = $Message
        }

        function Get-UpdateKbValue {
            param (
                [Parameter()]
                [object] $Update
            )

            if (-not $Update) { return $null }

            $kbValue = $null
            try {
                $kbValue = $Update.KB
            } catch {
                $kbValue = $null
            }
            if (-not [string]::IsNullOrWhiteSpace($kbValue)) {
                return $kbValue
            }

            $titleValue = $null
            try {
                $titleValue = $Update.Title
            } catch {
                $titleValue = $null
            }
            if (-not [string]::IsNullOrWhiteSpace($titleValue) -and ($titleValue -match '(KB\d{4,7})')) {
                return $matches[1]
            }

            $guidValue = $null
            try {
                $guidValue = $Update.Guid
            } catch {
                $guidValue = $null
            }
            if (-not [string]::IsNullOrWhiteSpace($guidValue) -and ($guidValue -match '(KB\d{4,7})')) {
                return $matches[1]
            }

            return $null
        }

        function Invoke-AutoDetect {
            $resultCollection.Clear()
            Update-AutoDetectStatus -Message 'Detecting updates...'
            $groups = $Items | Group-Object -Property Path
            $includePreview = [bool]$detectControls.AutoDetectIncludePreviewCheckBox.IsChecked
            $selectedType = [string]$detectControls.AutoDetectUpdateTypeComboBox.SelectedItem
            $typeFilter = if ([string]::IsNullOrWhiteSpace($selectedType)) { @('Cumulative Updates') } else { @($selectedType) }

            foreach ($group in $groups) {
                $indices = @(
                    $group.Group |
                        ForEach-Object { $_.Index } |
                        Where-Object { $_ } |
                        Select-Object -Unique
                )
                if ($indices.Count -eq 0) { $indices = @(1) }
                try {
                    $applicable = Get-WimApplicableUpdate -Path $group.Name -Index $indices -IncludePreview:$includePreview -UpdateType $typeFilter -ErrorAction Stop
                } catch {
                    Update-AutoDetectStatus -Message "Auto detect failed for $($group.Name): $($_.Exception.Message)"
                    continue
                }

                foreach ($match in $applicable) {
                    if (-not $match.Update) { continue }
                    $kb = Get-UpdateKbValue -Update $match.Update
                    $title = $match.Update.Title
                    $classification = $match.Update.Classification
                    $resultCollection.Add([pscustomobject]@{
                        WimPath        = $match.WimPath
                        WimName        = $match.WimName
                        Index          = $match.WimIndex
                        OperatingSystem = $match.OperatingSystem
                        Release        = $match.Release
                        Architecture   = $match.Architecture
                        UpdateType     = ($match.UpdateType -join ', ')
                        KB             = $kb
                        Title          = $title
                        Classification = $classification
                        LastUpdated    = $match.Update.LastUpdated
                        Guid           = $match.Update.Guid
                        CatalogUpdate  = $match.Update
                    }) | Out-Null
                }
            }

            if ($resultCollection.Count -eq 0) {
                Update-AutoDetectStatus -Message 'No catalog updates detected for the selected WIM images.'
            } else {
                Update-AutoDetectStatus -Message "Detected $($resultCollection.Count) update(s)."
            }
        }

        Invoke-AutoDetect

        $detectControls.AutoDetectUpdateTypeComboBox.Add_SelectionChanged({
            Invoke-AutoDetect
        })

        $detectControls.AutoDetectIncludePreviewCheckBox.Add_Click({
            Invoke-AutoDetect
        })

        $detectControls.BrowseDownloadPathButton.Add_Click({
            $dialogBrowse = [System.Windows.Forms.FolderBrowserDialog]::new()
            $dialogBrowse.Description = 'Select destination folder for detected update downloads'
            if ($dialogBrowse.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $detectControls.DownloadPathTextBox.Text = $dialogBrowse.SelectedPath
            }
        })

        $detectControls.QueueDownloadButton.Add_Click({
            $destination = $detectControls.DownloadPathTextBox.Text
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                [System.Windows.MessageBox]::Show('Specify a valid download directory before queueing downloads.', 'PSWimToolkit', 'OK', 'Warning') | Out-Null
                return
            }

            $selected = @($detectControls.AutoDetectResults.SelectedItems)
            if ($selected.Count -eq 0) {
                $selected = @($resultCollection)
            }
            if ($selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show('No updates available to download.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
                return
            }

            $updates = $selected | ForEach-Object { $_.CatalogUpdate } | Where-Object { $_ } | Select-Object -Unique

            try {
                Update-AutoDetectStatus -Message 'Downloading detected updates...'
                Save-WindowsUpdate -InputObject $updates -Destination $destination -DownloadAll:$true -Force:$true -ErrorAction Stop | Out-Null
                Update-AutoDetectStatus -Message "Downloaded $($updates.Count) update(s) to $destination."
                $controls.UpdatePathTextBox.Text = $destination
            } catch {
                Update-AutoDetectStatus -Message "Download failed: $($_.Exception.Message)"
            }
        })

        $detectControls.CopyUpdatesButton.Add_Click({
            $selection = @($detectControls.AutoDetectResults.SelectedItems)
            if ($selection.Count -eq 0) {
                $selection = @($resultCollection)
            }
            if ($selection.Count -eq 0) { return }
            $buffer = $selection | ForEach-Object {
                "WIM: {0}`r`nIndex: {1}`r`nKB: {2}`r`nTitle: {3}`r`nClassification: {4}`r`nLast Updated: {5}`r`nGuid: {6}" -f $_.WimName, $_.Index, $_.KB, $_.Title, $_.Classification, $_.LastUpdated, $_.Guid
            }
            [System.Windows.Clipboard]::SetText(($buffer -join "`r`n`r`n"))
            Update-AutoDetectStatus -Message "Copied $($selection.Count) entries."
        })

        $detectControls.CloseButton.Add_Click({
            $dialog.Close()
        })

        $null = $dialog.ShowDialog()
    }

    function Update-LogView {
        $filter = ($controls.LogLevelComboBox.SelectedItem)?.Content
        if (-not $filter) { $filter = 'All' }

        $displayItems = if ($filter -eq 'All') {
            $state.AllLogData
        } else {
            $state.AllLogData | Where-Object { $_.Level -eq $filter }
        }

        $ordered = $displayItems | Sort-Object Timestamp | Select-Object -Last 500
        $logItems.Clear()
        foreach ($entry in $ordered) {
            $logItems.Add($entry) | Out-Null
        }
        if ([bool]$controls.AutoScrollCheckBox.IsChecked -and $logItems.Count -gt 0) {
            $controls.LogList.ScrollIntoView($logItems[$logItems.Count - 1])
        }
    }

    function Harvest-Logs {
        if (-not $state.LogRoot) { return }
        if (-not (Test-Path -LiteralPath $state.LogRoot -PathType Container)) { return }

        $logFiles = Get-ChildItem -LiteralPath $state.LogRoot -Filter *.log -ErrorAction SilentlyContinue
        $regex = '^\[(?<Timestamp>.+?)\]\s+\[(?<Level>.+?)\]\s+\[(?<Source>.+?)\]\s+(?<Message>.*)$'

        foreach ($file in $logFiles) {
            $lines = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $key = "{0}|{1}" -f $file.FullName, $line
                if (-not $state.KnownLogEntries.Add($key)) { continue }

                $match = [regex]::Match($line, $regex)
                if ($match.Success) {
                    $timestamp = $match.Groups['Timestamp'].Value
                    $level = $match.Groups['Level'].Value
                    $source = $match.Groups['Source'].Value
                    $message = $match.Groups['Message'].Value
                } else {
                    $timestamp = (Get-Date).ToString('s')
                    $level = 'Info'
                    $source = [System.IO.Path]::GetFileName($file.FullName)
                    $message = $line
                }

                $entry = [pscustomobject]@{
                    Timestamp = $timestamp
                    Level     = $level
                    Source    = $source
                    Message   = $message
                }

                $state.AllLogData.Add($entry)
            }
        }

        Update-LogView
    }

    function Enable-ControlSet {
        param (
            [bool] $Enabled
        )

        $controls.OpenConfigMenuItem.IsEnabled = $Enabled
        $controls.SaveConfigMenuItem.IsEnabled = $Enabled
        $controls.DownloadUpdatesMenuItem.IsEnabled = $Enabled
        $controls.ClearLogsMenuItem.IsEnabled = $Enabled
        $controls.ExportLogsMenuItem.IsEnabled = $Enabled
        $controls.SearchCatalogButton.IsEnabled = $Enabled
        $controls.AddWimButton.IsEnabled = $Enabled
        $controls.ImportIsoButton.IsEnabled = $Enabled
        $controls.WimDetailsButton.IsEnabled = $Enabled
        $controls.RemoveWimButton.IsEnabled = $Enabled
        $controls.ClearWimButton.IsEnabled = $Enabled
        $controls.AutoDetectButton.IsEnabled = $Enabled
        $controls.StartButton.IsEnabled = $Enabled
        $controls.BrowseUpdateButton.IsEnabled = $Enabled
        $controls.BrowseSxSButton.IsEnabled = $Enabled
        $controls.BrowseOutputButton.IsEnabled = $Enabled
        $controls.WimGrid.IsReadOnly = -not $Enabled
        $controls.EnableNetFxCheckBox.IsEnabled = $Enabled
        $controls.ForceCheckBox.IsEnabled = $Enabled
        $controls.VerboseLogCheckBox.IsEnabled = $Enabled
        $controls.IncludePreviewCheckBox.IsEnabled = $Enabled
        $controls.ThrottleSlider.IsEnabled = $Enabled
        $controls.StopButton.IsEnabled = -not $Enabled
    }

    function Prepare-Timer {
        if ($state.Timer) { return }
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(2)
        $timer.Add_Tick({
            Harvest-Logs

            $job = $state.Job
            if (-not $job) { return }

            $jobState = $job.State
            switch ($jobState) {
                'Completed' {
                    Finish-Provisioning -Status 'Completed'
                }
                'Failed' {
                    Finish-Provisioning -Status 'Failed'
                }
                'Stopped' {
                    Finish-Provisioning -Status 'Stopped'
                }
            }
        })
        $state.Timer = $timer
    }

    function Finish-Provisioning {
        param (
            [ValidateSet('Completed','Failed','Stopped')]
            [string] $Status
        )

        $job = $state.Job
        if (-not $job) { return }
        if ($state.Timer) {
            $state.Timer.Stop()
        }

        $results = $null
        try {
            $results = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to receive job output: $($_.Exception.Message)"
        }

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $state.Job = $null
        Harvest-Logs
        $controls.StopButton.IsEnabled = $false
        Enable-ControlSet -Enabled $true
        $controls.OverallProgressBar.IsIndeterminate = $false
        $controls.OverallProgressBar.Value = 100

        if ($results) {
            foreach ($result in $results) {
                $matched = $wimItems | Where-Object { $_.Path -eq $result.WimImage.Path }
                if (-not $matched) { continue }
                foreach ($item in $matched) {
                    $item.Status = $result.Status
                    $successCount = $result.UpdatesApplied.Count
                    $failedCount = $result.UpdatesFailed.Count
                    $item.Details = "Applied: $successCount | Failed: $failedCount"
                    if ($result.Errors.Count -gt 0) {
                        $item.Details = "$($item.Details) | Errors: $($result.Errors.Count)"
                    }
                }
            }
            $controls.WimGrid.Items.Refresh()
            $controls.ProgressList.Items.Refresh()
            $successBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x10,0x7C,0x10))
            Update-Status -Message "Provisioning completed for $($results.Count) WIM image(s)." -Brush $successBrush
        } else {
            foreach ($item in $wimItems) {
                if ($item.Status -eq 'Running' -or $item.Status -eq 'Queued') {
                    $item.Status = switch ($Status) {
                        'Stopped' { 'Cancelled' }
                        'Failed' { 'Failed' }
                        default { 'Completed' }
                    }
                    if ($item.Status -eq 'Failed') {
                        $item.Details = 'Provisioning failed.'
                    } elseif ($item.Status -eq 'Cancelled') {
                        $item.Details = 'Operation cancelled by user.'
                    }
                }
            }
            $controls.WimGrid.Items.Refresh()
            $controls.ProgressList.Items.Refresh()
            Update-Status -Message "Provisioning $Status. Review logs for details." -Brush (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1,0x34,0x38)))
        }
    }

    function Start-Provisioning {
        if ($wimItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Add at least one WIM file before starting provisioning.', 'PSWimToolkit', 'OK', 'Warning') | Out-Null
            return
        }

        $updatePath = $controls.UpdatePathTextBox.Text
        if (-not (Test-Path -LiteralPath $updatePath -PathType Container)) {
            [System.Windows.MessageBox]::Show('Select a valid update folder before starting provisioning.', 'PSWimToolkit', 'OK', 'Warning') | Out-Null
            return
        }

        $sxspath = $controls.SxSPathTextBox.Text
        if ($controls.EnableNetFxCheckBox.IsChecked -and -not [string]::IsNullOrWhiteSpace($sxspath)) {
            if (-not (Test-Path -LiteralPath $sxspath -PathType Container)) {
                [System.Windows.MessageBox]::Show('SxS folder does not exist. Please verify the path or deselect .NET Framework option.', 'PSWimToolkit', 'OK', 'Warning') | Out-Null
                return
            }
        }

        $outputPath = $controls.OutputPathTextBox.Text
        if (-not [string]::IsNullOrWhiteSpace($outputPath)) {
            if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
                try {
                    New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
                } catch {
                    [System.Windows.MessageBox]::Show("Unable to create output folder '$outputPath'.", 'PSWimToolkit', 'OK', 'Warning') | Out-Null
                    return
                }
            }
        } else {
            $outputPath = $null
        }

        $logDirectory = Join-Path -Path $state.LogBase -ChildPath ("Run_{0:yyyyMMdd_HHmmss}" -f (Get-Date))
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        $state.LogRoot = $logDirectory
        Reset-LogCollections
        $controls.LogPathTextBlock.Text = "Logs folder: $logDirectory"

        foreach ($item in $wimItems) {
            $item.Status = 'Queued'
            $item.Details = ''
        }
        $controls.WimGrid.Items.Refresh()
        $controls.ProgressList.Items.Refresh()

        $controls.OverallProgressBar.IsIndeterminate = $true
        $controls.OverallProgressBar.Value = 0
        Enable-ControlSet -Enabled $false
        $controls.StopButton.IsEnabled = $true
        Refresh-ThrottleText -Value $controls.ThrottleSlider.Value
        Update-Status -Message 'Provisioning started...'

        $jobEntries = foreach ($item in $wimItems) {
            [pscustomobject]@{
                Name    = $item.Name
                Path    = $item.Path
                Index   = [int]$item.Index
            }
        }

        $indexMap = @{}
        foreach ($entry in $jobEntries) {
            if ($indexMap.ContainsKey($entry.Name)) { continue }
            $indexMap[$entry.Name] = $entry.Index
        }

        $throttle = [int][Math]::Round($controls.ThrottleSlider.Value)
        $enableNetFx = [bool]$controls.EnableNetFxCheckBox.IsChecked
        $forceUpdates = [bool]$controls.ForceCheckBox.IsChecked
        $verboseLogs = [bool]$controls.VerboseLogCheckBox.IsChecked

        $job = Start-ThreadJob -Name 'PSWimToolkitParallelProvisioning' -ScriptBlock {
            param(
                $ModulePath,
                $Entries,
                $UpdatePath,
                $SxSPath,
                $ThrottleLimit,
                $EnableNetFx3,
                $ForceUpdates,
                $LogPath,
                $MountRoot,
                $IndexMap,
                $OutputDirectory,
                $VerboseLogs
            )

            Import-Module -Name $ModulePath -Force | Out-Null

            if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
                if (-not (Test-Path -LiteralPath $LogPath)) {
                    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
                }
            }

            if ($VerboseLogs -and $script:LogConfig) {
                $script:LogConfig.DefaultLogLevel = 'Debug'
            }

            $wimFiles = $Entries | ForEach-Object { $_.Path }
            $arguments = @{
                WimFiles      = $wimFiles
                UpdatePath    = $UpdatePath
                ThrottleLimit = $ThrottleLimit
                LogPath       = $LogPath
                MountRoot     = $MountRoot
            }

            if ($SxSPath) { $arguments['SxSPath'] = $SxSPath }
            if ($EnableNetFx3) { $arguments['EnableNetFx3'] = $true }
            if ($ForceUpdates) { $arguments['Force'] = $true }
            if ($IndexMap) { $arguments['IndexSelection'] = $IndexMap }
            if ($OutputDirectory) { $arguments['OutputDirectory'] = $OutputDirectory }

            Start-ParallelProvisioning @arguments
        } -ArgumentList $state.ModulePath, $jobEntries, $updatePath, $sxspath, $throttle, $enableNetFx, $forceUpdates, $logDirectory, $state.MountRoot, $indexMap, $outputPath, $verboseLogs

        $state.Job = $job
        Prepare-Timer
        $state.Timer.Start()
    }

    function Stop-Provisioning {
        $job = $state.Job
        if (-not $job) { return }
        try {
            Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to stop provisioning job: $($_.Exception.Message)"
        }
        Finish-Provisioning -Status 'Stopped'
    }

    # Load any existing WIM files from the import directory
    Load-WimsFromImport

    $controls.ThrottleSlider.Add_ValueChanged({
        param($sender, $args)
        Refresh-ThrottleText -Value $sender.Value
    })

    $controls.AddWimButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'WIM images (*.wim)|*.wim|All files (*.*)|*.*'
        $dialog.Multiselect = $true
        if (-not $dialog.ShowDialog()) { return }

        $added = 0
        foreach ($file in $dialog.FileNames) {
            try {
                $destination = Copy-WimIntoImport -SourcePath $file
                if (Add-WimEntry -Path $destination) {
                    $added++
                }
            } catch {
                Write-Warning "Failed to import WIM '$file': $($_.Exception.Message)"
            }
        }

        if ($added -gt 0) {
            Update-Status -Message ("Imported {0} WIM file(s) into workspace." -f $added)
        } else {
            Update-Status -Message 'No WIM files were imported.'
        }
    })

    $controls.ImportIsoButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'ISO images (*.iso)|*.iso|All files (*.*)|*.*'
        $dialog.Multiselect = $true
        if (-not $dialog.ShowDialog()) { return }

        Update-Status -Message 'Importing ISO image(s)...'
        try {
            $imports = Import-WimFromIso -Path $dialog.FileNames -Destination $state.ImportRoot -ErrorAction Stop
            $added = 0
            foreach ($import in $imports) {
                if ([System.IO.Path]::GetExtension($import.Destination) -ne '.wim') { continue }
                if (Add-WimEntry -Path $import.Destination) {
                    $added++
                }
            }
            $message = if ($added -gt 0) {
                "Imported $added WIM file(s) from ISO."
            } else {
                'Import completed. No new WIM files were added.'
            }
            Update-Status -Message $message
        } catch {
            Update-Status -Message "ISO import failed: $($_.Exception.Message)" -Brush (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1,0x34,0x38)))
        }
    })

    $controls.RemoveWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) { return }
        foreach ($item in @($selected)) {
            Remove-WimEntry -Item $item | Out-Null
        }
    })

    $controls.DeleteWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Select at least one WIM before deleting from disk.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }
        $removed = 0
        foreach ($item in @($selected)) {
            if (Remove-WimEntry -Item $item -DeleteFile) {
                $removed++
            }
        }
        if ($removed -gt 0) {
            Update-Status -Message ("Deleted {0} WIM file(s) from the import workspace." -f $removed)
        }
    })

    $controls.ClearWimButton.Add_Click({
        foreach ($item in @($wimItems.ToArray())) {
            Remove-WimEntry -Item $item | Out-Null
        }
    })

    $controls.WimDetailsButton.Add_Click({
        $selection = Get-SelectedWimItems
        if (-not $selection -or $selection.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Select a WIM entry first.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }
        Show-WimDetailsDialog -Items $selection
    })

    $controls.WimGrid.Add_CellEditEnding({
        param($sender, $eventArgs)
        $item = $eventArgs.Row.Item
        if ($item) {
            Refresh-WimItemDetails -Item $item -Force
        }
    })

    $controls.BrowseUpdateButton.Add_Click({
        Open-FolderPath -Path $controls.UpdatePathTextBox.Text -DisplayName 'Update folder'
    })

    $controls.BrowseSxSButton.Add_Click({
        Open-FolderPath -Path $controls.SxSPathTextBox.Text -DisplayName 'SxS folder'
    })

    $controls.BrowseOutputButton.Add_Click({
        Open-FolderPath -Path $controls.OutputPathTextBox.Text -DisplayName 'Output folder'
    })

    $controls.StartButton.Add_Click({
        Start-Provisioning
    })

    $controls.StopButton.Add_Click({
        Stop-Provisioning
    })

    $controls.LogLevelComboBox.Add_SelectionChanged({
        Update-LogView
    })

    $saveLogsHandler = {
        if ($state.AllLogData.Count -eq 0) {
            [System.Windows.MessageBox]::Show('No log entries available to save.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
        $dialog.FileName = 'PSWimToolkit Provisioning Logs.txt'
        if ($dialog.ShowDialog()) {
            Save-LogsToFile -Destination $dialog.FileName
        }
    }
    $controls.SaveLogsButton.Add_Click($saveLogsHandler)

    $clearLogsHandler = {
        Reset-LogCollections
    }
    $controls.ClearLogsButton.Add_Click($clearLogsHandler)

    $controls.OpenLogFolderButton.Add_Click({
        if ($state.LogRoot -and (Test-Path -LiteralPath $state.LogRoot -PathType Container)) {
            Start-Process explorer.exe $state.LogRoot | Out-Null
        } else {
            [System.Windows.MessageBox]::Show('No log folder has been generated yet.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
        }
    })

    $controls.AutoScrollCheckBox.Add_Click({
        Update-LogView
    })

    $controls.AutoDetectButton.Add_Click({
        $selection = @($controls.WimGrid.SelectedItems)
        if ($selection.Count -eq 0) {
            $selection = @($wimItems)
        }
        Show-AutoDetectDialog -Items $selection
    })

    $controls.SearchCatalogButton.Add_Click({
        Show-CatalogDialog
    })

    $controls.OpenConfigMenuItem.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'Configuration (*.json)|*.json|All files (*.*)|*.*'
        if ($dialog.ShowDialog()) {
            Load-Configuration -Path $dialog.FileName
        }
    })

    $controls.SaveConfigMenuItem.Add_Click({
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Filter = 'Configuration (*.json)|*.json|All files (*.*)|*.*'
        $dialog.FileName = 'PSWimToolkitProvisioning.json'
        if ($dialog.ShowDialog()) {
            Save-Configuration -Path $dialog.FileName
        }
    })

    $controls.ExitMenuItem.Add_Click({
        $window.Close()
    })

    $downloadHandler = {
        Show-CatalogDialog
    }
    $controls.DownloadUpdatesMenuItem.Add_Click($downloadHandler)

    $controls.ClearLogsMenuItem.Add_Click($clearLogsHandler)
    $controls.ExportLogsMenuItem.Add_Click($saveLogsHandler)

    $controls.ToggleLogViewMenuItem.Add_Checked({
        $controls.LogViewerGroup.Visibility = [System.Windows.Visibility]::Visible
    })
    $controls.ToggleLogViewMenuItem.Add_Unchecked({
        $controls.LogViewerGroup.Visibility = [System.Windows.Visibility]::Collapsed
    })

    $controls.AboutMenuItem.Add_Click({
        $message = "PSWimToolkit`r`nVersion: $($state.ModuleVersion)`r`nAuthor: Mickael CHAVE`r`n`r`nModern tooling to provision Windows images with catalog integration."
        [System.Windows.MessageBox]::Show($message, 'About PSWimToolkit', 'OK', 'Information') | Out-Null
    })

    $controls.DocumentationMenuItem.Add_Click({
        Start-Process 'https://github.com/mchave3/PSWimToolkit' | Out-Null
    })

    $window.Add_Closing({
        if ($state.Timer) {
            $state.Timer.Stop()
        }
        if ($state.Job) {
            try {
                Stop-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
                Remove-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    })

    Refresh-ThrottleText -Value $controls.ThrottleSlider.Value
    Update-Status -Message 'Ready'

    $null = $window.ShowDialog()
}
