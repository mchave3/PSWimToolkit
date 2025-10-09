# PSWimToolkit - Implementation Plan

## Project Overview

Create a modern PowerShell 7.4 module for Windows Image (WIM) provisioning with automatic update management. The module will integrate Microsoft Update Catalog search/download capabilities with WIM servicing operations, featuring both CLI and WPF GUI interfaces with parallel processing support.

**Author**: Mickael CHAVE
**Target PowerShell Version**: 7.4+
**Language**: English (all code and documentation)

---

## Technical Stack

- **PowerShell**: 7.4+ (required)
- **HTML Parsing**: HtmlAgilityPack (maintained from MSCatalogLTS module)
- **GUI Framework**: WPF + XAML
- **Parallel Processing**: ForEach-Object -Parallel with ThrottleLimit
- **Image Management**: DISM PowerShell module (built-in Windows)
- **Logging**: Custom logging system with console and file output

---

## Module Structure

```
PSWimToolkit/
├── source/
│   ├── Classes/
│   │   ├── WimImage.ps1                  # WIM image representation
│   │   ├── UpdatePackage.ps1             # Update package information
│   │   ├── CatalogUpdate.ps1             # Catalog search result
│   │   ├── ProvisioningJob.ps1           # Provisioning job status
│   │   └── CatalogResponse.ps1           # HTML parsing response
│   ├── Private/
│   │   ├── Initialize-HtmlParser.ps1     # HtmlAgilityPack setup
│   │   ├── Invoke-CatalogRequest.ps1     # Catalog HTTP requests
│   │   ├── Invoke-ParseDate.ps1          # Date parsing utility
│   │   ├── Get-UpdateLinks.ps1           # Extract download URLs
│   │   ├── Set-SecurityProtocol.ps1      # TLS configuration
│   │   ├── Mount-WimImage.ps1            # Mount wrapper
│   │   ├── Dismount-WimImage.ps1         # Unmount wrapper
│   │   ├── Test-WimImageVersion.ps1      # OS version detection
│   │   ├── Test-UpdateInstalled.ps1      # Check if update exists
│   │   ├── Write-ToolkitLog.ps1     # Logging utility (enhanced)
│   │   ├── Initialize-LogFile.ps1        # Log file initialization
│   │   └── Get-LogFilePath.ps1           # Log path management
│   ├── Public/
│   │   ├── Find-WindowsUpdate.ps1        # Search MS Catalog
│   │   ├── Save-WindowsUpdate.ps1        # Download updates
│   │   ├── Get-WimImageInfo.ps1          # WIM inspection
│   │   ├── Add-UpdateToWim.ps1           # Single update injection
│   │   ├── Update-WimImage.ps1           # Full provisioning
│   │   ├── Enable-WimFeature.ps1         # Enable .NET 3.5, etc.
│   │   ├── Start-ParallelProvisioning.ps1 # Parallel WIM processing
│   │   └── Start-PSWimToolkit.ps1      # Launch WPF interface
│   ├── GUI/
│   │   ├── MainWindow.xaml               # Main GUI layout
│   │   ├── MainWindow.ps1                # GUI logic/code-behind
│   │   └── Styles.xaml                   # WPF styles/themes
│   ├── Types/
│   │   ├── netstandard2.0/
│   │   │   └── HtmlAgilityPack.dll       # PS7 version
│   │   └── PSWimToolkit.Types.ps1xml     # Custom object formatting
│   ├── PSWimToolkit.psd1                 # Module manifest
│   └── PSWimToolkit.psm1                 # Module loader
├── docs/
│   ├── en-US/
│   │   ├── about_PSWimToolkit.help.txt
│   │   └── cmdlet-help/
│   └── examples/
└── build.ps1                              # Build automation
```

---

## Logging Architecture

### Logging Requirements

The module requires comprehensive logging capabilities for both troubleshooting and audit purposes.

**Key Features**:
- Console output with color-coding (Info/Warning/Error/Success/Stage)
- File logging with timestamps and rotation
- Thread-safe logging for parallel operations
- Multiple log levels: Debug, Info, Warning, Error, Success, Stage
- GUI log viewer integration
- Export logs functionality
- Performance optimized (minimal overhead)

### Log Levels

