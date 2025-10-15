function Get-LogFilePath {
    [CmdletBinding()]
    param ()

    $currentFile = (Get-Variable -Name 'CurrentLogFile' -Scope Script -ErrorAction SilentlyContinue)?.Value

    if (-not $currentFile -or -not (Test-Path -LiteralPath $currentFile -PathType Leaf)) {
        return Initialize-LogFile -ForceNew
    }

    $maxSize = [int64]$script:LogConfig.MaxFileSizeBytes
    if ($maxSize -gt 0) {
        try {
            $fileInfo = Get-Item -LiteralPath $currentFile -ErrorAction Stop
            if ($fileInfo.Length -ge $maxSize) {
                return Initialize-LogFile -ForceNew
            }
        } catch {
            return Initialize-LogFile -ForceNew
        }
    }

    return $currentFile
}
