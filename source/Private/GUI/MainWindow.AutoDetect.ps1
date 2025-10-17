function Show-AutoDetectDialog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [psobject[]] $Items
    )

    if (-not $Items -or $Items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one WIM entry before running auto detect.', 'PSWimToolkit', 'OK', 'Information') | Out-Null
        return
    }

    $dialogPath = Join-Path -Path $Context.GuiRoot -ChildPath 'AutoDetectDialog.xaml'

    if (-not (Test-Path -LiteralPath $dialogPath -PathType Leaf)) {
        throw "Unable to locate auto detect dialog layout at $dialogPath."
    }

    [xml]$dialogXml = Get-Content -LiteralPath $dialogPath -Raw
    $dialogReader = New-Object System.Xml.XmlNodeReader $dialogXml
    $dialog = [Windows.Markup.XamlReader]::Load($dialogReader)
    $dialog.Owner = $Context.Window

    Add-SharedGuiStyles -Context $Context -Target $dialog

    $detectControls = @{
        DownloadPathTextBox              = $dialog.FindName('DownloadPathTextBox')
        BrowseDownloadPathButton         = $dialog.FindName('BrowseDownloadPathButton')
        AutoDetectUpdateTypeComboBox     = $dialog.FindName('AutoDetectUpdateTypeComboBox')
        AutoDetectIncludePreviewCheckBox = $dialog.FindName('AutoDetectIncludePreviewCheckBox')
        AutoDetectResults                = $dialog.FindName('AutoDetectResults')
        QueueDownloadButton              = $dialog.FindName('QueueDownloadButton')
        CopyUpdatesButton                = $dialog.FindName('CopyUpdatesButton')
        CloseButton                      = $dialog.FindName('CloseButton')
        StatusText                       = $dialog.FindName('AutoDetectStatusText')
    }

    foreach ($key in $detectControls.Keys) {
        if (-not $detectControls[$key]) {
            throw "Unable to locate auto-detect dialog control '$key'."
        }
    }

    if (-not $Context.State.CatalogFacets) {
        $Context.State.CatalogFacets = Get-ToolkitCatalogData
    }

    $detectControls.AutoDetectUpdateTypeComboBox.Items.Clear()

    foreach ($type in @('Cumulative Updates') + $Context.State.CatalogFacets.UpdateTypes) {
        if (-not $detectControls.AutoDetectUpdateTypeComboBox.Items.Contains($type)) {
            $null = $detectControls.AutoDetectUpdateTypeComboBox.Items.Add($type)
        }
    }

    $detectControls.AutoDetectUpdateTypeComboBox.SelectedItem = 'Cumulative Updates'

    $downloadPath = if (-not [string]::IsNullOrWhiteSpace($Context.Controls.UpdatePathTextBox.Text)) {
        $Context.Controls.UpdatePathTextBox.Text
    } else {
        $Context.State.ImportRoot
    }

    $detectControls.DownloadPathTextBox.Text = $downloadPath
    $detectControls.AutoDetectIncludePreviewCheckBox.IsChecked = $Context.Controls.IncludePreviewCheckBox.IsChecked

    $resultCollection = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    $detectControls.AutoDetectResults.ItemsSource = $resultCollection

    function Update-AutoDetectStatus {
        param (
            [Parameter(Mandatory)]
            [hashtable] $Controls,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message
        )

        $Controls.StatusText.Text = $Message
    }

    function Get-UpdateKbValue {
        param (
            [Parameter()]
            [psobject] $Update
        )

        if (-not $Update) {
            return $null
        }

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
        param (
            [Parameter(Mandatory)]
            [psobject] $Context,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [psobject[]] $Items,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.ObjectModel.ObservableCollection[psobject]] $Results,

            [Parameter(Mandatory)]
            [hashtable] $Controls
        )

        $Results.Clear()
        Update-AutoDetectStatus -Controls $Controls -Message 'Detecting updates...'

        $groups = $Items | Group-Object -Property Path
        $includePreview = [bool]$Controls.AutoDetectIncludePreviewCheckBox.IsChecked
        $selectedType = [string]$Controls.AutoDetectUpdateTypeComboBox.SelectedItem
        $typeFilter = if ([string]::IsNullOrWhiteSpace($selectedType)) { @('Cumulative Updates') } else { @($selectedType) }

        foreach ($group in $groups) {
            $indices = @(
                $group.Group |
                    ForEach-Object { $_.Index } |
                    Where-Object { $_ -ne $null } |
                    Select-Object -Unique
            )

            $arguments = @{
                WimPath        = $group.Name
                Indices        = $indices
                IncludePreview = $includePreview
                UpdateTypes    = $typeFilter
            }

            try {
                $applicable = Get-WimApplicableUpdate @arguments
            } catch {
                Update-AutoDetectStatus -Controls $Controls -Message "Auto detect failed for $($group.Name): $($_.Exception.Message)"
                continue
            }

            foreach ($match in $applicable) {
                if (-not $match.Update) {
                    continue
                }

                $kb = Get-UpdateKbValue -Update $match.Update
                $title = $match.Update.Title
                $classification = $match.Update.Classification

                $Results.Add([pscustomobject]@{
                    WimPath         = $match.WimPath
                    WimName         = $match.WimName
                    Index           = $match.WimIndex
                    OperatingSystem = $match.OperatingSystem
                    Release         = $match.Release
                    Architecture    = $match.Architecture
                    UpdateType      = ($match.UpdateType -join ', ')
                    KB              = $kb
                    Title           = $title
                    Classification  = $classification
                    LastUpdated     = $match.Update.LastUpdated
                    Guid            = $match.Update.Guid
                    CatalogUpdate   = $match.Update
                }) | Out-Null
            }
        }

        if ($Results.Count -eq 0) {
            Update-AutoDetectStatus -Controls $Controls -Message 'No catalog updates detected for the selected WIM images.'
        } else {
            Update-AutoDetectStatus -Controls $Controls -Message "Detected $($Results.Count) update(s)."
        }
    }

    Invoke-AutoDetect -Context $Context -Items $Items -Results $resultCollection -Controls $detectControls

    $detectControls.AutoDetectUpdateTypeComboBox.Add_SelectionChanged({
        Invoke-AutoDetect -Context $Context -Items $Items -Results $resultCollection -Controls $detectControls
    })

    $detectControls.AutoDetectIncludePreviewCheckBox.Add_Click({
        Invoke-AutoDetect -Context $Context -Items $Items -Results $resultCollection -Controls $detectControls
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
            Update-AutoDetectStatus -Controls $detectControls -Message 'Downloading detected updates...'
            Save-WindowsUpdate -InputObject $updates -Destination $destination -DownloadAll:$true -Force:$true -ErrorAction Stop | Out-Null
            Update-AutoDetectStatus -Controls $detectControls -Message "Downloaded $($updates.Count) update(s) to $destination."
            $Context.Controls.UpdatePathTextBox.Text = $destination
        } catch {
            Update-AutoDetectStatus -Controls $detectControls -Message "Download failed: $($_.Exception.Message)"
        }
    })

    $detectControls.CopyUpdatesButton.Add_Click({
        $selection = @($detectControls.AutoDetectResults.SelectedItems)

        if ($selection.Count -eq 0) {
            $selection = @($resultCollection)
        }

        if ($selection.Count -eq 0) {
            return
        }

        $buffer = $selection | ForEach-Object {
            "WIM: {0}`r`nIndex: {1}`r`nKB: {2}`r`nTitle: {3}`r`nClassification: {4}`r`nLast Updated: {5}`r`nGuid: {6}" -f $_.WimName, $_.Index, $_.KB, $_.Title, $_.Classification, $_.LastUpdated, $_.Guid
        }

        [System.Windows.Clipboard]::SetText(($buffer -join "`r`n`r`n"))
        Update-AutoDetectStatus -Controls $detectControls -Message "Copied $($selection.Count) entries."
    })

    $detectControls.CloseButton.Add_Click({
        $dialog.Close()
    })

    $null = $dialog.ShowDialog()
}
