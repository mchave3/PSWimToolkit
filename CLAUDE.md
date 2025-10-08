# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PSWimToolkit** is a PowerShell 7.4+ module for automated Windows Image (WIM) provisioning with Microsoft Update Catalog integration. The module enables searching, downloading, and injecting Windows updates into WIM files, with support for parallel processing and a WPF GUI interface.

**Key Requirements:**
- PowerShell 7.4+ only (no PowerShell 5.1 support)
- All code and documentation must be in English
- No automated tests (unit/integration) - manual testing only
- HtmlAgilityPack for HTML parsing (ported from MSCatalogLTS module)

## Build System

This project uses **Sampler** build framework with InvokeBuild.

### Common Commands

```powershell
# First-time setup: Install dependencies
.\build.ps1 -ResolveDependency -Tasks noop

# Build the module
.\build.ps1

# Run PSScriptAnalyzer
.\build.ps1 -Tasks Invoke_ScriptAnalyzer

# Clean build output
.\build.ps1 -Tasks Clean
```

**Note:** The build system references Pester tests in its configuration, but the project does not implement any tests. Ignore test-related tasks.

## Architecture

### Module Structure

```
source/
├── Classes/              # PowerShell classes (load order matters)
│   ├── CatalogResponse.ps1       # HTML parsing response from catalog
│   ├── CatalogUpdate.ps1         # Update search result representation
│   ├── UpdatePackage.ps1         # Downloaded update file metadata
│   ├── WimImage.ps1              # WIM file representation
│   └── ProvisioningJob.ps1       # Job status and tracking
├── Private/              # Internal helper functions
│   ├── [Catalog functions]       # Ported from MSCatalogLTS
│   ├── [WIM functions]           # DISM wrappers
│   └── [Logging functions]       # Thread-safe logging system
├── Public/               # Exported module functions
│   ├── Find-WindowsUpdate.ps1    # Search MS Update Catalog
│   ├── Save-WindowsUpdate.ps1    # Download updates
│   ├── Get-WimImageInfo.ps1      # Inspect WIM files
│   ├── Add-UpdateToWim.ps1       # Inject single update
│   ├── Update-WimImage.ps1       # Full provisioning workflow
│   ├── Enable-WimFeature.ps1     # Enable Windows features
│   ├── Start-ParallelProvisioning.ps1  # Parallel WIM processing
│   └── Show-ProvisioningGUI.ps1  # Launch WPF interface
├── GUI/                  # WPF interface
│   ├── MainWindow.xaml           # UI layout
│   ├── MainWindow.ps1            # Event handlers and logic
│   └── Styles.xaml               # Visual styles
├── Types/
│   ├── netstandard2.0/HtmlAgilityPack.dll  # HTML parsing library
│   └── PSWimToolkit.Types.ps1xml # Custom object formatting
├── PSWimToolkit.psd1     # Module manifest
└── PSWimToolkit.psm1     # Module loader
```

### Code Organization Principles

**Class Loading Order:**
Classes must be dot-sourced in dependency order in `PSWimToolkit.psm1`. Base classes before derived classes.

**Function Naming:**
- Public functions: Verb-Noun format (e.g., `Find-WindowsUpdate`)
- Private functions: Same convention, not exported
- Internal wrappers use same names as DISM cmdlets with module prefix

