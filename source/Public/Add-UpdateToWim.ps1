function Add-UpdateToWim {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $UpdatePath,

        [switch] $Force
    )

    begin {
        if (-not (Get-Command -Name Add-WindowsPackage -ErrorAction SilentlyContinue)) {
            try {
                Import-Module -Name Dism -ErrorAction Stop
            } catch {
                Write-ProvisioningLog -Message "Unable to import DISM module: $($_.Exception.Message)" -Type Error -Source 'Add-UpdateToWim'
                throw
            }
        }

        $resolvedMountPath = (Resolve-Path -LiteralPath $MountPath -ErrorAction Stop).ProviderPath
        if (-not (Test-Path -LiteralPath $resolvedMountPath -PathType Container)) {
            throw [System.IO.DirectoryNotFoundException]::new("Mount path '$resolvedMountPath' not found.")
        }

        Write-ProvisioningLog -Message "Applying updates to mounted image at $resolvedMountPath." -Type Stage -Source 'Add-UpdateToWim'
    }

    process {
        foreach ($path in $UpdatePath) {
            try {
                $resolvedUpdatePath = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
                $fileInfo = Get-Item -LiteralPath $resolvedUpdatePath -ErrorAction Stop
            } catch {
                Write-ProvisioningLog -Message ("Update path '{0}' could not be resolved: {1}" -f $path, $_.Exception.Message) -Type Error -Source 'Add-UpdateToWim'
                continue
            }

            $kbMatch = [regex]::Match($fileInfo.Name, 'KB(\d{4,7})', 'IgnoreCase')
            $kbValue = if ($kbMatch.Success) { $kbMatch.Groups[1].Value } else { $null }

            if (-not $Force.IsPresent -and $kbValue) {
                try {
                    if (Test-UpdateInstalled -MountPath $resolvedMountPath -KB $kbValue) {
                        Write-ProvisioningLog -Message ("Skipping {0}; KB{1} already installed." -f $fileInfo.Name, $kbValue) -Type Info -Source 'Add-UpdateToWim'
                        $package = [UpdatePackage]::new($fileInfo.FullName, [int]$kbValue)
                        $package.IsVerified = $true
                        Write-Output ([pscustomobject]@{
                            PackagePath = $fileInfo.FullName
                            KB          = if ($kbValue) { "KB$kbValue" } else { $null }
                            Status      = 'Skipped'
                            Reason      = 'AlreadyInstalled'
                            Package     = $package
                        })
                        continue
                    }
                } catch {
                    Write-ProvisioningLog -Message ("Failed to verify installation state for KB{0}: {1}" -f $kbValue, $_.Exception.Message) -Type Warning -Source 'Add-UpdateToWim'
                }
            }

            if (-not $PSCmdlet.ShouldProcess($resolvedMountPath, "Add Windows package $($fileInfo.Name)")) {
                continue
            }

            Write-ProvisioningLog -Message ("Installing update {0} to {1}." -f $fileInfo.Name, $resolvedMountPath) -Type Stage -Source 'Add-UpdateToWim'

            $status = 'Installed'
            $reason = $null
            try {
                Add-WindowsPackage -Path $resolvedMountPath -PackagePath $fileInfo.FullName -PreventPending -ErrorAction Stop | Out-Null
                Write-ProvisioningLog -Message ("Successfully installed {0}." -f $fileInfo.Name) -Type Success -Source 'Add-UpdateToWim'
            } catch {
                $status = 'Failed'
                $reason = $_.Exception.Message
                Write-ProvisioningLog -Message ("Failed to install {0}: {1}" -f $fileInfo.Name, $reason) -Type Error -Source 'Add-UpdateToWim'
            }

            $kbInt = if ($kbValue) { [int]$kbValue } else { 0 }
            $package = [UpdatePackage]::new($fileInfo.FullName, $kbInt)
            $package.IsVerified = $status -eq 'Installed'

            Write-Output ([pscustomobject]@{
                PackagePath = $fileInfo.FullName
                KB          = if ($kbValue) { "KB$kbValue" } else { $null }
                Status      = $status
                Reason      = $reason
                Package     = $package
            })
        }
    }
}
