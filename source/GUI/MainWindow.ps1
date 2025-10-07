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
        throw 'Show-ProvisioningGUI must be invoked from an STA thread. Launch PowerShell with -STA and retry.'
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
        RemoveWimButton       = $window.FindName('RemoveWimButton')
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

    $state = [pscustomobject]@{
        Job               = $null
        Timer             = $null
        LogRoot           = $null
        KnownLogEntries   = [System.Collections.Generic.HashSet[string]]::new()
        AllLogData        = [System.Collections.Generic.List[psobject]]::new()
        ModulePath        = $ModulePath
        ModuleVersion     = $moduleVersion
        MountRoot         = Join-Path ([System.IO.Path]::GetTempPath()) 'PSWimToolkit\GUIMounts'
        LogBase           = Join-Path ([System.IO.Path]::GetTempPath()) 'PSWimToolkit\GUILogs'
    }

    if (-not (Test-Path -LiteralPath $state.MountRoot)) {
        New-Item -Path $state.MountRoot -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $state.LogBase)) {
        New-Item -Path $state.LogBase -ItemType Directory -Force | Out-Null
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
        }
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
                try {
                    $info = Get-WimImageInfo -Path $entry.Path -Index $indexValue -ErrorAction Stop
                    if ($info) {
                        $item.Details = $info.Name
                    } else {
                        $item.Details = 'Pending'
                    }
                } catch {
                    $item.Details = 'Pending'
                }
                $wimItems.Add($item)
            }
        }
        $controls.WimGrid.Items.Refresh()
        $controls.ProgressList.Items.Refresh()

        if ($config.UpdatePath) { $controls.UpdatePathTextBox.Text = $config.UpdatePath } else { $controls.UpdatePathTextBox.Clear() }
        if ($config.SxSPath) { $controls.SxSPathTextBox.Text = $config.SxSPath } else { $controls.SxSPathTextBox.Clear() }
        if ($config.OutputPath) { $controls.OutputPathTextBox.Text = $config.OutputPath } else { $controls.OutputPathTextBox.Clear() }

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

    function Show-CatalogDialog {
        $catalogXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Update Catalog Search'
        Height='520'
        Width='860'
        WindowStartupLocation='CenterOwner'
        Background='#FFFFFF'
        FontFamily='Segoe UI'>
    <Grid Margin='12'>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
            <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>

        <StackPanel Orientation='Horizontal'
                    Grid.Row='0'>
            <TextBox x:Name='SearchTextBox'
                     Width='420'
                     Margin='0,0,8,0'
                     VerticalAlignment='Center'
                     ToolTip='Search term or KB number'/>
            <Button x:Name='SearchButton'
                    Content='Search'
                    Width='90'/>
        </StackPanel>

        <StackPanel Orientation='Horizontal'
                    Grid.Row='1'
                    Margin='0,10,0,10'>
            <CheckBox x:Name='AllPagesCheckBox'
                      Content='All pages'
                      Margin='0,0,12,0'/>
            <CheckBox x:Name='IncludePreviewCheckBox'
                      Content='Include preview updates'
                      Margin='0,0,12,0'/>
        </StackPanel>

        <ListView x:Name='ResultsList'
                  Grid.Row='2'
                  SelectionMode='Extended'>
            <ListView.View>
                <GridView>
                    <GridViewColumn Header='Title'
                                    Width='360'
                                    DisplayMemberBinding='{Binding Title}'/>
                    <GridViewColumn Header='Classification'
                                    Width='140'
                                    DisplayMemberBinding='{Binding Classification}'/>
                    <GridViewColumn Header='Last Updated'
                                    Width='130'
                                    DisplayMemberBinding='{Binding LastUpdated}'/>
                    <GridViewColumn Header='Size'
                                    Width='120'
                                    DisplayMemberBinding='{Binding Size}'/>
                </GridView>
            </ListView.View>
        </ListView>

        <Grid Grid.Row='3'>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='*'/>
                <ColumnDefinition Width='Auto'/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name='CatalogStatusText'
                       Grid.Column='0'
                       VerticalAlignment='Center'
                       Foreground='#2B579A'/>
            <StackPanel Grid.Column='1'
                        Orientation='Horizontal'>
                <Button x:Name='DownloadButton'
                        Content='Download Selected'
                        Margin='0,0,10,0'/>
                <Button x:Name='CopyButton'
                        Content='Copy Details'
                        Margin='0,0,10,0'/>
                <Button x:Name='CloseButton'
                        Content='Close'/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

        [xml]$catalogXml = $catalogXaml
        $catalogReader = New-Object System.Xml.XmlNodeReader $catalogXml
        $dialog = [Windows.Markup.XamlReader]::Load($catalogReader)
        $dialog.Owner = $window

        $catalogControls = @{
            SearchTextBox         = $dialog.FindName('SearchTextBox')
            SearchButton          = $dialog.FindName('SearchButton')
            AllPagesCheckBox      = $dialog.FindName('AllPagesCheckBox')
            IncludePreviewCheckBox = $dialog.FindName('IncludePreviewCheckBox')
            ResultsList           = $dialog.FindName('ResultsList')
            DownloadButton        = $dialog.FindName('DownloadButton')
            CopyButton            = $dialog.FindName('CopyButton')
            CloseButton           = $dialog.FindName('CloseButton')
            StatusText            = $dialog.FindName('CatalogStatusText')
        }

        foreach ($key in $catalogControls.Keys) {
            if (-not $catalogControls[$key]) {
                throw "Unable to locate catalog dialog control '$key'."
            }
        }

        $catalogControls.IncludePreviewCheckBox.IsChecked = $controls.IncludePreviewCheckBox.IsChecked

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
            $query = $catalogControls.SearchTextBox.Text
            if ([string]::IsNullOrWhiteSpace($query)) {
                Set-CatalogStatus -Message 'Enter a search term or KB number before searching.'
                return
            }

            $catalogControls.SearchButton.IsEnabled = $false
            $resultItems.Clear()
            Set-CatalogStatus -Message "Searching catalog for '$query'..."

            try {
                $includePreview = [bool]$catalogControls.IncludePreviewCheckBox.IsChecked
                $allPages = [bool]$catalogControls.AllPagesCheckBox.IsChecked
                $found = Find-WindowsUpdate -Search $query -IncludePreview:$includePreview -AllPages:$allPages -ErrorAction Stop
                foreach ($update in $found) {
                    $resultItems.Add($update) | Out-Null
                }
                if ($resultItems.Count -eq 0) {
                    Set-CatalogStatus -Message 'No updates found for the specified query.'
                } else {
                    Set-CatalogStatus -Message "Found $($resultItems.Count) update(s)."
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
                Save-WindowsUpdate -InputObject $selected -Destination $destination -DownloadAll:$true -ErrorAction Stop | Out-Null
                Set-CatalogStatus -Message "Downloaded $($selected.Count) update(s) to $destination."
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
        $controls.RemoveWimButton.IsEnabled = $Enabled
        $controls.ClearWimButton.IsEnabled = $Enabled
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

    $controls.ThrottleSlider.Add_ValueChanged({
        param($sender, $args)
        Refresh-ThrottleText -Value $sender.Value
    })

    $controls.AddWimButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'WIM images (*.wim)|*.wim|All files (*.*)|*.*'
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog()) {
            foreach ($file in $dialog.FileNames) {
                if ($wimItems | Where-Object { $_.Path -eq $file }) { continue }
                $item = New-WimItem -Path $file
                try {
                    $info = Get-WimImageInfo -Path $file -ErrorAction Stop
                    if ($info -and $info.Count -gt 0) {
                        $item.Index = $info[0].Index
                        $item.Details = $info[0].Name
                    }
                } catch {
                    $item.Details = 'Ready'
                }
                $wimItems.Add($item)
            }
        }
    })

    $controls.RemoveWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) { return }
        foreach ($item in @($selected)) {
            $null = $wimItems.Remove($item)
        }
    })

    $controls.ClearWimButton.Add_Click({
        $wimItems.Clear()
    })

    $controls.BrowseUpdateButton.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Select the folder that contains update packages (.cab/.msu)'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $controls.UpdatePathTextBox.Text = $dialog.SelectedPath
        }
    })

    $controls.BrowseSxSButton.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Select the SxS source folder for .NET Framework 3.5'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $controls.SxSPathTextBox.Text = $dialog.SelectedPath
        }
    })

    $controls.BrowseOutputButton.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Select a folder where updated WIM files should be saved'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $controls.OutputPathTextBox.Text = $dialog.SelectedPath
        }
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
        Start-Process 'https://github.com/Mickael-CHAVE/PSWimToolkit' | Out-Null
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
