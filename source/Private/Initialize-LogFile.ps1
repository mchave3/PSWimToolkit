function Initialize-LogFile {
    [CmdletBinding()]
    param (
        [switch] $ForceNew
    )

    if (-not (Get-Variable -Name 'LogConfig' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:LogConfig = [ordered]@{
            DefaultDirectory   = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'PSWimToolkit\Logs'
            MaxFileSizeBytes   = 10MB
            MaxFileCount       = 10
            EnableConsole      = $true
            EnableFile         = $true
            DefaultLogLevel    = 'Info'
            SupportedLogLevels = @('Debug','Info','Warning','Error','Success','Stage')
        }
    }

    $logDirectory = $script:LogConfig.DefaultDirectory
    if ([string]::IsNullOrWhiteSpace($logDirectory)) {
        $logDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'PSWimToolkit\Logs'
        $script:LogConfig.DefaultDirectory = $logDirectory
    }

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not $ForceNew -and $script:CurrentLogFile -and (Test-Path -LiteralPath $script:CurrentLogFile -PathType Leaf)) {
        return $script:CurrentLogFile
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "PSWimToolkit_$timestamp.log"
    $logPath = Join-Path -Path $logDirectory -ChildPath $fileName
    New-Item -Path $logPath -ItemType File -Force | Out-Null

    $script:CurrentLogFile = $logPath

    $maxCount = [int]($script:LogConfig.MaxFileCount)
    if ($maxCount -gt 0) {
        $logs = Get-ChildItem -Path $logDirectory -Filter 'PSWimToolkit_*.log' -File -ErrorAction SilentlyContinue | Sort-Object CreationTime
        if ($logs) {
            $excess = $logs.Count - $maxCount
            if ($excess -gt 0) {
                $logs | Select-Object -First $excess | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $script:CurrentLogFile
}
