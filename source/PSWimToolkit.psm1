. (Join-Path -Path $PSScriptRoot -ChildPath 'Private\Bootstrap\Initialize-PSWimToolkit.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Private\Bootstrap\Uninitialize-PSWimToolkit.ps1')

Initialize-PSWimToolkit -ModuleRoot $ExecutionContext.SessionState.Module.ModuleBase

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Uninitialize-PSWimToolkit
}
