class WimImage {
    [string] $Path
    [int] $Index = 1
    [string] $Name
    [string] $Description
    [Version] $Version
    [UInt64] $Size
    [string] $Architecture

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
            Write-ProvisioningLog -Message "Unable to read WIM metadata for $($this.Path): $($_.Exception.Message)" -Type Warning -Source 'WimImage'
        }
    }

    [void] Mount([string] $MountPath) {
        throw [System.NotImplementedException]::new('WIM mounting will be implemented during Phase 2.')
    }

    [void] Dismount([switch] $SaveChanges) {
        throw [System.NotImplementedException]::new('WIM dismount will be implemented during Phase 2.')
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

    [System.Collections.Generic.IEnumerable[string]] GetInstalledUpdates() {
        throw [System.NotImplementedException]::new('Retrieving installed updates will be implemented during Phase 2.')
    }
}
