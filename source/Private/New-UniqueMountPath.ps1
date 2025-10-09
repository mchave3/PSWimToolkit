function New-UniqueMountPath {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [string] $BasePath = (Get-ToolkitDataPath -Child 'Mounts'),

        [Parameter()]
        [string] $WimName
    )

    try {
        if (-not (Test-Path -LiteralPath $BasePath -PathType Container)) {
            New-Item -Path $BasePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ToolkitLog -Message ("Created mount base directory: {0}" -f $BasePath) -Type Debug -Source 'New-UniqueMountPath'
        }
    } catch {
        Write-ToolkitLog -Message ("Unable to ensure mount base directory '{0}': {1}" -f $BasePath, $_.Exception.Message) -Type Error -Source 'New-UniqueMountPath'
        throw
    }

    $safeName = if ($WimName) {
        ($WimName -replace '[^\w\-]', '_')
    } else {
        'Image'
    }

    $folderName = '{0}-{1}' -f $safeName.Trim('_'), ([guid]::NewGuid().ToString('N'))
    $mountPath = Join-Path -Path $BasePath -ChildPath $folderName

    try {
        New-Item -Path $mountPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-ToolkitLog -Message ("Failed to create mount directory '{0}': {1}" -f $mountPath, $_.Exception.Message) -Type Error -Source 'New-UniqueMountPath'
        throw
    }

    # Cleanup stale mounts older than 2 days to avoid clutter.
    try {
        $cutoff = (Get-Date).AddDays(-2)
        Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -lt $cutoff } | ForEach-Object {
            try {
                if (-not (Test-Path -LiteralPath $_.FullName)) { return }
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                Write-ToolkitLog -Message ("Removed stale mount directory '{0}'." -f $_.FullName) -Type Debug -Source 'New-UniqueMountPath'
            } catch {
                Write-ToolkitLog -Message ("Failed to remove stale mount directory '{0}': {1}" -f $_.FullName, $_.Exception.Message) -Type Warning -Source 'New-UniqueMountPath'
            }
        }
    } catch {
        Write-ToolkitLog -Message ("Stale mount cleanup encountered an issue: {0}" -f $_.Exception.Message) -Type Warning -Source 'New-UniqueMountPath'
    }

    Write-ToolkitLog -Message ("Allocated mount directory '{0}'." -f $mountPath) -Type Debug -Source 'New-UniqueMountPath'
    return $mountPath
}
