function Start-ParallelProvisioning {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([ProvisioningJob[]])]
    param (
        [Parameter(Mandatory)]
        [Alias('FullName')]
        [object[]] $WimFiles,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $UpdatePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $SxSPath,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int] $ThrottleLimit = 10,

        [switch] $EnableNetFx3,

        [hashtable] $IndexSelection,

        [string] $LogPath,

        [string] $MountRoot,

        [switch] $Force,

        [string] $OutputDirectory
    )

    $resolvedUpdatePath = (Resolve-Path -LiteralPath $UpdatePath -ErrorAction Stop).ProviderPath
    $resolvedSxSPath = if ($SxSPath) { (Resolve-Path -LiteralPath $SxSPath -ErrorAction Stop).ProviderPath } else { $null }

    $logRoot = if ($LogPath) {
        (Resolve-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue)?.ProviderPath ?? (New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop).FullName
    } else {
        $defaultRoot = if ($script:LogConfig.DefaultDirectory) { $script:LogConfig.DefaultDirectory } else { Join-Path ([System.IO.Path]::GetTempPath()) 'PSWimToolkit\Logs' }
        $parallelRoot = Join-Path -Path $defaultRoot -ChildPath ('Parallel_{0:yyyyMMdd_HHmmss}' -f (Get-Date))
        New-Item -Path $parallelRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $parallelRoot
    }

    $mountBase = if ($MountRoot) {
        (Resolve-Path -LiteralPath $MountRoot -ErrorAction SilentlyContinue)?.ProviderPath ?? (New-Item -Path $MountRoot -ItemType Directory -Force -ErrorAction Stop).FullName
    } else {
        Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'PSWimToolkit\Mounts'
    }

    $outputBase = if ($OutputDirectory) {
        (Resolve-Path -LiteralPath $OutputDirectory -ErrorAction SilentlyContinue)?.ProviderPath ?? (New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop).FullName
    } else {
        $null
    }

    $wimEntries = @()
    foreach ($entry in $WimFiles) {
        if ($null -eq $entry) { continue }

        $wimPath = $null
        $index = 1

        switch -regex ($entry.GetType().FullName) {
            '^PSWimToolkit\.WimImage$' {
                $wimPath = $entry.Path
                $index = $entry.Index
                break
            }
            '^System\.IO\.FileInfo$' {
                $wimPath = $entry.FullName
                break
            }
            default {
                $wimPath = [string]$entry
            }
        }

        try {
            $resolvedWim = (Resolve-Path -LiteralPath $wimPath -ErrorAction Stop).ProviderPath
        } catch {
            Write-ToolkitLog -Message ("Skipping WIM entry '{0}': {1}" -f $wimPath, $_.Exception.Message) -Type Error -Source 'Start-ParallelProvisioning'
            continue
        }

        $name = [System.IO.Path]::GetFileNameWithoutExtension($resolvedWim)
        if ($IndexSelection -and $IndexSelection.ContainsKey($name)) {
            $index = [int]$IndexSelection[$name]
        }

        $jobId = [guid]::NewGuid().ToString('N')
        $jobLogPath = Join-Path -Path $logRoot -ChildPath $jobId
        New-Item -Path $jobLogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $outputTarget = $null
        if ($outputBase) {
            $outputTarget = Join-Path -Path $outputBase -ChildPath ([System.IO.Path]::GetFileName($resolvedWim))
        }

        $wimEntries += [pscustomobject]@{
            WimPath    = $resolvedWim
            Index      = $index
            Name       = $name
            LogPath    = $jobLogPath
            OutputPath = $outputTarget
        }
    }

    if (-not $wimEntries) {
        Write-ToolkitLog -Message 'No valid WIM inputs were provided for parallel provisioning.' -Type Warning -Source 'Start-ParallelProvisioning'
        return @()
    }

    $targetDescription = '{0} WIM image(s)' -f $wimEntries.Count
    if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Provision in parallel')) {
        return @()
    }

    $total = $wimEntries.Count
    $activity = 'Provisioning WIM images in parallel'
    Invoke-ParallelProgress -Total $total -Completed 0 -Activity $activity -Status 'Queued'

    $parallelResults = $wimEntries |
        ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            param($wimEntry)
            $mountPath = $null
            try {
                $mountPath = New-UniqueMountPath -BasePath $using:mountBase -WimName $wimEntry.Name
                $parameters = @{
                    WimPath    = $wimEntry.WimPath
                    Index      = $wimEntry.Index
                    UpdatePath = $using:resolvedUpdatePath
                    MountPath  = $mountPath
                    LogPath    = $wimEntry.LogPath
                }
                if ($using:resolvedSxSPath) { $parameters['SxSPath'] = $using:resolvedSxSPath }
                if ($wimEntry.OutputPath) { $parameters['OutputPath'] = $wimEntry.OutputPath }
                if ($using:EnableNetFx3) { $parameters['EnableNetFx3'] = $true }
                if ($using:Force) { $parameters['Force'] = $true }

                $jobResult = Update-WimImage @parameters
                [pscustomobject]@{
                    Job   = $jobResult
                    Error = $null
                    Path  = $wimEntry.WimPath
                    Log   = $wimEntry.LogPath
                }
            } catch {
                Write-ToolkitLog -Message ("Parallel provisioning failed for {0}: {1}" -f $wimEntry.WimPath, $_.Exception.Message) -Type Error -Source 'Start-ParallelProvisioning'
                [pscustomobject]@{
                    Job   = $null
                    Error = $_.Exception.Message
                    Path  = $wimEntry.WimPath
                    Log   = $wimEntry.LogPath
                }
            } finally {
                if ($mountPath -and (Test-Path -LiteralPath $mountPath)) {
                    try {
                        Remove-Item -LiteralPath $mountPath -Recurse -Force -ErrorAction Stop
                    } catch {
                        Write-ToolkitLog -Message ("Failed to remove temporary mount directory '{0}': {1}" -f $mountPath, $_.Exception.Message) -Type Warning -Source 'Start-ParallelProvisioning'
                    }
                }
            }
        } |
        ForEach-Object -Begin { $completed = 0 } -Process {
            $completed++
            Invoke-ParallelProgress -Total $total -Completed $completed -Activity $activity
            $_
        } |
        Where-Object { $_ }

    Invoke-ParallelProgress -Total $total -Completed $total -Activity $activity -Status 'Completed'

    $jobs = @()
    $errors = @()
    foreach ($result in $parallelResults) {
        if ($result.Job) {
            $jobs += $result.Job
        }
        if ($result.Error) {
            $errors += [pscustomobject]@{
                Path = $result.Path
                Log  = $result.Log
                Error = $result.Error
            }
        }
    }

    if ($errors.Count -gt 0) {
        Write-ToolkitLog -Message ("Parallel provisioning completed with {0} error(s)." -f $errors.Count) -Type Warning -Source 'Start-ParallelProvisioning'
        foreach ($entry in $errors) {
            Write-ToolkitLog -Message ("Failure processing {0}: {1}" -f $entry.Path, $entry.Error) -Type Error -Source 'Start-ParallelProvisioning'
        }
    } else {
        Write-ToolkitLog -Message ("Parallel provisioning completed successfully for {0} image(s)." -f $jobs.Count) -Type Success -Source 'Start-ParallelProvisioning'
    }

    return $jobs
}
