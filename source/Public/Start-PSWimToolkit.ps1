function Start-PSWimToolkit {
    [CmdletBinding()]
    param ()

    $module = Get-Module -Name PSWimToolkit
    if (-not $module) {
        throw 'PSWimToolkit module must be imported before launching the GUI.'
    }

    $guiPath = Join-Path -Path $module.ModuleBase -ChildPath 'GUI/MainWindow.ps1'
    $resolvedGuiPath = Resolve-Path -LiteralPath $guiPath -ErrorAction Stop

    . $resolvedGuiPath

    Show-PSWimToolkitMainWindow -ModulePath $module.Path
}
