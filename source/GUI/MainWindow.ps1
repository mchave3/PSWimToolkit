#region Helper Functions

function Initialize-WindowState {
    <#
    .SYNOPSIS
        Initializes the application state object with workspace paths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string] $ModulePath
    )

    $moduleInfo = Get-Module -Name PSWimToolkit | Select-Object -First 1
    $moduleVersion = if ($moduleInfo) { $moduleInfo.Version.ToString() } else { 'Unknown' }

    $null = Get-ToolkitDataPath
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

    # Ensure all workspace directories exist
    $workspacePaths = @(
        $state.MountRoot
        $state.LogBase
        $state.ImportRoot
        $state.SxSRoot
        $state.OutputRoot
    )

    foreach ($path in $workspacePaths) {
        if ($path -and -not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    return $state
}

function Initialize-ControlDefaults {
    <#
    .SYNOPSIS
        Sets default values for controls based on application state.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable] $Controls,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    if ([string]::IsNullOrWhiteSpace($Controls.UpdatePathTextBox.Text)) {
        $Controls.UpdatePathTextBox.Text = $State.UpdatesRoot
    }

    if ([string]::IsNullOrWhiteSpace($Controls.SxSPathTextBox.Text)) {
        $Controls.SxSPathTextBox.Text = $State.SxSRoot
    }

    if ([string]::IsNullOrWhiteSpace($Controls.OutputPathTextBox.Text)) {
        $Controls.OutputPathTextBox.Text = $State.OutputRoot
    }

    # Style the Stop button
    $stopBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38)
    )
    $Controls.StopButton.Background = $stopBrush
    $Controls.StopButton.BorderBrush = $stopBrush
}

#endregion Helper Functions

#region Main Function

