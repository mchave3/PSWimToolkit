. (Join-Path -Path $PSScriptRoot -ChildPath 'Private\Bootstrap\00.Initialize-ToolkitEnvironment.ps1')

$privateRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$bootstrapScript = Get-Item -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Bootstrap\00.Initialize-ToolkitEnvironment.ps1') -ErrorAction SilentlyContinue

$loggingScripts = Get-ChildItem -Path (Join-Path -Path $privateRoot -ChildPath 'Logging') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
foreach ($file in $loggingScripts) {
    . $file.FullName
}

$preLoadedPrivateScripts = @()
if ($bootstrapScript) {
    $preLoadedPrivateScripts += $bootstrapScript.FullName
}
if ($loggingScripts) {
    $preLoadedPrivateScripts += ($loggingScripts | ForEach-Object { $_.FullName })
}

$moduleLoadStart = Get-Date

try {
    Write-ToolkitLog -Message "=== PSWimToolkit Module Loading ===" -Type Stage -Source 'PSWimToolkit'

    $classFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Classes') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    Write-ToolkitLog -Message "Loading $($classFiles.Count) class file(s)..." -Type Debug -Source 'PSWimToolkit'
    foreach ($file in $classFiles) {
        . $file.FullName
        Write-ToolkitLog -Message "Loaded class: $($file.BaseName)" -Type Debug -Source 'PSWimToolkit'
    }

    $privateFunctions = Get-ChildItem -Path $privateRoot -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not ($preLoadedPrivateScripts -contains $_.FullName) } |
        Sort-Object -Property DirectoryName, Name

    Write-ToolkitLog -Message "Loading $($privateFunctions.Count) private function(s)..." -Type Debug -Source 'PSWimToolkit'
    foreach ($file in $privateFunctions) {
        . $file.FullName
        Write-ToolkitLog -Message "Loaded private function: $($file.BaseName)" -Type Debug -Source 'PSWimToolkit'
    }

    $publicFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    Write-ToolkitLog -Message "Loading $($publicFunctions.Count) public function(s)..." -Type Debug -Source 'PSWimToolkit'
    foreach ($file in $publicFunctions) {
        . $file.FullName
        Write-ToolkitLog -Message "Loaded public function: $($file.BaseName)" -Type Debug -Source 'PSWimToolkit'
    }

    $publicFunctionNames = @()
    if ($publicFunctions) {
        $publicFunctionNames = $publicFunctions | ForEach-Object { $_.BaseName }
    }

    if ($publicFunctionNames.Count -gt 0) {
        Export-ModuleMember -Function $publicFunctionNames
        Write-ToolkitLog -Message "Exported $($publicFunctionNames.Count) public function(s)" -Type Info -Source 'PSWimToolkit'
    } else {
        Export-ModuleMember -Function @()
        Write-ToolkitLog -Message "No public functions to export" -Type Warning -Source 'PSWimToolkit'
    }

    $moduleLoadDuration = ((Get-Date) - $moduleLoadStart).TotalMilliseconds
    Write-ToolkitLog -Message "=== PSWimToolkit Module Loaded Successfully in $([Math]::Round($moduleLoadDuration, 2))ms ===" -Type Success -Source 'PSWimToolkit'
}
catch {
    Write-Error -Message "Failed to initialize PSWimToolkit: $_"
    throw
}

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Write-ToolkitLog -Message "=== PSWimToolkit Module Unloading ===" -Type Info -Source 'PSWimToolkit'

    if ($script:LogMutex) {
        try {
            $script:LogMutex = $null
        } catch {
            Write-Warning "Failed to cleanup log mutex: $_"
        }
    }

    Write-ToolkitLog -Message "=== PSWimToolkit Module Unloaded ===" -Type Info -Source 'PSWimToolkit'
}
