Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleInitStartTime = Get-Date

if (-not (Get-Variable -Name 'ModuleRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ModuleRoot = Split-Path -Parent $PSCommandPath
    if (-not $script:ModuleRoot) {
        $script:ModuleRoot = $PSScriptRoot
    }
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
    DataRoot   = $script:ProgramDataRoot
    Logs       = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Logs'
    Updates    = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Updates'
    Mounts     = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Mounts'
    Imports    = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Imports'
    Cache      = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Cache'
    Temp       = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Temp'
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
        Write-Verbose "Created workspace directory: $folder"
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
    Write-Verbose "Initialized LogConfig with directory: $($script:WorkspacePaths.Logs)"
} elseif (-not $script:LogConfig.DefaultDirectory) {
    $script:LogConfig.DefaultDirectory = $script:WorkspacePaths.Logs
    Write-Verbose "Updated LogConfig directory: $($script:WorkspacePaths.Logs)"
}

try {
    $htmlAgilityPackPath = Join-Path -Path $script:TypesRoot -ChildPath 'netstandard2.0\HtmlAgilityPack.dll'
    $htmlAgilityLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'HtmlAgilityPack' } | Select-Object -First 1
    if (-not $htmlAgilityLoaded) {
        if (-not (Test-Path -Path $htmlAgilityPackPath -PathType Leaf)) {
            throw "HtmlAgilityPack assembly not found at '$htmlAgilityPackPath'. Ensure Phase 0 dependencies are in place."
        }

        Add-Type -Path $htmlAgilityPackPath
        Write-Verbose "Loaded HtmlAgilityPack from: $htmlAgilityPackPath"
    } else {
        Write-Verbose "HtmlAgilityPack already loaded: $($htmlAgilityLoaded.Location)"
    }
}
catch {
    Write-Error -Message "Failed to initialize PSWimToolkit dependencies: $_"
    throw
}

$initDuration = ((Get-Date) - $script:ModuleInitStartTime).TotalMilliseconds
Write-Verbose "PSWimToolkit environment initialized in $([Math]::Round($initDuration, 2))ms"
