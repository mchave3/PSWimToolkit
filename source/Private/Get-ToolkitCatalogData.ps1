function Get-ToolkitCatalogData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    if (-not (Get-Variable -Name ToolkitCatalogData -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ToolkitCatalogData = $null
    }

    if (-not $script:ToolkitCatalogData) {
        $script:ToolkitCatalogData = @{
            Architectures = @('x64', 'x86', 'ARM64')
            Channels      = @('General Availability', 'Preview', 'Security Only')
            OperatingSystems = @(
                [pscustomobject]@{
                    Name      = 'Windows 11'
                    Channels  = @('General Availability', 'Preview')
                    Releases  = @(
                        [pscustomobject]@{
                            Name        = '24H2'
                            Query       = 'Windows 11 24H2'
                            BuildMin    = 26100
                            BuildMax    = 26999
                            Architectures = @('x64', 'ARM64')
                        }
                        [pscustomobject]@{
                            Name        = '23H2'
                            Query       = 'Windows 11 23H2'
                            BuildMin    = 22631
                            BuildMax    = 26099
                            Architectures = @('x64', 'ARM64')
                        }
                        [pscustomobject]@{
                            Name        = '22H2'
                            Query       = 'Windows 11 22H2'
                            BuildMin    = 22621
                            BuildMax    = 22630
                            Architectures = @('x64', 'ARM64')
                        }
                        [pscustomobject]@{
                            Name        = '21H2'
                            Query       = 'Windows 11 21H2'
                            BuildMin    = 22000
                            BuildMax    = 22620
                            Architectures = @('x64', 'ARM64')
                        }
                    )
                }
                [pscustomobject]@{
                    Name      = 'Windows 10'
                    Channels  = @('General Availability', 'Security Only')
                    Releases  = @(
                        [pscustomobject]@{
                            Name        = '22H2'
                            Query       = 'Windows 10 22H2'
                            BuildMin    = 19045
                            BuildMax    = 19999
                            Architectures = @('x64', 'x86', 'ARM64')
                        }
                        [pscustomobject]@{
                            Name        = '21H2'
                            Query       = 'Windows 10 21H2'
                            BuildMin    = 19044
                            BuildMax    = 19044
                            Architectures = @('x64', 'x86', 'ARM64')
                        }
                        [pscustomobject]@{
                            Name        = '21H1'
                            Query       = 'Windows 10 21H1'
                            BuildMin    = 19043
                            BuildMax    = 19043
                            Architectures = @('x64', 'x86')
                        }
                        [pscustomobject]@{
                            Name        = '20H2'
                            Query       = 'Windows 10 20H2'
                            BuildMin    = 19042
                            BuildMax    = 19042
                            Architectures = @('x64', 'x86')
                        }
                    )
                }
                [pscustomobject]@{
                    Name      = 'Windows Server'
                    Channels  = @('General Availability')
                    Releases  = @(
                        [pscustomobject]@{
                            Name        = '2025'
                            Query       = 'Windows Server 2025'
                            BuildMin    = 26100
                            BuildMax    = 26999
                            Architectures = @('x64')
                        }
                        [pscustomobject]@{
                            Name        = '2022'
                            Query       = 'Windows Server 2022'
                            BuildMin    = 20348
                            BuildMax    = 20999
                            Architectures = @('x64')
                        }
                        [pscustomobject]@{
                            Name        = '2019'
                            Query       = 'Windows Server 2019'
                            BuildMin    = 17763
                            BuildMax    = 18999
                            Architectures = @('x64')
                        }
                        [pscustomobject]@{
                            Name        = '2016'
                            Query       = 'Windows Server 2016'
                            BuildMin    = 14393
                            BuildMax    = 17699
                            Architectures = @('x64')
                        }
                    )
                }
            )
        }
    }

    return $script:ToolkitCatalogData
}
