Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot
$script:TypesRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Types'
$script:ProgramDataRoot = Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)) -ChildPath 'PSWimToolkit'
$script:WorkspacePaths = [ordered]@{
    DataRoot   = $script:ProgramDataRoot
    Logs       = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Logs'
    Updates    = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Updates'
    Mounts     = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Mounts'
    Imports    = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Imports'
    Cache      = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Cache'
    Temp       = Join-Path -Path $script:ProgramDataRoot -ChildPath 'Temp'
    GuiRoot    = Join-Path -Path $script:ProgramDataRoot -ChildPath 'GUI'
}
$script:WorkspacePaths['GuiLogs']    = Join-Path -Path $script:WorkspacePaths.GuiRoot -ChildPath 'Logs'
$script:WorkspacePaths['GuiMounts']  = Join-Path -Path $script:WorkspacePaths.GuiRoot -ChildPath 'Mounts'
$script:WorkspacePaths['GuiImports'] = Join-Path -Path $script:WorkspacePaths.GuiRoot -ChildPath 'Imports'

$workspaceFolders = $script:WorkspacePaths.Values | Sort-Object -Unique
foreach ($folder in $workspaceFolders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

function Get-ToolkitDataPath {
    [CmdletBinding()]
    param(
        [string] $Child
    )

    $root = $script:WorkspacePaths.DataRoot
    if (-not $root) {
        $root = Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)) -ChildPath 'PSWimToolkit'
    }

    if ([string]::IsNullOrWhiteSpace($Child)) {
        return $root
    }

    return Join-Path -Path $root -ChildPath $Child
}

$script:LogConfig = [ordered]@{
    DefaultDirectory  = $script:WorkspacePaths.Logs
    MaxFileSizeBytes  = 10MB
    MaxFileCount      = 10
    EnableConsole     = $true
    EnableFile        = $true
    DefaultLogLevel   = 'Info'
    SupportedLogLevels = @('Debug', 'Info', 'Warning', 'Error', 'Success', 'Stage')
}

try {
    $htmlAgilityPackPath = Join-Path -Path $script:TypesRoot -ChildPath 'netstandard2.0\HtmlAgilityPack.dll'
    if (-not (Test-Path -Path $htmlAgilityPackPath -PathType Leaf)) {
        throw "HtmlAgilityPack assembly not found at '$htmlAgilityPackPath'. Ensure Phase 0 dependencies are in place."
    }

    $htmlAgilityPackAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'HtmlAgilityPack' } | Select-Object -First 1
    if (-not $htmlAgilityPackAssembly) {
        Add-Type -Path $htmlAgilityPackPath
    }

    $classFiles = Get-ChildItem -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Classes') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $classFiles) {
        . $file.FullName
    }

    $privateFunctions = Get-ChildItem -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $privateFunctions) {
        . $file.FullName
    }

    $publicFunctions = Get-ChildItem -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $publicFunctions) {
        . $file.FullName
    }

    $publicFunctionNames = @()
    if ($publicFunctions) {
        $publicFunctionNames = $publicFunctions | ForEach-Object { $_.BaseName }
    }

    if ($publicFunctionNames.Count -gt 0) {
        Export-ModuleMember -Function $publicFunctionNames
    } else {
        Export-ModuleMember -Function @()
    }
}
catch {
    Write-Error -Message "Failed to initialize PSWimToolkit: $_"
    throw
}

