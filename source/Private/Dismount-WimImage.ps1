function Dismount-WimImage {
    [CmdletBinding(DefaultParameterSetName = 'Save')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath,

        [Parameter(ParameterSetName = 'Save')]
        [switch] $Save,

        [Parameter(ParameterSetName = 'Discard')]
        [switch] $Discard,

        [switch] $SkipCleanup
    )

    if (-not (Test-Path -LiteralPath $MountPath -PathType Container)) {
        Write-ProvisioningLog -Message "Mount path '$MountPath' does not exist." -Type Warning -Source 'Dismount-WimImage'
        return
    }

    $resolvedMountPath = (Resolve-Path -LiteralPath $MountPath).ProviderPath
    $dismountParams = @{
        Path        = $resolvedMountPath
        ErrorAction = 'Stop'
    }

    if ($Discard) {
        $dismountParams['Discard'] = $true
    } else {
        $dismountParams['Save'] = $true
    }

    Write-ProvisioningLog -Message ("Dismounting image at {0} ({1})." -f $resolvedMountPath, $(if ($Discard) { 'Discard' } else { 'Save' })) -Type Stage -Source 'Dismount-WimImage'

    try {
        Dismount-WindowsImage @dismountParams
        Write-ProvisioningLog -Message ("Dismount complete for {0}." -f $resolvedMountPath) -Type Success -Source 'Dismount-WimImage'
    } catch {
        Write-ProvisioningLog -Message ("Failed to dismount image at {0}. {1}" -f $resolvedMountPath, $_.Exception.Message) -Type Error -Source 'Dismount-WimImage'
        throw
    } finally {
        if (-not $SkipCleanup) {
            try {
                Remove-Item -LiteralPath $resolvedMountPath -Recurse -Force -ErrorAction Stop
                Write-ProvisioningLog -Message ("Mount directory {0} removed." -f $resolvedMountPath) -Type Debug -Source 'Dismount-WimImage'
            } catch {
                Write-ProvisioningLog -Message ("Failed to remove mount directory {0}: {1}" -f $resolvedMountPath, $_.Exception.Message) -Type Warning -Source 'Dismount-WimImage'
            }
        }
    }
}
