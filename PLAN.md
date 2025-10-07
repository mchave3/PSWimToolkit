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
│   │   ├── Write-ProvisioningLog.ps1     # Logging utility (enhanced)
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
│   │   └── Show-ProvisioningGUI.ps1      # Launch WPF interface
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

#### Write-ProvisioningLog.ps1 (Private Function)
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
- [ ] Update module manifest (PSWimToolkit.psd1)
  - [ ] Set PowerShell version to 7.4
  - [ ] Define exported functions
  - [ ] Add required modules if any
  - [ ] Update description and tags
- [ ] Copy HtmlAgilityPack DLLs from MSCatalogLTS
  - [ ] netstandard2.0 version for PS7
- [ ] Configure module loader (PSWimToolkit.psm1)
  - [ ] Load HtmlAgilityPack assembly
  - [ ] Initialize logging configuration
  - [ ] Dot-source Classes (ordered)
  - [ ] Dot-source Private functions
  - [ ] Dot-source Public functions
  - [ ] Export public functions
- [ ] Configure build script

---

### Phase 1: Foundation & Catalog Integration
**Goal**: Port MSCatalogLTS functionality with necessary adaptations

#### Classes
- [ ] **CatalogResponse.ps1**
  - [ ] Port from MSCatalogLTS
  - [ ] Properties: Rows, NextPage
  - [ ] Constructor from HtmlDocument
- [ ] **CatalogUpdate.ps1**
  - [ ] Port MSCatalogUpdate class
  - [ ] Properties: Title, Products, Classification, LastUpdated, Version, Size, SizeInBytes, Guid, FileNames
  - [ ] Constructor from HTML row
  - [ ] Add method: GetDownloadLinks()
- [ ] **UpdatePackage.ps1**
  - [ ] Represents downloaded update file
  - [ ] Properties: FilePath, FileName, KB, Size, Hash
  - [ ] Methods: Verify(), Install()
- [ ] **WimImage.ps1**
  - [ ] Represents WIM file
  - [ ] Properties: Path, Index, Name, Description, Version, Size, Architecture
  - [ ] Methods: Mount(), Dismount(), GetInfo(), GetInstalledUpdates()
- [ ] **ProvisioningJob.ps1**
  - [ ] Tracks provisioning progress
  - [ ] Properties: WimImage, Status, StartTime, EndTime, UpdatesApplied, UpdatesFailed, Errors, LogFile
  - [ ] Methods: Start(), Complete(), AddError(), GetLog()

#### Private Functions (Catalog)
- [ ] **Initialize-HtmlParser.ps1**
  - [ ] Check if HtmlAgilityPack loaded
  - [ ] Load appropriate DLL version
  - [ ] Handle errors gracefully
- [ ] **Set-SecurityProtocol.ps1**
  - [ ] Port from MSCatalogLTS (Set-TempSecurityProtocol)
  - [ ] Set TLS 1.2/1.3 for HTTPS
  - [ ] Reset to default option
- [ ] **Invoke-CatalogRequest.ps1**
  - [ ] Port from MSCatalogLTS
  - [ ] HTTP requests with retry logic
  - [ ] Return CatalogResponse object
  - [ ] Handle catalog errors (8DDD0010, etc.)
  - [ ] Logging integration
- [ ] **Invoke-ParseDate.ps1**
  - [ ] Port from MSCatalogLTS
  - [ ] Parse various date formats from catalog
  - [ ] Return DateTime object
- [ ] **Get-UpdateLinks.ps1**
  - [ ] Port from MSCatalogLTS
  - [ ] Extract download URLs using regex
  - [ ] Return array of links with KB numbers

#### Private Functions (Logging)
- [ ] **Write-ProvisioningLog.ps1**
  - [ ] Core logging function
  - [ ] Parameters: Message, Type, Source, NoConsole, NoFile
  - [ ] Color-coded console output
  - [ ] Thread-safe file writing with mutex
  - [ ] Format: [timestamp] [level] [source] message
  - [ ] Performance optimized
