function Test-UpdateInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $KB
    )

    if (-not (Get-Command -Name Get-WindowsPackage -ErrorAction SilentlyContinue)) {
        try {
            Import-Module -Name Dism -ErrorAction Stop
        } catch {
            Write-ToolkitLog -Message "Unable to import DISM module: $($_.Exception.Message)" -Type Error -Source 'Test-UpdateInstalled'
            throw
        }
    }

    $resolvedMountPath = (Resolve-Path -LiteralPath $MountPath -ErrorAction Stop).ProviderPath
    $kbIdentifier = if ($KB -match '\d+') { $Matches[0] } else { $KB }

    Write-ToolkitLog -Message ("Checking if KB{0} is installed in {1}." -f $kbIdentifier, $resolvedMountPath) -Type Debug -Source 'Test-UpdateInstalled'

    try {
        $packages = Get-WindowsPackage -Path $resolvedMountPath -ErrorAction Stop
        $isInstalled = $packages | Where-Object {
            $_.PackageName -match "KB$kbIdentifier" -or $_.PackageIdentity -match "KB$kbIdentifier"
        }

        if ($isInstalled) {
            Write-ToolkitLog -Message ("KB{0} already present in image at {1}." -f $kbIdentifier, $resolvedMountPath) -Type Info -Source 'Test-UpdateInstalled'
            return $true
        }

        return $false
    } catch {
        Write-ToolkitLog -Message ("Failed to query installed packages from {0}. {1}" -f $resolvedMountPath, $_.Exception.Message) -Type Error -Source 'Test-UpdateInstalled'
        throw
    }
}
