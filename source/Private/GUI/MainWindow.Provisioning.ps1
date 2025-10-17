function Prepare-Timer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    if ($Context.State.Timer) {
        return
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)

    $timer.Add_Tick({
        Harvest-Logs -Context $Context

        $job = $Context.State.Job
        if (-not $job) {
            return
        }

        switch ($job.State) {
            'Completed' { Finish-Provisioning -Context $Context -Status 'Completed' }
            'Failed'    { Finish-Provisioning -Context $Context -Status 'Failed' }
            'Stopped'   { Finish-Provisioning -Context $Context -Status 'Stopped' }
        }
    })

    $Context.State.Timer = $timer
}

function Finish-Provisioning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('Completed', 'Failed', 'Stopped')]
        [string] $Status
    )

    $state = $Context.State
    $controls = $Context.Controls
    $wimItems = $Context.WimItems
    $job = $state.Job

    if (-not $job) {
        return
    }

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

    Harvest-Logs -Context $Context

    $controls.StopButton.IsEnabled = $false
    Enable-ControlSet -Context $Context -Enabled $true
    $controls.OverallProgressBar.IsIndeterminate = $false
    $controls.OverallProgressBar.Value = 100

    if ($results) {
        foreach ($result in $results) {
            $matched = $wimItems | Where-Object { $_.Path -eq $result.WimImage.Path }
            if (-not $matched) {
                continue
            }

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
        $successBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x10, 0x7C, 0x10))
        Update-Status -Context $Context -Message ("Provisioning completed for {0} WIM image(s)." -f $results.Count) -Brush $successBrush
        return
    }

    foreach ($item in $wimItems) {
        if ($item.Status -ne 'Running' -and $item.Status -ne 'Queued') {
            continue
        }

        $item.Status = switch ($Status) {
            'Stopped' { 'Cancelled' }
            'Failed'  { 'Failed' }
            default   { 'Completed' }
        }

        switch ($item.Status) {
            'Failed'    { $item.Details = 'Provisioning failed.' }
            'Cancelled' { $item.Details = 'Operation cancelled by user.' }
        }
    }

    $controls.WimGrid.Items.Refresh()
    $controls.ProgressList.Items.Refresh()
    $errorBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD1, 0x34, 0x38))
    Update-Status -Context $Context -Message "Provisioning $Status. Review logs for details." -Brush $errorBrush
}

function Start-Provisioning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $controls = $Context.Controls
    $state = $Context.State
    $wimItems = $Context.WimItems

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

    Reset-LogCollections -Context $Context
    $controls.LogPathTextBlock.Text = "Logs folder: $logDirectory"

    foreach ($item in $wimItems) {
        $item.Status = 'Queued'
        $item.Details = ''
    }

    $controls.WimGrid.Items.Refresh()
    $controls.ProgressList.Items.Refresh()

    $controls.OverallProgressBar.IsIndeterminate = $true
    $controls.OverallProgressBar.Value = 0

    Enable-ControlSet -Context $Context -Enabled $false
    $controls.StopButton.IsEnabled = $true

    Refresh-ThrottleText -Context $Context -Value $controls.ThrottleSlider.Value
    Update-Status -Context $Context -Message 'Provisioning started...'

    $jobEntries = foreach ($item in $wimItems) {
        [pscustomobject]@{
            Name  = $item.Name
            Path  = $item.Path
            Index = [int]$item.Index
        }
    }

    $indexMap = @{}
    foreach ($entry in $jobEntries) {
        if ($indexMap.ContainsKey($entry.Name)) {
            continue
        }

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
    Prepare-Timer -Context $Context
    $state.Timer.Start()
}

function Stop-Provisioning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $job = $Context.State.Job
    if (-not $job) {
        return
    }

    try {
        Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed to stop provisioning job: $($_.Exception.Message)"
    }

    Finish-Provisioning -Context $Context -Status 'Stopped'
}