**Logging Architecture:**
- All operations must log through `Write-ToolkitLog`
- Thread-safe mutex-based file writing for parallel operations
- Log levels: Debug, Info, Warning, Error, Success, Stage
- Default location: `$env:TEMP\PSWimToolkit\Logs\`
- Auto-rotation at 10MB, keep last 10 files

## Migration from MSCatalogLTS

The catalog search functionality is ported from the `Archives/MSCatalogLTS/` module with these changes:

**Function Mappings:**
- `Get-MSCatalogUpdate` → `Find-WindowsUpdate`
- `Save-MSCatalogUpdate` → `Save-WindowsUpdate`
- `MSCatalogUpdate` class → `CatalogUpdate` class

**Key Differences:**
- Replace `Write-Host`/`Write-Warning` with `Write-ToolkitLog`
- Return strongly-typed custom objects instead of PSCustomObjects where possible
- Integrate with ProvisioningJob tracking

**Direct Ports (minimal changes):**
- `Invoke-CatalogRequest.ps1` - HTTP requests and HTML document loading
- `Invoke-ParseDate.ps1` - Date parsing from catalog HTML
- `Get-UpdateLinks.ps1` - Extract download URLs via regex
- `Set-TempSecurityProtocol.ps1` → `Set-SecurityProtocol.ps1`

## Special Considerations

### Windows 11 24H2 - KB5043080
This update must be installed **first** before other updates on Windows 11 24H2 (version ≥ 10.0.26100.0). Check for and install it separately before processing other updates.

### .NET Framework 3.5
Requires SxS source files from installation media. Different paths for:
- Windows 10 22H2
- Windows 11 23H2
- Windows 11 24H2

Detect OS version from mounted image and use appropriate SxS path.

### DISM Limitations
- Maximum 20 concurrent image mounts (best practice: 10-15)
- Each mount consumes significant RAM
- Always dismount images, even on error (use try/finally)
- Exclude mount directories from antivirus scanning
- Requires administrator privileges

### Parallel Processing
Use `ForEach-Object -Parallel` with:
- Unique mount paths per WIM (pattern: `C:\Mount\WimName-{GUID}`)
- Separate log file per thread
- `$using:` scope for external variables
- Conservative ThrottleLimit (default 10, max 20)
- Isolated error handling per job

## Development Workflow

### Phase 0: Project Setup (Current Phase)
1. Update `PSWimToolkit.psd1` manifest
   - Set PowerShellVersion to '7.4'
   - Define FunctionsToExport list
2. Copy HtmlAgilityPack DLL from `Archives/MSCatalogLTS/Types/netstandard2.0/`
3. Configure module loader with HtmlAgilityPack loading and logging initialization
4. Implement dot-sourcing logic for Classes, Private, Public functions

### Implementation Phases
See `PLAN.md` for detailed phase breakdown:
- Phase 1: Foundation & Catalog Integration (port MSCatalogLTS)
- Phase 2: WIM Operations (DISM wrappers, update injection)
- Phase 3: Parallel Processing
- Phase 4: WPF GUI
- Phase 5: Documentation & Polish

### Code Style
- Use approved PowerShell verbs (`Get-Verb`)
- Follow PSScriptAnalyzer rules (run before committing)
- Use comment-based help for all public functions
- Parameter validation with `[ValidateSet]`, `[ValidateScript]`, etc.
- Prefer splatting for cmdlets with many parameters

### Error Handling Strategy
1. Validate prerequisites before operations
2. Use try/catch/finally blocks
3. Log all errors with `Write-ToolkitLog -Type Error`
4. Clean up resources in finally blocks (unmount WIMs, remove temp files)
5. Continue processing other items on error (graceful degradation)

## Critical Files

**PLAN.md** - Complete implementation plan with checkboxes for tracking progress. Reference this file for:
- Detailed task breakdown per phase
- Function specifications and parameters
- Technical decisions and rationale
- Timeline estimates

**Archives/MSCatalogLTS/** - Source code to port for catalog functionality. Study this code before implementing Phase 1.

## Module Loader Pattern

```powershell
# PSWimToolkit.psm1 structure
try {
    # 1. Load HtmlAgilityPack
    if (!([System.Management.Automation.PSTypeName]'HtmlAgilityPack.HtmlDocument').Type) {
        Add-Type -Path "$PSScriptRoot\Types\netstandard2.0\HtmlAgilityPack.dll"
    }

    # 2. Initialize logging configuration
    $script:LogConfig = @{ ... }

    # 3. Dot-source Classes (in dependency order)
    $Classes = @(Get-ChildItem -Path $PSScriptRoot\Classes\*.ps1 -ErrorAction SilentlyContinue)
    foreach ($import in $Classes) {
        . $import.FullName
    }

    # 4. Dot-source Private functions
    $Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
    foreach ($import in $Private) {
        . $import.FullName
    }

    # 5. Dot-source Public functions
    $Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
    foreach ($import in $Public) {
        . $import.FullName
    }

    # 6. Export public functions
    Export-ModuleMember -Function $Public.BaseName

} catch {
    Write-Error "Failed to load module: $_"
    throw
}
```

## PSScriptAnalyzer

All code must pass PSScriptAnalyzer with default rules. Run before committing:

```powershell
.\build.ps1 -Tasks Invoke_ScriptAnalyzer
```

Fix all warnings and errors. The project does not use custom analyzer rules.

## Reference Documentation

- **PLAN.md** - Implementation roadmap and specifications
- **Archives/MSCatalogLTS/** - Source code for catalog functionality
- Microsoft DISM PowerShell cmdlets: `Get-Command -Module DISM`
- WPF/XAML documentation for GUI development (Phase 4)
