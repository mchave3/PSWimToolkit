function Set-SecurityProtocol {
    [CmdletBinding()]
    param (
        [switch] $ResetToDefault
    )

    if (-not (Get-Variable -Name 'DefaultSecurityProtocol' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:DefaultSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    }

    if ($ResetToDefault) {
        [System.Net.ServicePointManager]::SecurityProtocol = (Get-Variable -Name 'DefaultSecurityProtocol' -Scope Script -ErrorAction SilentlyContinue).Value
        Write-ToolkitLog -Message 'Security protocol reverted to default settings.' -Type Debug -Source 'Set-SecurityProtocol'
        return
    }

    $desiredProtocols = [System.Net.SecurityProtocolType]::Tls12
    try {
        $enumType = [System.Net.SecurityProtocolType]
        if ($enumType::GetNames($enumType) -contains 'Tls13') {
            $desiredProtocols = $desiredProtocols -bor [System.Net.SecurityProtocolType]::Tls13
        }
    } catch {
        # Ignore if TLS 1.3 is not available in the current runtime.
    }

    [System.Net.ServicePointManager]::SecurityProtocol = $desiredProtocols
    Write-ToolkitLog -Message ('Security protocol set to {0}.' -f [System.Net.ServicePointManager]::SecurityProtocol) -Type Debug -Source 'Set-SecurityProtocol'
}
