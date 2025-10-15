function Get-ToolkitUpdatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OperatingSystem,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Release,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $UpdateType = 'Updates',

        [switch] $Ensure
    )

    Write-ToolkitLog -Message "Getting toolkit update path for $OperatingSystem/$Release/$UpdateType" -Type Debug -Source 'Get-ToolkitUpdatePath'

    $result = Resolve-ToolkitUpdatePath -OperatingSystem $OperatingSystem -Release $Release -UpdateType $UpdateType -Ensure:$Ensure.IsPresent

    Write-ToolkitLog -Message "Toolkit update path: $result" -Type Info -Source 'Get-ToolkitUpdatePath'
    return $result
}