- [ ] **Initialize-LogFile.ps1**
  - [ ] Create log directory if not exists
  - [ ] Generate log filename with timestamp
  - [ ] Check and rotate old logs
  - [ ] Return log file path
- [ ] **Get-LogFilePath.ps1**
  - [ ] Return current log file path
  - [ ] Handle log rotation logic
  - [ ] Cleanup old log files (keep last N)

#### Public Functions (Catalog)
- [ ] **Find-WindowsUpdate.ps1**
  - [ ] Port Get-MSCatalogUpdate functionality
  - [ ] Parameter sets: Search, OperatingSystem
  - [ ] Parameters:
    - [ ] -Search (string)
    - [ ] -OperatingSystem (Win10/Win11/Server)
    - [ ] -Version (22H2, 23H2, 24H2, etc.)
    - [ ] -Architecture (x64, x86, ARM64, All)
    - [ ] -UpdateType (Cumulative, Security, etc.)
    - [ ] -AllPages (switch)
    - [ ] -IncludePreview (switch)
    - [ ] -ExcludeFramework (switch)
  - [ ] Return CatalogUpdate[] objects
  - [ ] Logging integration
- [ ] **Save-WindowsUpdate.ps1**
  - [ ] Port Save-MSCatalogUpdate functionality
  - [ ] Accept CatalogUpdate from pipeline
  - [ ] Download to specified path
  - [ ] Progress reporting
  - [ ] Verify download integrity
  - [ ] Return UpdatePackage object
  - [ ] Logging integration

---

### Phase 2: WIM Operations
**Goal**: Implement core WIM provisioning functionality from existing script

#### Private Functions (WIM)
- [ ] **Mount-WimImage.ps1**
  - [ ] Wrapper around Mount-WindowsImage
  - [ ] Parameter: WimImage object or path
  - [ ] Parameter: MountPath
  - [ ] Parameter: Index (default 1)
  - [ ] Validation: Path exists, mount directory empty
  - [ ] Error handling with cleanup
  - [ ] Logging integration
  - [ ] Return mount information
- [ ] **Dismount-WimImage.ps1**
  - [ ] Wrapper around Dismount-WindowsImage
  - [ ] Parameter: MountPath
  - [ ] Parameter: Save/Discard
  - [ ] Clean up mount directory
  - [ ] Error handling
  - [ ] Logging integration
- [ ] **Test-WimImageVersion.ps1**
  - [ ] Get OS version from mounted image
  - [ ] Detect: Windows 10, Windows 11 (23H2, 24H2)
  - [ ] Return version object
  - [ ] Logging integration
- [ ] **Test-UpdateInstalled.ps1**
  - [ ] Check if KB already installed
  - [ ] Use Get-WindowsPackage
  - [ ] Return boolean
  - [ ] Logging integration

#### Public Functions (WIM)
- [ ] **Get-WimImageInfo.ps1**
  - [ ] Get information about WIM file(s)
  - [ ] Parameters:
    - [ ] -Path (string[]) - supports wildcards
    - [ ] -Index (int) - specific index or all
  - [ ] Return WimImage[] objects
  - [ ] Properties: All DISM info + custom props
  - [ ] Logging integration
- [ ] **Add-UpdateToWim.ps1**
  - [ ] Add single update to mounted WIM
  - [ ] Parameters:
    - [ ] -MountPath (string)
    - [ ] -UpdatePath (string) - .msu or .cab file
    - [ ] -Force (skip installed check)
  - [ ] Check if already installed (skip if present)
  - [ ] Use Add-WindowsPackage
  - [ ] Progress reporting
  - [ ] Error handling
  - [ ] Logging integration
  - [ ] Return result object