function Show-PSWimToolkitMainWindow {
    <#
    .SYNOPSIS
        Displays the main PSWimToolkit GUI window.
    .DESCRIPTION
        Loads and displays the WPF-based provisioning console for managing
        Windows images and integrating Microsoft Update Catalog updates.
    .PARAMETER ModulePath
        The path to the PSWimToolkit module.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ModulePath
    )

    #region Platform Validation

    if (-not $IsWindows) {
        throw 'The provisioning GUI is only supported on Windows platforms.'
    }

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        throw 'Start-PSWimToolkit must be invoked from an STA thread. Launch PowerShell with -STA and retry.'
    }

    #endregion Platform Validation

    #region Assembly Loading

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Controls.Ribbon

    #endregion Assembly Loading

    #region XAML Loading

    $xamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        throw "Unable to locate GUI layout at $xamlPath."
    }

    [xml] $xamlContent = Get-Content -LiteralPath $xamlPath -Raw
    $xamlReader = [System.Xml.XmlNodeReader]::new($xamlContent)
    $window = [System.Windows.Markup.XamlReader]::Load($xamlReader)

    #endregion XAML Loading

    #region Styles Loading

    $stylesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Styles.xaml'
    $stylesXmlDocument = $null
    $stylesLoadWarningEmitted = $false

    if (Test-Path -LiteralPath $stylesPath -PathType Leaf) {
        try {
            [xml] $stylesXmlDocument = Get-Content -LiteralPath $stylesPath -Raw
        }
        catch {
            $stylesLoadWarningEmitted = $true
            Write-Warning "Failed to load GUI styles: $($_.Exception.Message)"
        }
    }

    #endregion Styles Loading

    #region Dynamic Control Binding

    $controls = Get-WindowControls -Window $window -XamlDocument $xamlContent

    # Validate required controls are present
    $requiredControls = @(
        'WimGrid'
        'StartButton'
        'StopButton'
        'LogList'
        'ProgressList'
    )

    foreach ($requiredControl in $requiredControls) {
        if (-not $controls.ContainsKey($requiredControl)) {
            throw "Required GUI control '$requiredControl' was not found in XAML."
        }
    }

    #endregion Dynamic Control Binding

    #region Window Configuration

    $window.WindowState = [System.Windows.WindowState]::Maximized
    $window.Add_ContentRendered({
        param($sender, $eventArgs)
        $sender.Topmost = $true
        $sender.Activate()
        $sender.Topmost = $false
    })

    #endregion Window Configuration

    #region Data Collections

    $wimItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $controls.WimGrid.ItemsSource = $wimItems
    $controls.ProgressList.ItemsSource = $wimItems

    $logItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $controls.LogList.ItemsSource = $logItems

    $logItemStyle = $window.Resources['LogListViewItemStyle']
    if ($null -ne $logItemStyle) {
        $controls.LogList.ItemContainerStyle = $logItemStyle
    }

    #endregion Data Collections

    #region State Initialization

    $state = Initialize-WindowState -ModulePath $ModulePath
    Initialize-ControlDefaults -Controls $controls -State $state

    #endregion State Initialization

    #region Context Object

    $context = [pscustomobject]@{
        Window                   = $window
        Controls                 = $controls
        State                    = $state
        WimItems                 = $wimItems
        LogItems                 = $logItems
        StylesXmlDocument        = $stylesXmlDocument
        StylesLoadWarningEmitted = $stylesLoadWarningEmitted
        GuiRoot                  = $PSScriptRoot
    }

    #endregion Context Object

    #region Initialization

    Add-SharedGuiStyles -Context $context -Target $window
    Load-WimsFromImport -Context $context

    #endregion Initialization

    #region Event Handlers - Slider

    $controls.ThrottleSlider.Add_ValueChanged({
        param($sender, $args)
        Refresh-ThrottleText -Context $context -Value $sender.Value
    })

    #endregion Event Handlers - Slider

    #region Event Handlers - WIM Management

    $controls.AddWimButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'WIM images (*.wim)|*.wim|All files (*.*)|*.*'
        $dialog.Multiselect = $true

        if (-not $dialog.ShowDialog()) {
            return
        }

        $added = 0
        foreach ($file in $dialog.FileNames) {
            try {
                $destination = Copy-WimIntoImport -Context $context -SourcePath $file
                if (Add-WimEntry -Context $context -Path $destination) {
                    $added++
                }
            }
            catch {
                Write-Warning "Failed to import WIM '$file': $($_.Exception.Message)"
            }
        }

        $message = if ($added -gt 0) {
            "Imported {0} WIM file(s) into workspace." -f $added
        }
        else {
            'No WIM files were imported.'
        }
        Update-Status -Context $context -Message $message
    })

    $controls.ImportIsoButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'ISO images (*.iso)|*.iso|All files (*.*)|*.*'
        $dialog.Multiselect = $true

        if (-not $dialog.ShowDialog()) {
            return
        }

        Update-Status -Context $context -Message 'Importing ISO image(s)...'

        try {
            $imports = Import-WimFromIso -Path $dialog.FileNames -Destination $state.ImportRoot -ErrorAction Stop
            $added = 0

            foreach ($import in $imports) {
                if ([System.IO.Path]::GetExtension($import.Destination) -ne '.wim') {
                    continue
                }
                if (Add-WimEntry -Context $context -Path $import.Destination) {
                    $added++
                }
            }

            $message = if ($added -gt 0) {
                "Imported $added WIM file(s) from ISO."
            }
            else {
                'Import completed. No new WIM files were added.'
            }
            Update-Status -Context $context -Message $message
        }
        catch {
            $errorBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38)
            )
            Update-Status -Context $context -Message "ISO import failed: $($_.Exception.Message)" -Brush $errorBrush
        }
    })

    $controls.RemoveWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) {
            return
        }

        foreach ($item in @($selected)) {
            Remove-WimEntry -Context $context -Item $item | Out-Null
        }
    })

    $controls.DeleteWimButton.Add_Click({
        $selected = @($controls.WimGrid.SelectedItems)

        if (-not $selected -or $selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'Select at least one WIM before deleting from disk.',
                'PSWimToolkit',
                'OK',
                'Information'
            ) | Out-Null
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
            [System.Windows.MessageBox]::Show(
                'Select a WIM entry first.',
                'PSWimToolkit',
                'OK',
                'Information'
            ) | Out-Null
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

    #endregion Event Handlers - WIM Management

    #region Event Handlers - Folder Browsing

    $controls.BrowseUpdateButton.Add_Click({
        Open-FolderPath -Path $controls.UpdatePathTextBox.Text -DisplayName 'Update folder'
    })

    $controls.BrowseSxSButton.Add_Click({
        Open-FolderPath -Path $controls.SxSPathTextBox.Text -DisplayName 'SxS folder'
    })

    $controls.BrowseOutputButton.Add_Click({
        Open-FolderPath -Path $controls.OutputPathTextBox.Text -DisplayName 'Output folder'
    })

    #endregion Event Handlers - Folder Browsing

    #region Event Handlers - Provisioning

    $controls.StartButton.Add_Click({
        Start-Provisioning -Context $context
    })

    $controls.StopButton.Add_Click({
        Stop-Provisioning -Context $context
    })

    #endregion Event Handlers - Provisioning

    #region Event Handlers - Logging

    $controls.LogLevelComboBox.Add_SelectionChanged({
        Update-LogView -Context $context
    })

    $saveLogsHandler = {
        if ($state.AllLogData.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'No log entries available to save.',
                'PSWimToolkit',
                'OK',
                'Information'
            ) | Out-Null
            return
        }

        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
        $dialog.FileName = 'PSWimToolkit Provisioning Logs.txt'

        if ($dialog.ShowDialog()) {
            Save-LogsToFile -Context $context -Destination $dialog.FileName
        }
    }

    $clearLogsHandler = {
        Reset-LogCollections -Context $context
    }

    $controls.SaveLogsButton.Add_Click($saveLogsHandler)
    $controls.ClearLogsButton.Add_Click($clearLogsHandler)

    $controls.OpenLogFolderButton.Add_Click({
        if ($state.LogRoot -and (Test-Path -LiteralPath $state.LogRoot -PathType Container)) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $state.LogRoot | Out-Null
        }
        else {
            [System.Windows.MessageBox]::Show(
                'No log folder has been generated yet.',
                'PSWimToolkit',
                'OK',
                'Information'
            ) | Out-Null
        }
    })

    $controls.AutoScrollCheckBox.Add_Click({
        Update-LogView -Context $context
    })

    #endregion Event Handlers - Logging

    #region Event Handlers - Catalog

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

    #endregion Event Handlers - Catalog

    #region Event Handlers - Menu Items

    $controls.ExitMenuItem.Add_Click({
        $window.Close()
    })

    $controls.DownloadUpdatesMenuItem.Add_Click({
        Show-CatalogDialog -Context $context
    })

    $controls.ClearLogsMenuItem.Add_Click($clearLogsHandler)
    $controls.ExportLogsMenuItem.Add_Click($saveLogsHandler)

    $controls.ToggleLogViewMenuItem.Add_Checked({
        $controls.LogViewerGroup.Visibility = [System.Windows.Visibility]::Visible
    })

    $controls.ToggleLogViewMenuItem.Add_Unchecked({
        $controls.LogViewerGroup.Visibility = [System.Windows.Visibility]::Collapsed
    })

    $controls.AboutMenuItem.Add_Click({
        $aboutMessage = @"
PSWimToolkit
Version: $($state.ModuleVersion)
Author: Mickael CHAVE

Modern tooling to provision Windows images with catalog integration.
"@
        [System.Windows.MessageBox]::Show($aboutMessage, 'About PSWimToolkit', 'OK', 'Information') | Out-Null
    })

    $controls.DocumentationMenuItem.Add_Click({
        Start-Process -FilePath 'https://github.com/mchave3/PSWimToolkit' | Out-Null
    })

    #endregion Event Handlers - Menu Items

    #region Window Closing Handler

    $window.Add_Closing({
        if ($state.Timer) {
            $state.Timer.Stop()
        }

        if ($state.Job) {
            try {
                Stop-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
                Remove-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Best-effort cleanup; ignore failures on shutdown.
            }
        }
    })

    #endregion Window Closing Handler

    #region Show Window

    Refresh-ThrottleText -Context $context -Value $controls.ThrottleSlider.Value
    Update-Status -Context $context -Message 'Ready'

    $null = $window.ShowDialog()

    #endregion Show Window
}

#endregion Main Function
