function ConvertTo-ToolkitPathSegment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Value,

        [Parameter()]
        [string] $Default = 'General'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    $segment = $Value.Trim()
    $segment = $segment -replace '[\\/:*?"<>|]', '_'
    $segment = $segment -replace '\s+', ' '
    if ([string]::IsNullOrWhiteSpace($segment)) {
        return $Default
    }

    return $segment
}

function Get-ToolkitUpdatesRoot {
    [CmdletBinding()]
    param ()

    $root = Get-ToolkitDataPath -Child 'Updates'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }
    return $root
}

function Resolve-ToolkitUpdatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $OperatingSystem,

        [Parameter(Mandatory)]
        [string] $Release,

        [Parameter(Mandatory)]
        [string] $UpdateType,

        [switch] $Ensure
    )

    Write-ToolkitLog -Message "Resolving update path for $OperatingSystem/$Release/$UpdateType" -Type Debug -Source 'Resolve-ToolkitUpdatePath'

    $segments = @(
        ConvertTo-ToolkitPathSegment -Value $OperatingSystem -Default 'OS'
        ConvertTo-ToolkitPathSegment -Value $Release -Default 'Release'
        ConvertTo-ToolkitPathSegment -Value $UpdateType -Default 'Updates'
    )

    $path = Get-ToolkitUpdatesRoot
    foreach ($segment in $segments) {
        $path = Join-Path -Path $path -ChildPath $segment
    }

    if ($Ensure) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-ToolkitLog -Message "Created update directory: $path" -Type Info -Source 'Resolve-ToolkitUpdatePath'
        }
    }

    Write-ToolkitLog -Message "Resolved update path: $path" -Type Debug -Source 'Resolve-ToolkitUpdatePath'
    return $path
}