| Level   | Description                        | Color  | Console | File |
|---------|-----------------------------------|--------|---------|------|
| Debug   | Detailed technical information    | Gray   | No*     | Yes  |
| Info    | General informational messages    | White  | Yes     | Yes  |
| Warning | Non-critical issues               | Yellow | Yes     | Yes  |
| Error   | Critical errors requiring attention| Red   | Yes     | Yes  |
| Success | Operation completed successfully  | Green  | Yes     | Yes  |
| Stage   | Major workflow milestones         | Cyan   | Yes     | Yes  |

*Debug only displayed when `-Verbose` is used

### Implementation Details

#### Write-ToolkitLog.ps1 (Private Function)
Centralized logging function for all module operations.

**Parameters**:
- `Message` (string) - The message to log
- `Type` (LogLevel enum) - Log level
- `Source` (string) - Optional source identifier (function name, class, etc.)
- `NoConsole` (switch) - Skip console output
- `NoFile` (switch) - Skip file logging

**Features**:
- Thread-safe file writes using mutex
- Automatic log rotation when size > 10 MB
- Timestamp format: `yyyy-MM-dd HH:mm:ss`
- Console color-coding
- Performance: < 5ms per log entry

#### Log File Management

**Default Log Location**: `$env:TEMP\PSWimToolkit\Logs\`
**File Naming**: `PSWimToolkit_YYYYMMDD_HHmmss.log`
**Max File Size**: 10 MB
**Retention**: Keep last 10 log files
**Format**: Plain text with UTF-8 encoding

**Example Log Entry**:
```
[2025-10-07 14:32:15] [INFO]    [Find-WindowsUpdate] Searching catalog for: Windows 11 23H2
[2025-10-07 14:32:17] [SUCCESS] [Find-WindowsUpdate] Found 15 updates
[2025-10-07 14:32:20] [STAGE]   [Update-WimImage] Starting provisioning: install.wim
[2025-10-07 14:32:25] [INFO]    [Mount-WimImage] Mounting image at C:\Mount\install.wim-guid
[2025-10-07 14:33:45] [WARNING] [Add-UpdateToWim] KB5043080 already installed, skipping
[2025-10-07 14:45:12] [ERROR]   [Add-UpdateToWim] Failed to apply KB5044033: Access denied
```

#### Configuration

Logging behavior can be configured via module-level variables:

```powershell
# Set in PSWimToolkit.psm1
$script:LogConfig = @{
    LogPath = "$env:TEMP\PSWimToolkit\Logs"
    MaxLogSizeMB = 10
    MaxLogFiles = 10
    DefaultLogLevel = 'Info'
    EnableDebugLog = $false
    EnableConsoleLog = $true
    EnableFileLog = $true
    ThreadSafe = $true
}
```

Users can override via:
```powershell
Set-PSWimToolkitLogConfig -LogPath "D:\Logs" -MaxLogSizeMB 50
```

---

## Implementation Phases

### Phase 0: Project Setup
- [x] Module template structure created
- [x] Update module manifest (PSWimToolkit.psd1)
  - [x] Set PowerShell version to 7.4
  - [x] Define exported functions
  - [x] Add required modules if any
  - [x] Update description and tags
- [x] Copy HtmlAgilityPack DLLs from MSCatalogLTS
  - [x] netstandard2.0 version for PS7
- [x] Configure module loader (PSWimToolkit.psm1)
  - [x] Load HtmlAgilityPack assembly
  - [x] Initialize logging configuration
  - [x] Dot-source Classes (ordered)
  - [x] Dot-source Private functions
  - [x] Dot-source Public functions
  - [x] Export public functions
- [x] Configure build script

---

### Phase 1: Foundation & Catalog Integration
**Goal**: Port MSCatalogLTS functionality with necessary adaptations

#### Classes
- [x] **CatalogResponse.ps1**
  - [x] Port from MSCatalogLTS
  - [x] Properties: Rows, NextPage
  - [x] Constructor from HtmlDocument
- [x] **CatalogUpdate.ps1**
  - [x] Port MSCatalogUpdate class
  - [x] Properties: Title, Products, Classification, LastUpdated, Version, Size, SizeInBytes, Guid, FileNames
  - [x] Constructor from HTML row
  - [x] Add method: GetDownloadLinks()
- [x] **UpdatePackage.ps1**
  - [x] Represents downloaded update file
  - [x] Properties: FilePath, FileName, KB, Size, Hash
  - [x] Methods: Verify(), Install()
- [x] **WimImage.ps1**
  - [x] Represents WIM file
  - [x] Properties: Path, Index, Name, Description, Version, Size, Architecture
  - [x] Methods: Mount(), Dismount(), GetInfo(), GetInstalledUpdates()
- [x] **ProvisioningJob.ps1**
  - [x] Tracks provisioning progress
  - [x] Properties: WimImage, Status, StartTime, EndTime, UpdatesApplied, UpdatesFailed, Errors, LogFile
  - [x] Methods: Start(), Complete(), AddError(), GetLog()

#### Private Functions (Catalog)
- [x] **Initialize-HtmlParser.ps1**
  - [x] Check if HtmlAgilityPack loaded
  - [x] Load appropriate DLL version
  - [x] Handle errors gracefully
- [x] **Set-SecurityProtocol.ps1**
  - [x] Port from MSCatalogLTS (Set-TempSecurityProtocol)
  - [x] Set TLS 1.2/1.3 for HTTPS
  - [x] Reset to default option
- [x] **Invoke-CatalogRequest.ps1**
  - [x] Port from MSCatalogLTS
  - [x] HTTP requests with retry logic
  - [x] Return CatalogResponse object
  - [x] Handle catalog errors (8DDD0010, etc.)
  - [x] Logging integration
- [x] **Invoke-ParseDate.ps1**
  - [x] Port from MSCatalogLTS
  - [x] Parse various date formats from catalog
  - [x] Return DateTime object
- [x] **Get-UpdateLinks.ps1**
  - [x] Port from MSCatalogLTS
  - [x] Extract download URLs using regex
  - [x] Return array of links with KB numbers

#### Private Functions (Logging)
- [x] **Write-ToolkitLog.ps1**
  - [x] Core logging function
  - [x] Parameters: Message, Type, Source, NoConsole, NoFile
  - [x] Color-coded console output
  - [x] Thread-safe file writing with mutex
  - [x] Format: [timestamp] [level] [source] message
  - [x] Performance optimized
- [x] **Initialize-LogFile.ps1**
  - [x] Create log directory if not exists
  - [x] Generate log filename with timestamp
  - [x] Check and rotate old logs
  - [x] Return log file path
- [x] **Get-LogFilePath.ps1**
  - [x] Return current log file path
  - [x] Handle log rotation logic
  - [x] Cleanup old log files (keep last N)

- [x] **Find-WindowsUpdate.ps1**
  - [x] Port Get-MSCatalogUpdate functionality
  - [x] Parameter sets: Search, OperatingSystem
  - [x] Parameters:
    - [x] -Search (string)
    - [x] -OperatingSystem (Win10/Win11/Server)
    - [x] -Version (22H2, 23H2, 24H2, etc.)
    - [x] -Architecture (x64, x86, ARM64, All)
    - [x] -UpdateType (Cumulative, Security, etc.)
    - [x] -AllPages (switch)
    - [x] -IncludePreview (switch)
    - [x] -ExcludeFramework (switch)
  - [x] Return CatalogUpdate[] objects
  - [x] Logging integration
- [x] **Save-WindowsUpdate.ps1**
  - [x] Port Save-MSCatalogUpdate functionality
  - [x] Accept CatalogUpdate from pipeline
  - [x] Download to specified path
  - [x] Progress reporting
  - [x] Verify download integrity
  - [x] Return UpdatePackage object
  - [x] Logging integration

---

### Phase 2: WIM Operations
**Goal**: Implement core WIM provisioning functionality from existing script

#### Private Functions (WIM)
- [x] **Mount-WimImage.ps1**
  - [x] Wrapper around Mount-WindowsImage
  - [x] Parameter: WimImage object or path
  - [x] Parameter: MountPath
  - [x] Parameter: Index (default 1)
  - [x] Validation: Path exists, mount directory empty
  - [x] Error handling with cleanup
  - [x] Logging integration
  - [x] Return mount information
- [x] **Dismount-WimImage.ps1**
  - [x] Wrapper around Dismount-WindowsImage
  - [x] Parameter: MountPath
  - [x] Parameter: Save/Discard
  - [x] Clean up mount directory
  - [x] Error handling
  - [x] Logging integration
- [x] **Test-WimImageVersion.ps1**
  - [x] Get OS version from mounted image
  - [x] Detect: Windows 10, Windows 11 (23H2, 24H2)
  - [x] Return version object
  - [x] Logging integration
- [x] **Test-UpdateInstalled.ps1**
  - [x] Check if KB already installed
  - [x] Use Get-WindowsPackage
  - [x] Return boolean
  - [x] Logging integration

#### Public Functions (WIM)
- [x] **Get-WimImageInfo.ps1**
  - [x] Get information about WIM file(s)
  - [x] Parameters:
    - [x] -Path (string[]) - supports wildcards
    - [x] -Index (int) - specific index or all
  - [x] Return WimImage[] objects
  - [x] Properties: All DISM info + custom props
  - [x] Logging integration
- [x] **Add-UpdateToWim.ps1**
  - [x] Add single update to mounted WIM
  - [x] Parameters:
    - [x] -MountPath (string)
    - [x] -UpdatePath (string) - .msu or .cab file
    - [x] -Force (skip installed check)
  - [x] Check if already installed (skip if present)
  - [x] Use Add-WindowsPackage
  - [x] Progress reporting
  - [x] Error handling
  - [x] Logging integration
  - [x] Return result object
- [x] **Update-WimImage.ps1**
  - [x] Full provisioning workflow (port from script)
  - [x] Parameters:
    - [x] -WimPath (string)
    - [x] -Index (int)
    - [x] -UpdatePath (string) - folder with updates
    - [x] -SxSPath (string) - for .NET 3.5
    - [x] -EnableNetFx3 (switch)
    - [x] -OutputPath (string) - save modified WIM
    - [x] -LogPath (string) - custom log location
  - [x] Steps:
    1. Initialize logging
    2. Mount WIM
    3. Detect OS version
    4. Apply updates from folder
    5. Special handling for KB5043080 (Win11 24H2)
    6. Enable .NET 3.5 if requested
    7. Dismount and save
    8. Generate summary report
  - [x] Return ProvisioningJob object
  - [x] Comprehensive logging throughout
- [x] **Enable-WimFeature.ps1**
  - [x] Enable Windows features in mounted WIM
  - [x] Parameters:
    - [x] -MountPath (string)
    - [x] -FeatureName (string[]) - supports multiple
    - [x] -SxSPath (string) - source files
  - [x] Common features: NetFx3, etc.
  - [x] Use Enable-WindowsOptionalFeature
  - [x] Logging integration
  - [x] Return result

---

### Phase 3: Parallel Processing
**Goal**: Enable concurrent WIM provisioning with proper resource management

#### Public Function
- [x] **Start-ParallelProvisioning.ps1**
  - [x] Process multiple WIMs concurrently
  - [x] Parameters:
    - [x] -WimFiles (WimImage[] or FileInfo[])
    - [x] -UpdatePath (string)
    - [x] -SxSPath (string)
    - [x] -ThrottleLimit (int) - default 10, max 20
    - [x] -EnableNetFx3 (switch)
    - [x] -IndexSelection (hashtable) - WIM name -> index
    - [x] -LogPath (string) - base log directory
  - [x] Implementation:
    - [x] Create unique mount points per WIM
    - [x] Create separate log file per WIM
    - [x] Use ForEach-Object -Parallel
    - [x] Pass variables with $using:
    - [x] Collect results from all jobs
    - [x] Aggregate errors
    - [x] Overall progress reporting
    - [x] Merge logs or keep separate
  - [x] Return ProvisioningJob[] objects

#### Private Functions
- [x] **New-UniqueMountPath.ps1**
  - [x] Generate unique mount directory
  - [x] Pattern: C:\Mount\WimName-GUID
  - [x] Ensure no conflicts
  - [x] Auto-cleanup old mounts
  - [x] Logging integration
- [x] **Invoke-ParallelProgress.ps1**
  - [x] Track progress across parallel jobs
  - [x] Update parent progress bar
  - [x] Aggregate timing information
  - [x] Aggregate log information

#### Considerations
- [ ] Document DISM limitation (max 20 concurrent mounts)
- [ ] Resource monitoring (disk space, memory)
- [x] Error isolation (one failure doesn't stop others)
- [x] Cleanup on failure (unmount orphaned images)
- [x] Thread-safe logging critical for parallel operations
- [x] Each parallel job writes to its own log file

---

### Phase 4: WPF GUI
**Goal**: Create user-friendly graphical interface for non-CLI users

#### XAML Design
- [x] **MainWindow.xaml**
  - [x] Main window layout (Grid-based)
  - [x] Sections:
    - [x] WIM Selection
      - [x] File picker (single/multiple)
      - [x] Selected WIMs list with details
      - [x] Index selection per WIM
    - [x] Update Configuration
      - [x] Catalog search interface
      - [x] Or: Browse local update folder
      - [x] SxS folder selection
      - [x] Options: Enable .NET 3.5, Include Preview, etc.
    - [x] Provisioning Control
      - [x] Start/Stop/Pause buttons
      - [x] ThrottleLimit slider
      - [x] Output path selection
    - [x] Progress Display
      - [x] Overall progress bar
      - [x] Per-WIM progress (list view)
      - [x] Current operation text
    - [x] Log Viewer (NEW)
      - [x] Real-time log display (scrollable)
      - [x] Filter by log level (All/Debug/Info/Warning/Error)
      - [x] Color-coded log entries
      - [x] Auto-scroll toggle
      - [x] Save logs button
      - [x] Clear logs button
  - [x] Menu bar:
    - [x] File: Open Config, Save Config, Exit
    - [x] Tools: Download Updates, Clear Logs, Export Logs
    - [x] View: Show/Hide Log Viewer
    - [x] Help: About, Documentation
- [x] **Styles.xaml**
  - [x] Modern flat design
  - [x] Color scheme (blue/white/grey)
  - [x] Button styles
  - [x] Progress bar styles
  - [x] List view templates
  - [x] Log viewer styles (color-coded entries)

#### PowerShell Code-Behind
- [x] **MainWindow.ps1**
  - [x] Load XAML and create window
  - [x] Event handlers:
    - [x] btnBrowseWim_Click - File picker
    - [x] btnRemoveWim_Click - Remove from list
    - [x] btnBrowseUpdates_Click - Folder picker
    - [x] btnSearchCatalog_Click - Open catalog search
    - [x] btnStartProvisioning_Click - Start processing
    - [x] btnStop_Click - Cancel operations
    - [x] btnSaveLogs_Click - Export logs
    - [x] btnClearLogs_Click - Clear log viewer
    - [x] cmbLogLevel_Changed - Filter logs by level
    - [x] Window_Loaded - Initialize UI
    - [x] Window_Closing - Cleanup
  - [x] Background processing:
    - [x] Use runspaces for non-blocking operations
    - [x] Update UI from background threads (Dispatcher)
    - [x] Real-time log updates to GUI
    - [x] Progress updates
  - [x] Data binding:
    - [x] ObservableCollection for WIM list
    - [x] ObservableCollection for log entries
    - [x] Property change notifications
    - [x] Two-way binding for options
  - [x] Log integration:
    - [x] Subscribe to log events
    - [x] Update log viewer in real-time
    - [x] Color-code entries by level
    - [x] Auto-scroll implementation

#### Public Function
- [x] **Start-PSWimToolkit.ps1**
  - [x] Entry point to launch GUI
  - [x] Load XAML files
  - [x] Initialize window
  - [x] Set up log viewer
  - [x] Show modally or non-modal
  - [x] Return results when closed

---

### Phase 5: WIM Management & Catalog Enhancements
**Goal**: Deliver richer WIM tooling and smarter catalog discovery ahead of documentation freeze.

#### WIM Management Experience (MainWindow.xaml / MainWindow.ps1)
- [x] Rename the GUI section header from **WIM Selection** to **WIM Management** (XAML label, localized strings, telemetry).
- [x] Update button captions (`Add WIM` -> `Import WIM`) and ensure command bindings/event handlers reflect the new verb while keeping backward-compatible command aliases.
- [x] Add a `Details` button near the WIM list that opens a modal `WimDetailsWindow`.
- [x] Create `WimDetailsWindow.xaml` + code-behind to enumerate every WIM index via `Get-WimImageInfo`, surface metadata (edition, architecture, language packs, size), and expose export/copy actions.
- [x] Materialize a lightweight cache of parsed WIM metadata so repeated detail launches avoid redundant DISM calls; invalidate when selections change or provisioning completes.
- [x] Introduce an `Import ISO` button beside `Import WIM` with workflow status updates and reuse of shared helpers.
- [x] Implement ISO ingestion helpers (`Import-WimFromIso`, `Resolve-WimCatalogProfile`, etc.) that mount ISOs, unwrap install sources, convert `.esd` when requested, and cleanly dismount.
- [x] Extend logging hooks so WIM imports, detail views, and ISO extractions surface Stage/Info/Error events with correlation IDs.

#### Update Catalog UX & Automation
- [x] Enhance the catalog search dialog with drop-down filters (OS family, release, architecture, update type) populated from toolkit catalog facets.
- [x] Cascade filter selections to build the catalog query automatically while still permitting manual search overrides.
- [ ] Persist last-used filter defaults per user profile to streamline repeat searches. *(Defer to Phase 6 polish.)*
- [x] Countersign validation so only supported combinations (OS, release, architecture) feed catalog queries while still allowing manual refinement.
- [x] Add an `Auto Detect` button next to `Search Catalog` in the main window command bar.
- [x] Implement an auto-detect workflow that inspects the currently selected WIMs, proposes applicable updates, and displays them in a dedicated dialog with multi-select + queue-to-download.
- [x] Ensure auto-detect results can funnel directly into download/provision pipelines and emit structured logging objects for traceability.

#### Shared ViewModels & Services
- [x] Update the GUI backing script to support new commands (`Show-WimDetails`, `ImportIso`, `Show-AutoDetectDialog`) and state refresh pipelines.
- [x] Share catalog filter definitions between CLI/GUI by surfacing them through a new `Get-ToolkitCatalogFacet` helper.
- [ ] Expand unit tests for ISO import helpers, detail parsing, and catalog auto-detect heuristics (mock DISM/MSCatalog calls). *(Open item.)*

**Phase 5 Status**: ✅ Core UX/functionality re-implemented on 2025-10-09 using MSCatalogLTS logic (GUI rename, ISO import workflow, detail viewer, catalog facets, auto-detect).  
**Open Follow-ups**: Persist catalog filter defaults; add dedicated unit tests for ISO/import and auto-detect helpers leveraging the MSCatalogLTS search surface.

---

### Phase 6: Documentation & Polish
**Goal**: Professional documentation and final refinements

#### User Documentation
- [ ] **README.md**
  - [ ] Project description
  - [ ] Features overview
  - [ ] Installation instructions
  - [ ] Quick start examples
  - [ ] Screenshots (GUI with log viewer)
  - [ ] Links to detailed docs
  - [ ] Logging configuration guide
- [ ] **about_PSWimToolkit.help.txt**
  - [ ] Module overview
  - [ ] Key concepts
  - [ ] Workflow examples
  - [ ] Best practices
  - [ ] Logging configuration
  - [ ] Troubleshooting (using logs)
- [ ] **Cmdlet Help** (comment-based help for all public functions)
  - [ ] Synopsis
  - [ ] Description
  - [ ] Parameters (with examples)
  - [ ] Examples (at least 3 per function)
  - [ ] Notes (including logging info)
  - [ ] Links
- [ ] **Examples** (docs/examples/)
  - [ ] Example 1: Search and download updates
  - [ ] Example 2: Provision single WIM
  - [ ] Example 3: Batch provision with parallel
  - [ ] Example 4: Use GUI
  - [ ] Example 5: Custom workflow
  - [ ] Example 6: Custom logging configuration

#### Developer Documentation
- [ ] **Architecture.md**
  - [ ] Module structure explanation
  - [ ] Class diagram
  - [ ] Data flow
  - [ ] Logging architecture diagram
  - [ ] Key design decisions
- [ ] **Contributing.md**
  - [ ] How to contribute
  - [ ] Code standards
  - [ ] Logging standards
  - [ ] Pull request process
- [ ] **API Reference**
  - [ ] Auto-generated from help if possible
  - [ ] Class documentation
  - [ ] Private function documentation
  - [ ] Logging API

#### Code Quality
- [ ] Code review and refactoring
  - [ ] Consistent naming conventions
  - [ ] Remove duplicate code
  - [ ] Optimize performance
  - [ ] Add error handling everywhere
  - [ ] Consistent logging throughout
- [ ] PSScriptAnalyzer
  - [ ] Run analyzer on all .ps1 files
  - [ ] Fix all warnings/errors
  - [ ] Configure custom rules if needed

#### Final Steps
- [ ] Version 1.0.0 release
  - [ ] Update module manifest with final version
  - [ ] Generate changelog
  - [ ] Tag repository
- [ ] Publish to PowerShell Gallery (optional)
  - [ ] Create API key
  - [ ] Test in isolated environment
  - [ ] Publish-Module
  - [ ] Verify listing

---

## Technical Decisions & Considerations

### HtmlAgilityPack (Maintained from MSCatalogLTS)

**Decision**: Keep HtmlAgilityPack as in MSCatalogLTS
**Rationale**:
- Proven working code
- Minimal migration effort
- Well-understood by team
- No breaking changes needed

**Implementation**:
```powershell
# Module loader (PSWimToolkit.psm1)
try {
    if (!([System.Management.Automation.PSTypeName]'HtmlAgilityPack.HtmlDocument').Type) {
        if ($PSVersionTable.PSEdition -eq "Desktop") {
            throw "This module requires PowerShell 7.4+"
        } else {
            Add-Type -Path "$PSScriptRoot\Types\netstandard2.0\HtmlAgilityPack.dll"
        }
    }
} catch {
    Write-Error "Failed to load HtmlAgilityPack: $_"
    throw
}
```

### Parallel Processing Strategy

**Decision**: ForEach-Object -Parallel with conservative ThrottleLimit
**Rationale**:
- Native PS7 feature
- DISM supports max 20 concurrent mounts (best practice)
- Each WIM needs isolated mount point
- Balance performance vs. resource consumption

**Implementation Pattern**:
```powershell
$WimFiles | ForEach-Object -Parallel {
    $MountPath = New-Item "C:\Mount\$($_.BaseName)-$(New-Guid)" -ItemType Directory -Force
    $LogFile = "$using:LogBasePath\$($_.BaseName).log"

    try {
        # Initialize thread-specific logging
        & $using:InitLogFunction -LogPath $LogFile

        Mount-WindowsImage -ImagePath $_.FullName -Path $MountPath -Index $using:Index
        # Apply updates...
        Dismount-WindowsImage -Path $MountPath -Save
    } catch {
        Write-Error $_
        & $using:LogFunction -Message "Failed to process $($_.Name): $_" -Type Error
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $MountPath -Recurse -Force -ErrorAction SilentlyContinue
    }
} -ThrottleLimit 10
```

**Key Considerations**:
- Use `$using:` for external variables
- Isolated error handling per job
- Cleanup in finally block
- Conservative default throttle (10, not 20)
- Separate log file per thread

### GUI Architecture

**Decision**: WPF with XAML and code-behind pattern
**Rationale**:
- Native Windows integration
- Separation of UI and logic
- Designer-friendly
- Responsive with async operations

**Challenges**:
- UI updates from background threads (use Dispatcher)
- State management across operations
- Error display and recovery
- Configuration persistence
- Real-time log streaming to GUI

### Logging Architecture

**Decision**: Custom logging system with thread-safe file writes
**Rationale**:
- Full control over format and behavior
- Thread-safe for parallel operations (mutex-based)
- Performance optimized
- GUI integration capability
- No external dependencies

**Thread Safety Implementation**:
```powershell
# Write-ToolkitLog.ps1
$script:LogMutex = New-Object System.Threading.Mutex($false, "PSWimToolkit_LogMutex")