- [ ] **Update-WimImage.ps1**
  - [ ] Full provisioning workflow (port from script)
  - [ ] Parameters:
    - [ ] -WimPath (string)
    - [ ] -Index (int)
    - [ ] -UpdatePath (string) - folder with updates
    - [ ] -SxSPath (string) - for .NET 3.5
    - [ ] -EnableNetFx3 (switch)
    - [ ] -OutputPath (string) - save modified WIM
    - [ ] -LogPath (string) - custom log location
  - [ ] Steps:
    1. Initialize logging
    2. Mount WIM
    3. Detect OS version
    4. Apply updates from folder
    5. Special handling for KB5043080 (Win11 24H2)
    6. Enable .NET 3.5 if requested
    7. Dismount and save
    8. Generate summary report
  - [ ] Return ProvisioningJob object
  - [ ] Comprehensive logging throughout
- [ ] **Enable-WimFeature.ps1**
  - [ ] Enable Windows features in mounted WIM
  - [ ] Parameters:
    - [ ] -MountPath (string)
    - [ ] -FeatureName (string[]) - supports multiple
    - [ ] -SxSPath (string) - source files
  - [ ] Common features: NetFx3, etc.
  - [ ] Use Enable-WindowsOptionalFeature
  - [ ] Logging integration
  - [ ] Return result

---

### Phase 3: Parallel Processing
**Goal**: Enable concurrent WIM provisioning with proper resource management

#### Public Function
- [ ] **Start-ParallelProvisioning.ps1**
  - [ ] Process multiple WIMs concurrently
  - [ ] Parameters:
    - [ ] -WimFiles (WimImage[] or FileInfo[])
    - [ ] -UpdatePath (string)
    - [ ] -SxSPath (string)
    - [ ] -ThrottleLimit (int) - default 10, max 20
    - [ ] -EnableNetFx3 (switch)
    - [ ] -IndexSelection (hashtable) - WIM name -> index
    - [ ] -LogPath (string) - base log directory
  - [ ] Implementation:
    - [ ] Create unique mount points per WIM
    - [ ] Create separate log file per WIM
    - [ ] Use ForEach-Object -Parallel
    - [ ] Pass variables with $using:
    - [ ] Collect results from all jobs
    - [ ] Aggregate errors
    - [ ] Overall progress reporting
    - [ ] Merge logs or keep separate
  - [ ] Return ProvisioningJob[] objects

#### Private Functions
- [ ] **New-UniqueMountPath.ps1**
  - [ ] Generate unique mount directory
  - [ ] Pattern: C:\Mount\WimName-GUID
  - [ ] Ensure no conflicts
  - [ ] Auto-cleanup old mounts
  - [ ] Logging integration
- [ ] **Invoke-ParallelProgress.ps1**
  - [ ] Track progress across parallel jobs
  - [ ] Update parent progress bar
  - [ ] Aggregate timing information
  - [ ] Aggregate log information

