function Show-PSWimToolkitMainWindow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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
    Add-Type -AssemblyName System.Windows.Controls.Ribbon

    $xamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        throw "Unable to locate GUI layout at $xamlPath."
    }

    [xml]$xamlContent = Get-Content -LiteralPath $xamlPath -Raw
    $xamlReader = New-Object System.Xml.XmlNodeReader $xamlContent
    $window = [Windows.Markup.XamlReader]::Load($xamlReader)

    $stylesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Styles.xaml'
    $stylesXmlDocument = $null
    $stylesLoadWarningEmitted = $false
    if (Test-Path -LiteralPath $stylesPath -PathType Leaf) {
        try {
            [xml]$stylesXmlDocument = Get-Content -LiteralPath $stylesPath -Raw
        } catch {
            $stylesLoadWarningEmitted = $true
            Write-Warning "Failed to load GUI styles: $($_.Exception.Message)"
        }
    }

    $controls = @{
        ExitMenuItem            = $window.FindName('ExitMenuItem')
        DownloadUpdatesMenuItem = $window.FindName('DownloadUpdatesMenuItem')
        ClearLogsMenuItem       = $window.FindName('ClearLogsMenuItem')
        ExportLogsMenuItem      = $window.FindName('ExportLogsMenuItem')
        ToggleLogViewMenuItem   = $window.FindName('ToggleLogViewMenuItem')
        AboutMenuItem           = $window.FindName('AboutMenuItem')
        DocumentationMenuItem   = $window.FindName('DocumentationMenuItem')
        AddWimButton            = $window.FindName('AddWimButton')
        ImportIsoButton         = $window.FindName('ImportIsoButton')
        WimDetailsButton        = $window.FindName('WimDetailsButton')
        RemoveWimButton         = $window.FindName('RemoveWimButton')
        DeleteWimButton         = $window.FindName('DeleteWimButton')
        ClearWimButton          = $window.FindName('ClearWimButton')
        WimGrid                 = $window.FindName('WimGrid')
        UpdatePathTextBox       = $window.FindName('UpdatePathTextBox')
        BrowseUpdateButton      = $window.FindName('BrowseUpdateButton')
        SxSPathTextBox          = $window.FindName('SxSPathTextBox')
        BrowseSxSButton         = $window.FindName('BrowseSxSButton')
        OutputPathTextBox       = $window.FindName('OutputPathTextBox')
        BrowseOutputButton      = $window.FindName('BrowseOutputButton')
        EnableNetFxCheckBox     = $window.FindName('EnableNetFxCheckBox')
        ForceCheckBox           = $window.FindName('ForceCheckBox')
        VerboseLogCheckBox      = $window.FindName('VerboseLogCheckBox')
        IncludePreviewCheckBox  = $window.FindName('IncludePreviewCheckBox')
        AutoDetectButton        = $window.FindName('AutoDetectButton')
        SearchCatalogButton     = $window.FindName('SearchCatalogButton')
        StartButton             = $window.FindName('StartButton')
        StopButton              = $window.FindName('StopButton')
        ThrottleSlider          = $window.FindName('ThrottleSlider')
        ThrottleValueText       = $window.FindName('ThrottleValueText')
        StatusTextBlock         = $window.FindName('StatusTextBlock')
        OverallProgressBar      = $window.FindName('OverallProgressBar')
        ProgressList            = $window.FindName('ProgressList')
        LogLevelComboBox        = $window.FindName('LogLevelComboBox')
        LogList                 = $window.FindName('LogList')
        AutoScrollCheckBox      = $window.FindName('AutoScrollCheckBox')
        SaveLogsButton          = $window.FindName('SaveLogsButton')
        ClearLogsButton         = $window.FindName('ClearLogsButton')
        OpenLogFolderButton     = $window.FindName('OpenLogFolderButton')
        LogPathTextBlock        = $window.FindName('LogPathTextBlock')
        LogViewerGroup          = $window.FindName('LogViewerGroup')
    }

    foreach ($key in $controls.Keys) {
        if (-not $controls[$key]) {
            throw "Unable to locate expected GUI control '$key'."
        }
    }

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
        Job              = $null
        Timer            = $null
        LogRoot          = $null
        KnownLogEntries  = [System.Collections.Generic.HashSet[string]]::new()
        AllLogData       = [System.Collections.Generic.List[psobject]]::new()
        ModulePath       = $ModulePath
        ModuleVersion    = $moduleVersion
        MountRoot        = $mountRoot
        LogBase          = $logRoot
        ImportRoot       = $importRoot
        UpdatesRoot      = $updatesRoot
        SxSRoot          = $sxsRoot
        OutputRoot       = $outputRoot
        WimMetadataCache = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[psobject]]]::new()
        CatalogFacets    = $null
    }

    foreach ($path in @($state.MountRoot, $state.LogBase, $state.ImportRoot, $state.SxSRoot, $state.OutputRoot)) {
        if ($path -and -not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
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

    $context = [pscustomobject]@{
        Window                    = $window
        Controls                  = $controls
        State                     = $state
        WimItems                  = $wimItems
        LogItems                  = $logItems
        StylesXmlDocument         = $stylesXmlDocument
        StylesLoadWarningEmitted  = $stylesLoadWarningEmitted
        GuiRoot                   = $PSScriptRoot
    }

    Add-SharedGuiStyles -Context $context -Target $window

    Load-WimsFromImport -Context $context

    $controls.ThrottleSlider.Add_ValueChanged({
        param($sender, $args)
        Refresh-ThrottleText -Context $context -Value $sender.Value
    })

    $controls.AddWimButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'WIM images (*.wim)|*.wim|All files (*.*)|*.*'
        $dialog.Multiselect = $true
        if (-not $dialog.ShowDialog()) { return }

        $added = 0
        foreach ($file in $dialog.FileNames) {
            try {
                $destination = Copy-WimIntoImport -Context $context -SourcePath $file
                if (Add-WimEntry -Context $context -Path $destination) {
                    $added++
                }
            } catch {
                Write-Warning "Failed to import WIM '$file': $($_.Exception.Message)"
            }
        }

        if ($added -gt 0) {
            Update-Status -Context $context -Message ("Imported {0} WIM file(s) into workspace." -f $added)
        } else {
            Update-Status -Context $context -Message 'No WIM files were imported.'
        }
    })

    $controls.ImportIsoButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'ISO images (*.iso)|*.iso|All files (*.*)|*.*'
        $dialog.Multiselect = $true
        if (-not $dialog.ShowDialog()) { return }

        Update-Status -Context $context -Message 'Importing ISO image(s)...'
        try {
            $imports = Import-WimFromIso -Path $dialog.FileNames -Destination $state.ImportRoot -ErrorAction Stop
            $added = 0
            foreach ($import in $imports) {
                if ([System.IO.Path]::GetExtension($import.Destination) -ne '.wim') { continue }
                if (Add-WimEntry -Context $context -Path $import.Destination) {
                    $added++
                }
            }
            $message = if ($added -gt 0) {
                "Imported $added WIM file(s) from ISO."
            } else {
                'Import completed. No new WIM files were added.'
            }
            Update-Status -Context $context -Message $message
        } catch {
            $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38))
            Update-Status -Context $context -Message "ISO import failed: $($_.Exception.Message)" -Brush $errorBrush
        }
    })

    $controls.RemoveWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) { return }
        foreach ($item in @($selected)) {
            Remove-WimEntry -Context $context -Item $item | Out-Null
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
            if (Remove-WimEntry -Context $context -Item $item -DeleteFile) {
                $removed++
            }
        }
        if ($removed -gt 0) {
            Update-Status -Context $context -Message ("Deleted {0} WIM file(s) from the import workspace." -f $removed)
        }
    })

    $controls.ClearWimButton.Add_Click({
        foreach ($item in @($wimItems.ToArray())) {
            Remove-WimEntry -Context $context -Item $item | Out-Null
        }
    })

    $controls.WimDetailsButton.Add_Click({
        $selection = Get-SelectedWimItems -Context $context
        if (-not $selection -or $selection.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Select a WIM entry first.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
            return
        }
        Show-WimDetailsDialog -Context $context -Items $selection
    })

    $controls.WimGrid.Add_CellEditEnding({
        param($sender, $eventArgs)
        $item = $eventArgs.Row.Item
        if ($item) {
            Refresh-WimItemDetails -Context $context -Item $item -Force
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
        Start-Provisioning -Context $context
    })

    $controls.StopButton.Add_Click({
        Stop-Provisioning -Context $context
    })

    $controls.LogLevelComboBox.Add_SelectionChanged({
        Update-LogView -Context $context
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
            Save-LogsToFile -Context $context -Destination $dialog.FileName
        }
    }
    $controls.SaveLogsButton.Add_Click($saveLogsHandler)

    $clearLogsHandler = {
        Reset-LogCollections -Context $context
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
        Update-LogView -Context $context
    })

    $controls.AutoDetectButton.Add_Click({
        $selection = @($controls.WimGrid.SelectedItems)
        if ($selection.Count -eq 0) {
            $selection = @($wimItems)
        }
        Show-AutoDetectDialog -Context $context -Items $selection
    })

    $controls.SearchCatalogButton.Add_Click({
        Show-CatalogDialog -Context $context
    })

    $controls.ExitMenuItem.Add_Click({
        $window.Close()
    })

    $downloadHandler = {
        Show-CatalogDialog -Context $context
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
            } catch {
                # Best-effort cleanup; ignore failures on shutdown.
            }
        }
    })

    Refresh-ThrottleText -Context $context -Value $controls.ThrottleSlider.Value
    Update-Status -Context $context -Message 'Ready'

    $null = $window.ShowDialog()
}
