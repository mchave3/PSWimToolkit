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

    return Resolve-ToolkitUpdatePath -OperatingSystem $OperatingSystem -Release $Release -UpdateType $UpdateType -Ensure:$Ensure.IsPresent
}
