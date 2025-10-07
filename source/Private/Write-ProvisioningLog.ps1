function Write-ProvisioningLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Success', 'Stage')]
        [string] $Type = 'Info',

        [Parameter()]
        [string] $Source,

        [switch] $NoConsole,
        [switch] $NoFile
    )

    if (-not (Get-Variable -Name 'LogConfig' -Scope Script -ErrorAction SilentlyContinue)) {
        Initialize-LogFile
    }

    $levelRanking = @{
        Debug   = 0
        Info    = 1
        Stage   = 2
        Success = 2
        Warning = 3
        Error   = 4
    }

    $defaultLevel = $script:LogConfig.DefaultLogLevel
    if (-not $levelRanking.ContainsKey($defaultLevel)) {
        $defaultLevel = 'Info'
    }

    $shouldLog = ($levelRanking[$Type] -ge $levelRanking[$defaultLevel]) -or ($Type -eq 'Debug')
    if (-not $shouldLog) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $levelLabel = $Type.ToUpperInvariant()
    $sourceLabel = if ($Source) { $Source } else { 'PSWimToolkit' }
    $entry = "[{0}] [{1}] [{2}] {3}" -f $timestamp, $levelLabel, $sourceLabel, $Message

    if (-not $NoConsole -and $script:LogConfig.EnableConsole) {
        switch ($Type) {
            'Debug' { Write-Verbose -Message $entry }
            'Info' { Write-Host $entry -ForegroundColor White }
            'Warning' { Write-Host $entry -ForegroundColor Yellow }
            'Error' { Write-Host $entry -ForegroundColor Red }
            'Success' { Write-Host $entry -ForegroundColor Green }
            'Stage' { Write-Host $entry -ForegroundColor Cyan }
        }
    }

    if (-not $NoFile -and $script:LogConfig.EnableFile) {
        if (-not (Get-Variable -Name 'LogMutex' -Scope Script -ErrorAction SilentlyContinue)) {
            $script:LogMutex = New-Object System.Object
        }

        [System.Threading.Monitor]::Enter($script:LogMutex)
        try {
            $logFile = Get-LogFilePath
            if ($logFile) {
                Add-Content -Path $logFile -Value $entry -Encoding UTF8
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($script:LogMutex)
        }
    }
}
