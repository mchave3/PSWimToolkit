class WimImage {
    [string] $Path
    [int] $Index = 1
    [string] $Name
    [string] $Description
    [Version] $Version
    [UInt64] $Size
    [string] $Architecture
    [string] $CurrentMountPath
    [bool] $IsMounted

    WimImage([string] $ImagePath, [int] $ImageIndex = 1) {
        if ([string]::IsNullOrWhiteSpace($ImagePath)) {
            throw [System.ArgumentException]::new('Image path must be supplied.', 'ImagePath')
        }

        $this.Path = [System.IO.Path]::GetFullPath($ImagePath)
        $this.Index = if ($ImageIndex -gt 0) { $ImageIndex } else { 1 }

        if (Test-Path -LiteralPath $this.Path) {
            $this.RefreshMetadata()
        }
    }

    hidden [void] RefreshMetadata() {
        try {
            $imageInfo = Get-WindowsImage -ImagePath $this.Path -Index $this.Index -ErrorAction Stop
            $this.Name = $imageInfo.ImageName
            $this.Description = $imageInfo.ImageDescription
            $this.Version = [Version]$imageInfo.Version
            $this.Size = [UInt64]$imageInfo.ImageSize
            $this.Architecture = $imageInfo.ImageArchitecture
        } catch {
            Write-ToolkitLog -Message "Unable to read WIM metadata for $($this.Path): $($_.Exception.Message)" -Type Warning -Source 'WimImage'
        }
    }

    [pscustomobject] Mount([string] $MountPath, [bool] $ReadOnly = $false) {
        if ([string]::IsNullOrWhiteSpace($MountPath)) {
            throw [System.ArgumentException]::new('Mount path must be provided.', 'MountPath')
        }

        $mountParams = @{
            InputObject = $this
            MountPath   = $MountPath
            Index       = $this.Index
        }
        if ($ReadOnly) {
            $mountParams['ReadOnly'] = $true
        }

        $result = Mount-WimImage @mountParams
        $this.CurrentMountPath = $result.MountPath
        $this.IsMounted = $true
        return $result
    }

    [void] Dismount([bool] $DiscardChanges = $false, [bool] $KeepMountDirectory = $false) {
        if (-not $this.IsMounted -or [string]::IsNullOrWhiteSpace($this.CurrentMountPath)) {
            Write-ToolkitLog -Message "WimImage instance for $($this.Path) is not tracked as mounted." -Type Warning -Source 'WimImage'
            return
        }

        if ($DiscardChanges) {
            Dismount-WimImage -MountPath $this.CurrentMountPath -Discard -SkipCleanup:$KeepMountDirectory
        } else {
            Dismount-WimImage -MountPath $this.CurrentMountPath -Save -SkipCleanup:$KeepMountDirectory
        }

        $this.IsMounted = $false
        $this.CurrentMountPath = $null
    }

    [pscustomobject] GetInfo() {
        $this.RefreshMetadata()
        return [pscustomobject]@{
            Path         = $this.Path
            Index        = $this.Index
            Name         = $this.Name
            Description  = $this.Description
            Version      = $this.Version
            Size         = $this.Size
            Architecture = $this.Architecture
        }
    }

    [System.Collections.Generic.IEnumerable[pscustomobject]] GetInstalledUpdates([string] $MountPath) {
        $targetMountPath = if (-not [string]::IsNullOrWhiteSpace($MountPath)) {
            $MountPath
        } elseif ($this.IsMounted -and -not [string]::IsNullOrWhiteSpace($this.CurrentMountPath)) {
            $this.CurrentMountPath
        } else {
            throw [System.InvalidOperationException]::new('Mount path must be specified or the image must already be mounted.')
        }

        $resolvedMountPath = (Resolve-Path -LiteralPath $targetMountPath -ErrorAction Stop).ProviderPath

        try {
            $packages = Get-WindowsPackage -Path $resolvedMountPath -ErrorAction Stop
            return $packages | ForEach-Object {
                $kbMatch = [regex]::Match($_.PackageName, 'KB(\d{4,7})', 'IgnoreCase')
                [pscustomobject]@{
                    PackageName = $_.PackageName
                    KB          = if ($kbMatch.Success) { "KB$($kbMatch.Groups[1].Value)" } else { $null }
                    State       = $_.State
                    ReleaseType = $_.ReleaseType
                }
            }
        } catch {
            Write-ToolkitLog -Message "Failed to enumerate installed updates for mount path $resolvedMountPath. $($_.Exception.Message)" -Type Error -Source 'WimImage'
            throw
        }
    }
}
