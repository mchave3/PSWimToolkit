function Invoke-ParallelProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Total,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Completed,

        [Parameter()]
        [string] $Activity = 'Parallel provisioning',

        [Parameter()]
        [string] $Status
    )

    $calculatedStatus = if ($Status) {
        $Status
    } else {
        'Completed {0}/{1}' -f $Completed, $Total
    }

    $percent = if ($Total -le 0) {
        0
    } else {
        $calculated = [int]([math]::Floor(($Completed / [double]$Total) * 100))
        if ($calculated -lt 0) { 0 }
        elseif ($calculated -gt 100) { 100 }
        else { $calculated }
    }

    Write-ToolkitLog -Message "Progress: $calculatedStatus ($percent%)" -Type Debug -Source 'Invoke-ParallelProgress'
    Write-Progress -Activity $Activity -Status $calculatedStatus -PercentComplete $percent
}
