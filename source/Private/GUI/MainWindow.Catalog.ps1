function Show-CatalogDialog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    #region Dialog Loading

    $dialogPath = Join-Path -Path $Context.GuiRoot -ChildPath 'CatalogDialog.xaml'

    if (-not (Test-Path -LiteralPath $dialogPath -PathType Leaf)) {
        throw "Unable to locate catalog dialog layout at $dialogPath."
    }

    [xml] $dialogXml = Get-Content -LiteralPath $dialogPath -Raw
    $dialogReader = [System.Xml.XmlNodeReader]::new($dialogXml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($dialogReader)
    $dialog.Owner = $Context.Window

    Add-SharedGuiStyles -Context $Context -Target $dialog

    #endregion Dialog Loading

    #region Dynamic Control Binding

    $catalogControls = Get-WindowControls -Window $dialog -XamlDocument $dialogXml

    # Validate required controls
    $requiredControls = @(
        'SearchTextBox'
        'SearchButton'
        'OperatingSystemComboBox'
        'ReleaseComboBox'
        'ArchitectureComboBox'
        'UpdateTypeComboBox'
        'ResultsList'
        'DownloadButton'
        'CloseButton'
        'CatalogStatusText'
    )

    foreach ($requiredControl in $requiredControls) {
        if (-not $catalogControls.ContainsKey($requiredControl)) {
            throw "Required catalog dialog control '$requiredControl' was not found in XAML."
        }
    }

    #endregion Dynamic Control Binding

    if (-not $Context.State.CatalogFacets) {
        $Context.State.CatalogFacets = Get-ToolkitCatalogData
    }

    $catalogControls.IncludePreviewCheckBox.IsChecked = $Context.Controls.IncludePreviewCheckBox.IsChecked

    $operatingSystems = $Context.State.CatalogFacets.OperatingSystems
    $architectures = @('All') + $Context.State.CatalogFacets.Architectures
    $updateTypes = @('Any') + $Context.State.CatalogFacets.UpdateTypes

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
            [Parameter(Mandatory)]
            [string] $OperatingSystemName,

            [Parameter(Mandatory)]
            [psobject] $Context,

            [Parameter(Mandatory)]
            [hashtable] $Controls,

            [Parameter(Mandatory)]
            [object[]] $OperatingSystems
        )

        $Controls.ReleaseComboBox.Items.Clear()

        if (-not $OperatingSystemName) {
            return
        }

        $osEntry = $OperatingSystems | Where-Object { $_.Name -eq $OperatingSystemName } | Select-Object -First 1

        if (-not $osEntry) {
            return
        }

        foreach ($release in $osEntry.Releases) {
            $null = $Controls.ReleaseComboBox.Items.Add($release.Name)
        }

        $Controls.ReleaseComboBox.SelectedIndex = 0
    }

    function Set-CatalogStatus {
        param (
            [Parameter(Mandatory)]
            [hashtable] $Controls,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message,

            [Parameter()]
            [Windows.Media.Brush] $Brush
        )

        if (-not $Brush) {
            $Brush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(0x2B, 0x57, 0x9A)
            )
        }

        $Controls.CatalogStatusText.Text = $Message
        $Controls.CatalogStatusText.Foreground = $Brush
    }

    $catalogControls.OperatingSystemComboBox.Add_SelectionChanged({
        $selectedOs = [string]$catalogControls.OperatingSystemComboBox.SelectedItem
        Set-ReleaseOptions -OperatingSystemName $selectedOs -Context $Context -Controls $catalogControls -OperatingSystems $operatingSystems
    })

    if ($catalogControls.OperatingSystemComboBox.Items.Count -gt 0) {
        $catalogControls.OperatingSystemComboBox.SelectedItem = 'Windows 11'

        if (-not $catalogControls.OperatingSystemComboBox.SelectedItem) {
            $catalogControls.OperatingSystemComboBox.SelectedIndex = 0
        }
    }

    $resultItems = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $catalogControls.ResultsList.ItemsSource = $resultItems

    $catalogControls.SearchButton.Add_Click({
        $searchText = $catalogControls.SearchTextBox.Text
        $selectedOs = [string]$catalogControls.OperatingSystemComboBox.SelectedItem
        $selectedRelease = [string]$catalogControls.ReleaseComboBox.SelectedItem
        $selectedArchitecture = [string]$catalogControls.ArchitectureComboBox.SelectedItem
        $selectedUpdateType = [string]$catalogControls.UpdateTypeComboBox.SelectedItem
        $includePreview = [bool]$catalogControls.IncludePreviewCheckBox.IsChecked
        $includeDynamic = [bool]$catalogControls.IncludeDynamicCheckBox.IsChecked
        $getFramework = [bool]$catalogControls.GetFrameworkCheckBox.IsChecked
        $excludeFramework = [bool]$catalogControls.ExcludeFrameworkCheckBox.IsChecked
        $strict = [bool]$catalogControls.StrictCheckBox.IsChecked
        $includeFileNames = [bool]$catalogControls.IncludeFileNamesCheckBox.IsChecked
        $allPages = [bool]$catalogControls.AllPagesCheckBox.IsChecked

        $params = @{
            IncludePreview  = $includePreview
            IncludeDynamic  = $includeDynamic
            Strict          = $strict
            IncludeFileName = $includeFileNames
            AllPages        = $allPages
        }

        if (-not [string]::IsNullOrWhiteSpace($searchText)) {
            $params['Search'] = $searchText
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedOs)) {
            $params['OperatingSystem'] = $selectedOs
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedRelease)) {
            $params['Version'] = $selectedRelease
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedArchitecture) -and $selectedArchitecture -ne 'All') {
            $params['Architecture'] = $selectedArchitecture
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedUpdateType) -and $selectedUpdateType -ne 'Any') {
            $params['UpdateType'] = $selectedUpdateType
        }

        if ($getFramework) {
            $params['IncludeFramework'] = $true
        }

        if ($excludeFramework) {
            $params['ExcludeFramework'] = $true
        }

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
            '{0} {1}' -f $params['OperatingSystem'], ($params['Version'] ?? '')
        } else {
            $params['Search']
        }

        $catalogControls.SearchButton.IsEnabled = $false
        $resultItems.Clear()
        Set-CatalogStatus -Controls $catalogControls -Message ("Searching catalog for {0}..." -f $descriptor)

        try {
            $found = Find-WindowsUpdate @params

            foreach ($update in $found) {
                $resultItems.Add($update) | Out-Null
            }

            if ($resultItems.Count -eq 0) {
                Set-CatalogStatus -Controls $catalogControls -Message 'No updates found for the specified criteria.'
            } else {
                Set-CatalogStatus -Controls $catalogControls -Message ("Found {0} update(s)." -f $resultItems.Count)
            }
        } catch {
            $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38))
            Set-CatalogStatus -Controls $catalogControls -Message "Catalog search failed: $($_.Exception.Message)" -Brush $errorBrush
        } finally {
            $catalogControls.SearchButton.IsEnabled = $true
        }
    })

    $catalogControls.DownloadButton.Add_Click({
        $selected = @($catalogControls.ResultsList.SelectedItems)

        if (-not $selected -or $selected.Count -eq 0) {
            Set-CatalogStatus -Controls $catalogControls -Message 'Select one or more updates to download.'
            return
        }

        $destination = $Context.Controls.UpdatePathTextBox.Text

        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            $folderDialog = [System.Windows.Forms.FolderBrowserDialog]::new()
            $folderDialog.Description = 'Select destination folder for downloaded updates'

            if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $destination = $folderDialog.SelectedPath
                $Context.Controls.UpdatePathTextBox.Text = $destination
            } else {
                Set-CatalogStatus -Controls $catalogControls -Message 'Download cancelled.'
                return
            }
        }

        try {
            Set-CatalogStatus -Controls $catalogControls -Message 'Downloading selected updates...'
            Save-WindowsUpdate -InputObject $selected -Destination $destination -DownloadAll:$true -Force:$true -ErrorAction Stop | Out-Null
            Set-CatalogStatus -Controls $catalogControls -Message ("Downloaded {0} update(s) to {1}." -f $selected.Count, $destination)
            $Context.Controls.UpdatePathTextBox.Text = $destination
        } catch {
            $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38))
            Set-CatalogStatus -Controls $catalogControls -Message "Download failed: $($_.Exception.Message)" -Brush $errorBrush
        }
    })

    $catalogControls.CopyButton.Add_Click({
        $selected = @($catalogControls.ResultsList.SelectedItems)

        if (-not $selected -or $selected.Count -eq 0) {
            Set-CatalogStatus -Controls $catalogControls -Message 'Select an update to copy its details.'
            return
        }

        $text = $selected | ForEach-Object {
            "Title: $($_.Title)`r`nClassification: $($_.Classification)`r`nLast Updated: $($_.LastUpdated)`r`nSize: $($_.Size)`r`nProducts: $($_.Products)`r`nGuid: $($_.Guid)`r`n"
        }

        [System.Windows.Clipboard]::SetText($text -join "`r`n")
        Set-CatalogStatus -Controls $catalogControls -Message 'Selected update details copied to clipboard.'
    })

    $catalogControls.ResultsList.Add_MouseDoubleClick({
        $catalogControls.CopyButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    })

    $catalogControls.CloseButton.Add_Click({
        $dialog.Close()
    })

    $null = $dialog.ShowDialog()
    $Context.Controls.IncludePreviewCheckBox.IsChecked = $catalogControls.IncludePreviewCheckBox.IsChecked
}
