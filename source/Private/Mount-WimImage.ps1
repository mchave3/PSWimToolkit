function Mount-WimImage {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $ImagePath,

        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNull()]
        [WimImage] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $MountPath,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int] $Index = 1,

        [switch] $ReadOnly
    )

    begin {
        if (-not (Get-Command -Name Mount-WindowsImage -ErrorAction SilentlyContinue)) {
            try {
                Import-Module -Name Dism -ErrorAction Stop
            } catch {
                Write-ToolkitLog -Message "Unable to import DISM module: $($_.Exception.Message)" -Type Error -Source 'Mount-WimImage'
                throw
            }
        }
    }

    process {
        $resolvedImage = $null
        if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $resolvedImage = $InputObject
            if ($PSBoundParameters.ContainsKey('Index')) {
                $resolvedImage.Index = $Index
            }
        } else {
            try {
                $fullPath = (Resolve-Path -LiteralPath $ImagePath -ErrorAction Stop).ProviderPath
                $resolvedImage = [WimImage]::new($fullPath, $Index)
            } catch {
                Write-ToolkitLog -Message "WIM path '$ImagePath' could not be resolved. $($_.Exception.Message)" -Type Error -Source 'Mount-WimImage'
                throw
            }
        }

        try {
            $targetMountPath = (Resolve-Path -LiteralPath $MountPath -ErrorAction SilentlyContinue)?.ProviderPath
            if (-not $targetMountPath) {
                $targetMountPath = (New-Item -Path $MountPath -ItemType Directory -Force -ErrorAction Stop).FullName
            }

            $directoryContents = Get-ChildItem -LiteralPath $targetMountPath -Force -ErrorAction SilentlyContinue
            if ($directoryContents -and $directoryContents.Count -gt 0) {
                Write-ToolkitLog -Message "Mount path '$targetMountPath' must be empty before mounting." -Type Error -Source 'Mount-WimImage'
                throw [System.InvalidOperationException]::new("Mount path '$targetMountPath' is not empty.")
            }

            Write-ToolkitLog -Message ("Mounting WIM {0} (Index {1}) to {2}." -f $resolvedImage.Path, $resolvedImage.Index, $targetMountPath) -Type Stage -Source 'Mount-WimImage'

            $mountParams = @{
                ImagePath = $resolvedImage.Path
                Index     = $resolvedImage.Index
                Path      = $targetMountPath
                ErrorAction = 'Stop'
            }
            if ($ReadOnly) {
                $mountParams['ReadOnly'] = $true
            }

            $mountResult = Mount-WindowsImage @mountParams
            Write-ToolkitLog -Message ("Mount complete: {0}" -f $mountResult.ImagePath) -Type Success -Source 'Mount-WimImage'

            return [pscustomobject]@{
                WimPath    = $resolvedImage.Path
                Index      = $resolvedImage.Index
                MountPath  = $targetMountPath
                ReadOnly   = $ReadOnly.IsPresent
                Timestamp  = Get-Date
            }
        } catch {
            Write-ToolkitLog -Message ("Failed to mount WIM. {0}" -f $_.Exception.Message) -Type Error -Source 'Mount-WimImage'
            throw
        }
    }
}
