function Start-PSWimToolkit {
    [CmdletBinding()]
    param ()

    Clear-Host

    Write-ToolkitLog -Message "=== Starting PSWimToolkit GUI ===" -Type Stage -Source 'Start-PSWimToolkit'

    $module = Get-Module -Name PSWimToolkit
    if (-not $module) {
        Write-ToolkitLog -Message "PSWimToolkit module must be imported before launching the GUI" -Type Error -Source 'Start-PSWimToolkit'
        throw 'PSWimToolkit module must be imported before launching the GUI.'
    }

    Write-ToolkitLog -Message "Module loaded from: $($module.Path)" -Type Debug -Source 'Start-PSWimToolkit'
    Write-ToolkitLog -Message "Launching main window..." -Type Info -Source 'Start-PSWimToolkit'

    Show-PSWimToolkitMainWindow -ModulePath $module.Path

    Write-ToolkitLog -Message "=== PSWimToolkit GUI Closed ===" -Type Info -Source 'Start-PSWimToolkit'
}