function Write-ToolkitLog {
    param($Message, $Type)

    # Console output (always safe)
    Write-Host "[$Type] $Message" -ForegroundColor $Color

    # File output (mutex protected)
    if ($script:LogConfig.EnableFileLog) {
        try {
            $null = $script:LogMutex.WaitOne()
            $LogEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Type] $Message"
            Add-Content -Path $script:CurrentLogFile -Value $LogEntry -Encoding UTF8
        } finally {
            $script:LogMutex.ReleaseMutex()
        }
    }
}
```

### Special Cases

#### Windows 11 24H2 - KB5043080
This update must be installed first, before other updates:
```powershell
if ($OSVersion -ge "10.0.26100.0") {
    Write-ToolkitLog -Message "Detected Windows 11 24H2, checking for KB5043080" -Type Info

    $KB5043080 = $Updates | Where-Object { $_.Name -like "*KB5043080*" }
    if ($KB5043080 -and -not (Test-UpdateInstalled -MountPath $MountPath -KB "KB5043080")) {
        Write-ToolkitLog -Message "Installing KB5043080 first (required for 24H2)" -Type Stage
        Add-WindowsPackage -Path $MountPath -PackagePath $KB5043080.FullName
        Write-ToolkitLog -Message "KB5043080 installed successfully" -Type Success
    }
    $Updates = $Updates | Where-Object { $_ -ne $KB5043080 }
}
```

#### .NET Framework 3.5
Requires SxS source files from installation media:
- Windows 10 22H2: Different SxS folder
- Windows 11 23H2: Different SxS folder
- Windows 11 24H2: Different SxS folder

Must detect version and use appropriate source.

```powershell
Write-ToolkitLog -Message "Enabling .NET Framework 3.5" -Type Stage
$SxSPath = switch ($OSVersion) {
    { $_ -lt "10.0.22000.0" } { $SxSPaths.Win10_22H2 }
    { $_ -ge "10.0.26100.0" } { $SxSPaths.Win11_24H2 }
    default { $SxSPaths.Win11_23H2 }
}
Write-ToolkitLog -Message "Using SxS source: $SxSPath" -Type Info
Enable-WindowsOptionalFeature -Path $MountPath -FeatureName NetFx3 -All -Source $SxSPath -LimitAccess
```

### DISM Limitations & Best Practices

1. **Concurrent Mounts**: Max 20 recommended, but 10-15 more stable
2. **Resource Intensive**: Each mount uses significant RAM
3. **Antivirus**: Exclude mount folders from real-time scanning
4. **Cleanup**: Always dismount, even on error
5. **Disk Space**: Each mount needs free space (10+ GB recommended)

### Error Handling Strategy

1. **Validation**: Check prerequisites before operations
2. **Graceful Degradation**: Continue processing other WIMs on error
3. **Cleanup**: Always cleanup resources (mount points, temp files)
4. **Logging**: Detailed logs for troubleshooting (CRITICAL)
5. **User Feedback**: Clear error messages with resolution steps

---

## Open Questions & Future Enhancements

### Phase 1 Questions
- [ ] Should we support downloading directly from catalog, or only local files?
- [ ] Configuration file format: JSON, XML, or PSD1?
- [ ] Localization: English only, or multi-language support?
- [ ] Remote logging: Send logs to central server?

### Future Enhancements (Post v1.0)
- [ ] ISO extraction and mounting
- [ ] Driver injection support
- [ ] Custom Windows features management
- [ ] Scheduled provisioning (task scheduler integration)
- [ ] Network share support for WIM storage
- [ ] Reporting: HTML/PDF reports of provisioning results
- [ ] REST API for integration with other tools
- [ ] Web-based GUI (optional alternative to WPF)
- [ ] Centralized logging server
- [ ] Log analytics and visualization

---

## Timeline Estimate

| Phase | Estimated Duration | Dependencies |
|-------|-------------------|--------------|
| Phase 0: Setup | 1-2 days | None |
| Phase 1: Catalog + Logging | 4-6 days | Phase 0 |
| Phase 2: WIM Ops | 5-7 days | Phase 0, 1 |
| Phase 3: Parallel | 3-4 days | Phase 2 |
| Phase 4: GUI | 7-10 days | Phase 2, 3 |
| Phase 5: WIM Mgmt + Catalog UX | 5-7 days | Phase 1-4 |
| Phase 6: Docs | 3-5 days | Phase 1-5 |
| **Total** | **28-41 days** | |

*Note: Timeline assumes dedicated development time. Adjust for part-time work. Logging adds 1-2 days.*

---

## Success Criteria

### Minimum Viable Product (MVP)
- [x] Module structure complete
- [ ] Search catalog for updates (CLI)
- [ ] Download updates (CLI)
- [ ] Provision single WIM with updates (CLI)
- [ ] Provision multiple WIMs in parallel (CLI)
- [ ] Basic error handling and logging
- [ ] Log files created with proper format
- [ ] Core documentation

### Version 1.0 Complete
- [ ] All phases 0-6 complete
- [ ] WPF GUI functional with log viewer
- [x] WIM Management workspace supports Import WIM/ISO and detail workflow
- [x] Catalog search dialog ships with facet filters and auto-detect pipeline
- [ ] Full documentation
- [ ] PSScriptAnalyzer clean
- [ ] Thread-safe logging verified
- [ ] Ready for production use

### Stretch Goals
- [ ] Published to PowerShell Gallery
- [ ] Community contributions accepted
- [ ] Video tutorials created
- [ ] Integration with MDT/SCCM workflows
- [ ] Log analytics dashboard

---

## Maintenance Plan

### Version Numbering
- **Major** (X.0.0): Breaking changes, major features
- **Minor** (0.X.0): New features, non-breaking
- **Patch** (0.0.X): Bug fixes only

### Support
- GitHub issues for bug reports
- GitHub discussions for questions
- Pull requests welcome with guidelines

### Updates
- Monitor Microsoft Catalog for HTML changes
- Update HtmlAgilityPack periodically
- Keep DISM cmdlet usage current
- Test with new Windows versions

---

**Last Updated**: 2025-10-09
**Status**: Phase 5 Completed
**Next Milestone**: Kick off Phase 6 Documentation & Polish
