function Enable-WimFeature {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $FeatureName,

        [Parameter()]
        [string] $SxSPath,

        [switch] $LimitAccess,
        [switch] $IncludeAll
    )

    if (-not (Get-Command -Name Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        try {
            Import-Module -Name Dism -ErrorAction Stop
        } catch {
            Write-ProvisioningLog -Message "Unable to import DISM module: $($_.Exception.Message)" -Type Error -Source 'Enable-WimFeature'
            throw
        }
    }

    $resolvedMountPath = (Resolve-Path -LiteralPath $MountPath -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolvedMountPath -PathType Container)) {
        throw [System.IO.DirectoryNotFoundException]::new("Mount path '$resolvedMountPath' does not exist.")
    }

    $featuresList = $FeatureName -join ', '
    if (-not $PSCmdlet.ShouldProcess($resolvedMountPath, "Enable features $featuresList")) {
        return
    }

    Write-ProvisioningLog -Message ("Enabling feature(s) {0} for image {1}." -f $featuresList, $resolvedMountPath) -Type Stage -Source 'Enable-WimFeature'

    $commandParams = @{
        Path        = $resolvedMountPath
        FeatureName = $FeatureName
        ErrorAction = 'Stop'
    }

    if ($IncludeAll) {
        $commandParams['All'] = $true
    }

    if ($LimitAccess) {
        $commandParams['LimitAccess'] = $true
    }

    if ($SxSPath) {
        $resolvedSource = (Resolve-Path -LiteralPath $SxSPath -ErrorAction Stop).ProviderPath
        $commandParams['Source'] = $resolvedSource
    }

    try {
        $result = Enable-WindowsOptionalFeature @commandParams
        Write-ProvisioningLog -Message ("Feature enablement completed for {0}." -f $resolvedMountPath) -Type Success -Source 'Enable-WimFeature'
        return $result
    } catch {
        Write-ProvisioningLog -Message ("Failed to enable feature(s) {0}: {1}" -f $featuresList, $_.Exception.Message) -Type Error -Source 'Enable-WimFeature'
        throw
    }
}
