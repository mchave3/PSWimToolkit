Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name 'ModuleRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
    if (-not $moduleBase) {
        $moduleBase = Split-Path -Parent $PSCommandPath
    }
    if (-not $moduleBase) {
        $moduleBase = $PSScriptRoot
    }

    $script:ModuleRoot = $moduleBase
}

if (-not (Get-Variable -Name 'TypesRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TypesRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Types'
}

$commonDataRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
$defaultDataRoot = Join-Path -Path $commonDataRoot -ChildPath 'PSWimToolkit'
if (-not (Get-Variable -Name 'ProgramDataRoot' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:ProgramDataRoot) {
    $script:ProgramDataRoot = $defaultDataRoot
}

$workspaceDefaults = [ordered]@{
    DataRoot = $script:ProgramDataRoot
    Logs     = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Logs'
    Updates  = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Updates'
    Mounts   = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Mounts'
    Imports  = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Imports'
}

if (-not (Get-Variable -Name 'WorkspacePaths' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:WorkspacePaths) {
    $script:WorkspacePaths = [ordered]@{}
    foreach ($key in $workspaceDefaults.Keys) {
        $script:WorkspacePaths[$key] = $workspaceDefaults[$key]
    }
} else {
    foreach ($key in $workspaceDefaults.Keys) {
        if (-not $script:WorkspacePaths.Contains($key) -or [string]::IsNullOrWhiteSpace($script:WorkspacePaths[$key])) {
            $script:WorkspacePaths[$key] = $workspaceDefaults[$key]
        }
    }
}

$workspaceFolders = $script:WorkspacePaths.Values | Sort-Object -Unique
foreach ($folder in $workspaceFolders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Write-Verbose "Created workspace directory: $folder" -Verbose
    }
}

function Get-ToolkitDataPath {
    [CmdletBinding()]
    param(
        [string] $Child
    )

    $root = $script:WorkspacePaths.DataRoot
    if (-not $root) {
        $root = $defaultDataRoot
    }

    if ([string]::IsNullOrWhiteSpace($Child)) {
        return $root
    }

    return Join-Path -Path $root -ChildPath $Child
}

if (-not (Get-Variable -Name 'LogConfig' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:LogConfig = [ordered]@{
        DefaultDirectory   = $script:WorkspacePaths.Logs
        MaxFileSizeBytes   = 10MB
        MaxFileCount       = 10
        EnableConsole      = $true
        EnableFile         = $true
        DefaultLogLevel    = 'Info'
        SupportedLogLevels = @('Debug', 'Info', 'Warning', 'Error', 'Success', 'Stage')
    }
    Write-Verbose "Initialized LogConfig with directory: $($script:WorkspacePaths.Logs)" -Verbose
} elseif (-not $script:LogConfig.DefaultDirectory) {
    $script:LogConfig.DefaultDirectory = $script:WorkspacePaths.Logs
    Write-Verbose "Updated LogConfig directory: $($script:WorkspacePaths.Logs)" -Verbose
}

try {
    $htmlAgilityPackPath = Join-Path -Path $script:TypesRoot -ChildPath 'netstandard2.0\HtmlAgilityPack.dll'
    $htmlAgilityLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'HtmlAgilityPack' } | Select-Object -First 1
    if (-not $htmlAgilityLoaded) {
        if (-not (Test-Path -Path $htmlAgilityPackPath -PathType Leaf)) {
            throw "HtmlAgilityPack assembly not found at '$htmlAgilityPackPath'. Ensure Phase 0 dependencies are in place."
        }

        Add-Type -Path $htmlAgilityPackPath
        Write-Verbose "Loaded HtmlAgilityPack from: $htmlAgilityPackPath" -Verbose
    } else {
        Write-Verbose "HtmlAgilityPack already loaded: $($htmlAgilityLoaded.Location)" -Verbose
    }
}
catch {
    Write-Error -Message "Failed to initialize PSWimToolkit dependencies: $_"
    throw
}

function Initialize-PSWimToolkit {
    [CmdletBinding()]
    param(
        [string] $ModuleRoot
    )

    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $ModuleRoot = $script:ModuleRoot
    }
    if (-not $ModuleRoot) {
        $ModuleRoot = $ExecutionContext.SessionState.Module.ModuleBase
    }

    $privateRoot = Join-Path -Path $ModuleRoot -ChildPath 'Private'
    $bootstrapSelf = $MyInvocation.MyCommand.Path
    $uninitScript = Join-Path -Path $privateRoot -ChildPath 'Bootstrap\Uninitialize-PSWimToolkit.ps1'

    $loggingScripts = Get-ChildItem -Path (Join-Path -Path $privateRoot -ChildPath 'Logging') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $loggingScripts) {
        . $file.FullName
    }

    $preLoadedPrivateScripts = @()
    if ($bootstrapSelf) {
        $preLoadedPrivateScripts += $bootstrapSelf
    }
    if (Test-Path -LiteralPath $uninitScript -PathType Leaf) {
        $preLoadedPrivateScripts += $uninitScript
    }
    if ($loggingScripts) {
        $preLoadedPrivateScripts += ($loggingScripts | ForEach-Object { $_.FullName })
    }

    $moduleLoadStart = Get-Date

    try {
        Write-ToolkitLog -Message "=== PSWimToolkit Module Loading ===" -Type Stage -Source 'PSWimToolkit'

        $classFiles = Get-ChildItem -Path (Join-Path -Path $ModuleRoot -ChildPath 'Classes') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
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

        $publicFunctions = Get-ChildItem -Path (Join-Path -Path $ModuleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
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
}
