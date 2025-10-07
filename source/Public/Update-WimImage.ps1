function Update-WimImage {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([ProvisioningJob])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WimPath,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int] $Index = 1,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $UpdatePath,

        [Parameter()]
        [string] $MountPath,

        [Parameter()]
        [string] $OutputPath,

        [Parameter()]
        [string] $SxSPath,

        [switch] $EnableNetFx3,
        [switch] $Force,
        [string] $LogPath
    )

    if (-not $PSCmdlet.ShouldProcess($WimPath, "Update WIM image index $Index")) {
        return
    }

    $originalLogDirectory = (Get-Variable -Name 'LogConfig' -Scope Script -ErrorAction SilentlyContinue)?.Value?.DefaultDirectory
    $logDirectoryOverride = $null

    try {
        $resolvedWimPath = (Resolve-Path -LiteralPath $WimPath -ErrorAction Stop).ProviderPath

        if ($OutputPath) {
            $outputDirectory = Split-Path -Path $OutputPath -Parent
            if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
                New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
            }

            Copy-Item -LiteralPath $resolvedWimPath -Destination $OutputPath -Force -ErrorAction Stop
            Write-ProvisioningLog -Message ("Copied source WIM to {0} for processing." -f $OutputPath) -Type Info -Source 'Update-WimImage'
            $resolvedWimPath = (Resolve-Path -LiteralPath $OutputPath -ErrorAction Stop).ProviderPath
        }

        if ($LogPath) {
            $logDirectoryOverride = (Resolve-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue)?.ProviderPath
            if (-not $logDirectoryOverride) {
                $logDirectoryOverride = (New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop).FullName
            }
            $script:LogConfig.DefaultDirectory = $logDirectoryOverride
        }

        $logFile = Initialize-LogFile -ForceNew
        Write-ProvisioningLog -Message "Provisioning log initialized at $logFile." -Type Debug -Source 'Update-WimImage'

        $wimImage = [WimImage]::new($resolvedWimPath, $Index)
        $job = [ProvisioningJob]::new($wimImage, $logFile)
        $job.Start()

        $updatesRoot = (Resolve-Path -LiteralPath $UpdatePath -ErrorAction Stop).ProviderPath
        $mountRoot = if ($MountPath) {
            $resolvedMount = (Resolve-Path -LiteralPath $MountPath -ErrorAction SilentlyContinue)?.ProviderPath
            if (-not $resolvedMount) {
                $resolvedMount = (New-Item -Path $MountPath -ItemType Directory -Force -ErrorAction Stop).FullName
            }
            $resolvedMount
        } else {
            $tempMount = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("PSWimToolkit\Mounts\{0}" -f ([guid]::NewGuid().ToString('N')))
            New-Item -Path $tempMount -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $tempMount
        }
        $preserveMountDirectory = [bool]$MountPath

        $mountResult = $null
        $versionInfo = $null
        $success = $true
        $updatesApplied = 0

        try {
            $mountResult = $wimImage.Mount($mountRoot)
            $versionInfo = Test-WimImageVersion -MountPath $mountResult.MountPath

            $jobMessage = "Processing $($wimImage.Path) (Index $($wimImage.Index)) - $($versionInfo.ProductName)"
            Write-ProvisioningLog -Message $jobMessage -Type Info -Source 'Update-WimImage'

            $updateFiles = Get-ChildItem -Path $updatesRoot -File -ErrorAction Stop | Where-Object { $_.Extension -in ('.msu', '.cab') } | Sort-Object Name
            if (-not $updateFiles) {
                Write-ProvisioningLog -Message ("No update packages found in {0}." -f $updatesRoot) -Type Warning -Source 'Update-WimImage'
            }

            if ($versionInfo.Channel -eq 'Windows 11 24H2') {
                $prereq = $updateFiles | Where-Object { $_.Name -match 'KB5043080' }
                if ($prereq) {
                    $others = $updateFiles | Where-Object { $_.Name -notmatch 'KB5043080' }
                    $updateFiles = @($prereq + $others)
                    Write-ProvisioningLog -Message "Prioritizing KB5043080 for Windows 11 24H2 image." -Type Info -Source 'Update-WimImage'
                }
            }

            foreach ($update in $updateFiles) {
                try {
                    $addParams = @{
                        MountPath  = $mountResult.MountPath
                        UpdatePath = $update.FullName
                    }
                    if ($Force) {
                        $addParams['Force'] = $true
                    }
                    $results = Add-UpdateToWim @addParams

                    foreach ($result in $results) {
                        $updateId = if ($result.KB) { $result.KB } else { $update.Name }
                        switch ($result.Status) {
                            'Installed' {
                                $job.RecordUpdateResult($updateId, $true)
                                $updatesApplied++
                            }
                            'Failed' {
                                $job.RecordUpdateResult($updateId, $false)
                                $job.AddError(("Failed to install {0}: {1}" -f $updateId, $result.Reason))
                                $success = $false
                            }
                            default {
                                Write-ProvisioningLog -Message ("Update {0} status: {1}" -f $updateId, $result.Status) -Type Debug -Source 'Update-WimImage'
                            }
                        }
                    }
                } catch {
                    $identifier = $update.Name
                    $job.RecordUpdateResult($identifier, $false)
                    $job.AddError(("Unexpected failure while installing {0}: {1}" -f $identifier, $_.Exception.Message))
                    $success = $false
                }
            }

            if ($EnableNetFx3) {
                if (-not $SxSPath) {
                    Write-ProvisioningLog -Message "NetFx3 enablement requested but no SxS source provided." -Type Warning -Source 'Update-WimImage'
                } else {
                    try {
                        Enable-WimFeature -MountPath $mountResult.MountPath -FeatureName 'NetFx3' -SxSPath $SxSPath -IncludeAll -LimitAccess
                    } catch {
                        $job.AddError("Failed to enable .NET Framework 3.5: $($_.Exception.Message)")
                        $success = $false
                    }
                }
            }
        } catch {
            $job.AddError("Critical failure during provisioning: $($_.Exception.Message)")
            $success = $false
            throw
        } finally {
            if ($mountResult) {
                try {
                    if ($success) {
                        $wimImage.Dismount($false, $preserveMountDirectory)
                    } else {
                        $wimImage.Dismount($true, $preserveMountDirectory)
                    }
                } catch {
                    $job.AddError("Dismount operation failed: $($_.Exception.Message)")
                    $success = $false
                }
            }
        }

        Write-ProvisioningLog -Message ("Update process completed. Updates applied: {0}" -f $updatesApplied) -Type Success -Source 'Update-WimImage'
        $job.Complete($success)
        return $job
    }
    finally {
        if ($LogPath -and $originalLogDirectory) {
            $script:LogConfig.DefaultDirectory = $originalLogDirectory
        }
    }
}
