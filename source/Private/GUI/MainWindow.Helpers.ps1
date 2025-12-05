function Get-XamlNamedElements {
    <#
    .SYNOPSIS
        Extracts all x:Name attributes from XAML content recursively.
    .DESCRIPTION
        Parses XAML XML document and finds all elements with x:Name attribute,
        returning them as a list of control names for dynamic binding.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [xml] $XamlDocument
    )

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($XamlDocument.NameTable)
    $namespaceManager.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')

    $namedNodes = $XamlDocument.SelectNodes('//*[@x:Name]', $namespaceManager)
    $controlNames = [System.Collections.Generic.List[string]]::new()

    foreach ($node in $namedNodes) {
        $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $controlNames.Add($name)
        }
    }

    return $controlNames.ToArray()
}

function Get-WindowControls {
    <#
    .SYNOPSIS
        Dynamically binds all named XAML controls to a hashtable.
    .DESCRIPTION
        Uses the XAML document to find all x:Name elements and creates
        a hashtable with control references from the loaded window.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [System.Windows.Window] $Window,

        [Parameter(Mandatory)]
        [xml] $XamlDocument
    )

    $controlNames = Get-XamlNamedElements -XamlDocument $XamlDocument
    $controls = @{}

    foreach ($name in $controlNames) {
        $control = $Window.FindName($name)
        if ($null -ne $control) {
            $controls[$name] = $control
        }
        else {
            Write-Warning "Control '$name' defined in XAML but not found in window."
        }
    }

    return $controls
}

function Invoke-UiAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Windows.Threading.Dispatcher] $Dispatcher,

        [Parameter(Mandatory)]
        [scriptblock] $Action
    )

    if ($Dispatcher.CheckAccess()) {
        & $Action
        return
    }

    $Dispatcher.Invoke($Action)
}

function Open-FolderPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        [System.Windows.MessageBox]::Show("No path configured for $DisplayName.", 'PSWimToolkit', 'OK', 'Information') | Out-Null
        return
    }

    $resolvedPath = $Path

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }

        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    } catch {
        [System.Windows.MessageBox]::Show("Unable to prepare $DisplayName folder: $($_.Exception.Message)", 'PSWimToolkit', 'OK', 'Error') | Out-Null
        return
    }

    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @("`"$resolvedPath`"") -WindowStyle Normal | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("Unable to open $DisplayName folder: $($_.Exception.Message)", 'PSWimToolkit', 'OK', 'Error') | Out-Null
    }
}

function Add-SharedGuiStyles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement] $Target
    )

    $stylesDocument = $Context.StylesXmlDocument
    if (-not $Target -or -not $stylesDocument) {
        return
    }

    try {
        $stylesReader = New-Object System.Xml.XmlNodeReader $stylesDocument
        $stylesDictionary = [Windows.Markup.XamlReader]::Load($stylesReader)
        $Target.Resources.MergedDictionaries.Add($stylesDictionary) | Out-Null
    } catch {
        if (-not $Context.StylesLoadWarningEmitted) {
            Write-Warning "Failed to load GUI styles: $($_.Exception.Message)"
            $Context.StylesLoadWarningEmitted = $true
        }
    }
}

function Update-Status {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [Windows.Media.Brush] $Brush
    )

    $window = $Context.Window
    $controls = $Context.Controls

    if (-not $Brush) {
        $Brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x2B, 0x57, 0x9A))
    }

    Invoke-UiAction -Dispatcher $window.Dispatcher -Action {
        $controls.StatusTextBlock.Text = $Message
        $controls.StatusTextBlock.Foreground = $Brush
    }
}

function Refresh-ThrottleText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [double] $Value
    )

    $Context.Controls.ThrottleValueText.Text = [Math]::Round($Value).ToString()
}

function Enable-ControlSet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [bool] $Enabled
    )

    $controls = $Context.Controls

    $controls.DownloadUpdatesMenuItem.IsEnabled = $Enabled
    $controls.ClearLogsMenuItem.IsEnabled = $Enabled
    $controls.ExportLogsMenuItem.IsEnabled = $Enabled
    $controls.SearchCatalogButton.IsEnabled = $Enabled
    $controls.AddWimButton.IsEnabled = $Enabled
    $controls.ImportIsoButton.IsEnabled = $Enabled
    $controls.WimDetailsButton.IsEnabled = $Enabled
    $controls.RemoveWimButton.IsEnabled = $Enabled
    $controls.ClearWimButton.IsEnabled = $Enabled
    $controls.AutoDetectButton.IsEnabled = $Enabled
    $controls.StartButton.IsEnabled = $Enabled
    $controls.BrowseUpdateButton.IsEnabled = $Enabled
    $controls.BrowseSxSButton.IsEnabled = $Enabled
    $controls.BrowseOutputButton.IsEnabled = $Enabled
    $controls.WimGrid.IsReadOnly = -not $Enabled
    $controls.EnableNetFxCheckBox.IsEnabled = $Enabled
    $controls.ForceCheckBox.IsEnabled = $Enabled
    $controls.VerboseLogCheckBox.IsEnabled = $Enabled
    $controls.IncludePreviewCheckBox.IsEnabled = $Enabled
    $controls.ThrottleSlider.IsEnabled = $Enabled
    $controls.StopButton.IsEnabled = -not $Enabled
}
