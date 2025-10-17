function Reset-LogCollections {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $Context.State.KnownLogEntries.Clear() | Out-Null
    $Context.State.AllLogData.Clear()
    $Context.LogItems.Clear()

    Update-LogView -Context $Context
}

function Save-LogsToFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Destination
    )

    if ($Context.State.AllLogData.Count -eq 0) {
        return
    }

    $lines = $Context.State.AllLogData |
        Sort-Object -Property Timestamp |
        ForEach-Object {
            '[{0}] [{1}] [{2}] {3}' -f $_.Timestamp, $_.Level, $_.Source, $_.Message
        }

    Set-Content -LiteralPath $Destination -Value $lines -Encoding utf8
}

function Update-LogView {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $controls = $Context.Controls
    $logItems = $Context.LogItems

    $filter = ($controls.LogLevelComboBox.SelectedItem)?.Content
    if (-not $filter) {
        $filter = 'All'
    }

    $displayItems = if ($filter -eq 'All') {
        $Context.State.AllLogData
    } else {
        $Context.State.AllLogData | Where-Object { $_.Level -eq $filter }
    }

    $ordered = $displayItems | Sort-Object -Property Timestamp | Select-Object -Last 500
    $logItems.Clear()

    foreach ($entry in $ordered) {
        $logItems.Add($entry) | Out-Null
    }

    if ([bool]$controls.AutoScrollCheckBox.IsChecked -and $logItems.Count -gt 0) {
        $controls.LogList.ScrollIntoView($logItems[$logItems.Count - 1])
    }
}

function Harvest-Logs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context
    )

    $state = $Context.State

    if (-not $state.LogRoot -or -not (Test-Path -LiteralPath $state.LogRoot -PathType Container)) {
        return
    }

    $logFiles = Get-ChildItem -LiteralPath $state.LogRoot -Filter *.log -ErrorAction SilentlyContinue
    $regex = '^\[(?<Timestamp>.+?)\]\s+\[(?<Level>.+?)\]\s+\[(?<Source>.+?)\]\s+(?<Message>.*)$'

    foreach ($file in $logFiles) {
        $lines = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $key = '{0}|{1}' -f $file.FullName, $line

            if (-not $state.KnownLogEntries.Add($key)) {
                continue
            }

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

    Update-LogView -Context $Context
}
