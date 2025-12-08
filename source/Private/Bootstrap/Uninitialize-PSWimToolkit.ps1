function Uninitialize-PSWimToolkit {
    [CmdletBinding()]
    param()

    # Use Write-Verbose with -Verbose flag since Write-ToolkitLog may not be available during unload
    $canLog = Get-Command -Name 'Write-ToolkitLog' -ErrorAction SilentlyContinue

    if ($canLog) {
        try {
            Write-ToolkitLog -Message "=== PSWimToolkit Module Unloading ===" -Type Info -Source 'PSWimToolkit'
        } catch {
            Write-Verbose "=== PSWimToolkit Module Unloading ===" -Verbose
        }
    } else {
        Write-Verbose "=== PSWimToolkit Module Unloading ===" -Verbose
    }

    # Log completion BEFORE cleaning up (otherwise logging won't work)
    if ($canLog) {
        try {
            Write-ToolkitLog -Message "=== PSWimToolkit Module Unloaded ===" -Type Info -Source 'PSWimToolkit'
        } catch {
            Write-Verbose "=== PSWimToolkit Module Unloaded ===" -Verbose
        }
    } else {
        Write-Verbose "=== PSWimToolkit Module Unloaded ===" -Verbose
    }

    # Clean up script-scoped variables AFTER logging
    $variablesToClean = @(
        'LogMutex',
        'LogConfig',
        'CurrentLogFile',
        'WorkspacePaths',
        'ProgramDataRoot',
        'ModuleRoot',
        'TypesRoot',
        'DefaultSecurityProtocol'
    )
    foreach ($varName in $variablesToClean) {
        Remove-Variable -Name $varName -Scope Script -ErrorAction SilentlyContinue
    }
}
