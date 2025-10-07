class UpdatePackage {
    [string] $FilePath
    [string] $FileName
    [string] $KB
    [UInt64] $Size
    [string] $Sha256
    [bool] $IsVerified

    UpdatePackage([string] $Path, [int] $Kb) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw [System.ArgumentException]::new('File path must be specified.', 'Path')
        }

        $this.FilePath = [System.IO.Path]::GetFullPath($Path)
        $this.FileName = [System.IO.Path]::GetFileName($Path)
        $this.KB = if ($Kb) { "KB$Kb" } else { $null }
        $this.RefreshMetadata()
    }

    hidden [void] RefreshMetadata() {
        if (-not (Test-Path -LiteralPath $this.FilePath -PathType Leaf)) {
            return
        }

        $file = Get-Item -LiteralPath $this.FilePath -ErrorAction Stop
        $this.Size = [UInt64]$file.Length
        $hash = Get-FileHash -Algorithm SHA256 -Path $this.FilePath -ErrorAction Stop
        $this.Sha256 = $hash.Hash
    }

    [bool] Verify([string] $ExpectedSha256) {
        if (-not (Test-Path -LiteralPath $this.FilePath -PathType Leaf)) {
            Write-ProvisioningLog -Message "Update package $($this.FileName) is missing from disk." -Type Error -Source 'UpdatePackage'
            $this.IsVerified = $false
            return $false
        }

        $this.RefreshMetadata()

        if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            $this.IsVerified = $true
            return $true
        }

        $isMatch = $this.Sha256 -and ($this.Sha256.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase))
        $this.IsVerified = $isMatch

        if (-not $isMatch) {
            Write-ProvisioningLog -Message "Hash mismatch for package $($this.FileName)." -Type Warning -Source 'UpdatePackage'
        }

        return $isMatch
    }

    [void] Install([string] $MountPath) {
        throw [System.NotImplementedException]::new('Update installation workflow is scheduled for a later phase.')
    }
}
