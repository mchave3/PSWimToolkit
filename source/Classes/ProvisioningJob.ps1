class ProvisioningJob {
    [WimImage] $WimImage
    [string] $Status = 'Pending'
    [datetime] $StartTime
    [datetime] $EndTime
    [System.Collections.Generic.List[string]] $UpdatesApplied = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $UpdatesFailed = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $Errors = [System.Collections.Generic.List[string]]::new()
    [string] $LogFile

    ProvisioningJob([WimImage] $Image, [string] $LogPath) {
        if ($null -eq $Image) {
            throw [System.ArgumentNullException]::new('Image')
        }
        $this.WimImage = $Image
        $this.LogFile = $LogPath
    }

    [void] Start() {
        $this.StartTime = Get-Date
        $this.Status = 'Running'
        Write-ToolkitLog -Message "Provisioning job starting for $($this.WimImage.Path)." -Type Stage -Source 'ProvisioningJob'
    }

    [void] Complete([bool] $Successful) {
        $this.EndTime = Get-Date
        $this.Status = if ($Successful) { 'Completed' } else { 'Failed' }
        $type = if ($Successful) { 'Success' } else { 'Error' }
        Write-ToolkitLog -Message "Provisioning job $($this.Status) for $($this.WimImage.Path)." -Type $type -Source 'ProvisioningJob'
    }

    [void] AddError([string] $Message) {
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            [void]$this.Errors.Add($Message)
            Write-ToolkitLog -Message $Message -Type Error -Source 'ProvisioningJob'
        }
    }

    [void] RecordUpdateResult([string] $UpdateId, [bool] $Succeeded) {
        if ($Succeeded) {
            [void]$this.UpdatesApplied.Add($UpdateId)
        } else {
            [void]$this.UpdatesFailed.Add($UpdateId)
        }
    }

    [string[]] GetLog() {
        if ($this.LogFile -and (Test-Path -LiteralPath $this.LogFile -PathType Leaf)) {
            return Get-Content -Path $this.LogFile -ErrorAction SilentlyContinue
        }
        return @()
    }
}