#### Considerations
- [ ] Document DISM limitation (max 20 concurrent mounts)
- [ ] Resource monitoring (disk space, memory)
- [ ] Error isolation (one failure doesn't stop others)
- [ ] Cleanup on failure (unmount orphaned images)
- [ ] Thread-safe logging critical for parallel operations
- [ ] Each parallel job writes to its own log file

---

### Phase 4: WPF GUI
**Goal**: Create user-friendly graphical interface for non-CLI users

#### XAML Design
- [ ] **MainWindow.xaml**
  - [ ] Main window layout (Grid-based)
  - [ ] Sections:
    - [ ] WIM Selection
      - [ ] File picker (single/multiple)
      - [ ] Selected WIMs list with details
      - [ ] Index selection per WIM
    - [ ] Update Configuration
      - [ ] Catalog search interface
      - [ ] Or: Browse local update folder
      - [ ] SxS folder selection
      - [ ] Options: Enable .NET 3.5, Include Preview, etc.
    - [ ] Provisioning Control
      - [ ] Start/Stop/Pause buttons
      - [ ] ThrottleLimit slider
      - [ ] Output path selection
    - [ ] Progress Display
      - [ ] Overall progress bar
      - [ ] Per-WIM progress (list view)
      - [ ] Current operation text
    - [ ] Log Viewer (NEW)
      - [ ] Real-time log display (scrollable)
      - [ ] Filter by log level (All/Debug/Info/Warning/Error)
      - [ ] Color-coded log entries
      - [ ] Auto-scroll toggle
      - [ ] Save logs button
      - [ ] Clear logs button
  - [ ] Menu bar:
    - [ ] File: Open Config, Save Config, Exit
    - [ ] Tools: Download Updates, Clear Logs, Export Logs
    - [ ] View: Show/Hide Log Viewer
    - [ ] Help: About, Documentation
- [ ] **Styles.xaml**
  - [ ] Modern flat design
  - [ ] Color scheme (blue/white/grey)
  - [ ] Button styles
  - [ ] Progress bar styles
  - [ ] List view templates
  - [ ] Log viewer styles (color-coded entries)

#### PowerShell Code-Behind
- [ ] **MainWindow.ps1**
  - [ ] Load XAML and create window
  - [ ] Event handlers:
    - [ ] btnBrowseWim_Click - File picker
    - [ ] btnRemoveWim_Click - Remove from list
    - [ ] btnBrowseUpdates_Click - Folder picker
    - [ ] btnSearchCatalog_Click - Open catalog search
    - [ ] btnStartProvisioning_Click - Start processing
    - [ ] btnStop_Click - Cancel operations
    - [ ] btnSaveLogs_Click - Export logs
    - [ ] btnClearLogs_Click - Clear log viewer
    - [ ] cmbLogLevel_Changed - Filter logs by level
    - [ ] Window_Loaded - Initialize UI
    - [ ] Window_Closing - Cleanup
  - [ ] Background processing:
    - [ ] Use runspaces for non-blocking operations
    - [ ] Update UI from background threads (Dispatcher)
    - [ ] Real-time log updates to GUI
    - [ ] Progress updates
  - [ ] Data binding:
    - [ ] ObservableCollection for WIM list
    - [ ] ObservableCollection for log entries
    - [ ] Property change notifications
    - [ ] Two-way binding for options
  - [ ] Log integration:
    - [ ] Subscribe to log events
    - [ ] Update log viewer in real-time
    - [ ] Color-code entries by level
    - [ ] Auto-scroll implementation

#### Public Function
- [ ] **Show-ProvisioningGUI.ps1**
  - [ ] Entry point to launch GUI
  - [ ] Load XAML files
  - [ ] Initialize window
  - [ ] Set up log viewer
  - [ ] Show modally or non-modal
  - [ ] Return results when closed

---

### Phase 5: Documentation & Polish
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
# Write-ProvisioningLog.ps1
$script:LogMutex = New-Object System.Threading.Mutex($false, "PSWimToolkit_LogMutex")

function Write-ProvisioningLog {
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
    Write-ProvisioningLog -Message "Detected Windows 11 24H2, checking for KB5043080" -Type Info

    $KB5043080 = $Updates | Where-Object { $_.Name -like "*KB5043080*" }
    if ($KB5043080 -and -not (Test-UpdateInstalled -MountPath $MountPath -KB "KB5043080")) {
        Write-ProvisioningLog -Message "Installing KB5043080 first (required for 24H2)" -Type Stage
        Add-WindowsPackage -Path $MountPath -PackagePath $KB5043080.FullName
        Write-ProvisioningLog -Message "KB5043080 installed successfully" -Type Success
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
Write-ProvisioningLog -Message "Enabling .NET Framework 3.5" -Type Stage
$SxSPath = switch ($OSVersion) {
    { $_ -lt "10.0.22000.0" } { $SxSPaths.Win10_22H2 }
    { $_ -ge "10.0.26100.0" } { $SxSPaths.Win11_24H2 }
    default { $SxSPaths.Win11_23H2 }
}
Write-ProvisioningLog -Message "Using SxS source: $SxSPath" -Type Info
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
| Phase 5: Docs | 3-5 days | Phase 1-4 |
| **Total** | **23-34 days** | |

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
- [ ] All phases 0-5 complete
- [ ] WPF GUI functional with log viewer
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

**Last Updated**: 2025-10-07
**Status**: Phase 0 In Progress
**Next Milestone**: Complete Phase 0 Setup + Logging Implementation
