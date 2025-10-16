# PSWimToolkit Refactor Plan

```powershell
#requires -Version 7.4
```

## Phase 0 - Discovery
- **Goal**: Capture the current PSWimToolkit surface and hotspots before reshaping the module.
- **Actions**:
  - [ ] Inventory public, private, and GUI functions with metadata (paths, exported status, dependencies) and store the results in `output/analysis/ModuleMap.json` for later validation.
  - [ ] Measure script sizes and cyclomatic complexity in `source/GUI` and `source/Private`, highlighting `source/GUI/MainWindow.ps1` as the primary refactoring target.
  - [ ] Document cross-folder dependencies, especially GUI calls into `source/Private/Updates` and `source/Private/WimImage`, to guide responsibility boundaries.
  - [ ] Record current naming deviations from approved PowerShell verb-noun patterns to drive consistent renaming later.
- **Deliverables**:
  - [ ] Dependency report describing per-function imports, exports, and script length.
  - [ ] Summary notes outlining the highest-cost files and the most tightly coupled areas to be addressed in later phases.
  - [ ] Naming convention gap analysis capturing non-compliant function, file, and folder names.

## Phase 1 - Directory Structure
- **Goal**: Reshape the module tree into clear, responsibility-focused folders that reflect the existing script responsibilities while keeping a single PSWimToolkit module.
- **Actions**:
  - [ ] Map each script in `source/Private` to a responsibility based on its current namespace (Bootstrap, Logging, Cache, Catalog, Updates, Utility, WimImage) and design an updated folder layout that keeps related scripts together.
  - [ ] Convert `source/PSWimToolkit.psm1` into a straightforward loader that dot-sources scripts from the revised folders (e.g. `Core` for bootstrap/logging, `DataCache` for cache helpers, `Catalog` for catalog operations, `MSUpdates` for update orchestration, `WimManagement` for image work, `Common` for shared utilities, and `Private\GUI` for GUI logic).
  - [ ] Rename or relocate existing folders to match the approved layout and move scripts accordingly, keeping XAML assets under `source/GUI` while moving all GUI PowerShell scripts into `source/Private/GUI`.
  - [ ] Introduce `Common` (shared helpers) and `Core` (configuration, logging, bootstrap) folders to eliminate ambiguous `Private` groupings while preserving current functionality.
  - [ ] Keep exported functions (e.g. `Start-PSWimToolkit`) in `source/Public`, but relocate their internal dependencies into the new folder layout.
  - [ ] Introduce a contributor-facing folder map in `README.md` that explains the simplified structure and responsibility boundaries.
- **Deliverables**:
  - [ ] Refactored `source/PSWimToolkit.psm1` that sequentially loads scripts by folder while remaining easy to follow.
  - [ ] Updated folder tree showing the new responsibility-focused layout derived from the current `Private` subdirectories (e.g. `Core`, `Common`, `DataCache`, `Catalog`, `MSUpdates`, `WimManagement`, `Private\GUI`, `GUI`, `Classes`, `Public`).
  - [ ] Updated `source/PSWimToolkit.psd1` to reflect new file paths if required.
  - [ ] Updated documentation outlining the streamlined directory structure and loading order.

## Phase 2 - GUI Decomposition
- **Goal**: Split `Show-PSWimToolkitMainWindow` into composable pieces that isolate UI wiring from business logic while keeping GUI PowerShell scripts under `source/Private/GUI` and retaining XAML in `source/GUI`.
- **Actions**:
  - [ ] Extract XAML loading and resource resolution into `Initialize-PSToolkitWindow` (handles Add-Type, XAML parsing, and style injection) stored in `source/Private/GUI/Initialization/Initialize-PSToolkitWindow.ps1`, leaving `source/GUI` for XAML/styles only.
  - [ ] Introduce a `MainWindowViewModel` class in `source/Classes/MainWindowViewModel.ps1` that captures observable state, command bindings, and validation helpers.
  - [ ] Move event hookup blocks into `Register-PSToolkitMainWindowEvents` under `source/Private/GUI/Controllers`, keeping each handler in its own function file grouped by feature (imaging, updates, catalogs).
  - [ ] Provide command objects in `source/Private/GUI/Commands/*.ps1` that wrap long-running operations with centralized progress reporting and error handling, reducing inline scriptblock duplication.
  - [ ] Update `Show-PSWimToolkitMainWindow` to orchestrate initialization, view model creation, event registration, and graceful teardown in fewer than 200 lines.
  - [ ] Keep each GUI function below 150 lines and document purpose with concise comment-based help.
- **Deliverables**:
  - [ ] Lean `Show-PSWimToolkitMainWindow` coordinating initialization, view model binding, and shutdown.
  - [ ] Dedicated initialization, controller, and command scripts under `source/Private/GUI` with clear naming conventions that mirror the XAML structure.
  - [ ] `MainWindowViewModel` class exposing strongly-typed properties for binding and command execution.
  - [ ] Guidance document (`source/Private/GUI/README.md`) describing folder responsibilities and naming expectations while pointing to XAML assets under `source/GUI`.

## Phase 3 - Service Layer
- **Goal**: Isolate update, catalog, cache, and image services behind cohesive APIs consumable by both GUI and future automation.
- **Actions**:
  - [ ] Merge related private scripts into the new responsibility folders (`Core`, `Common`, `DataCache`, `Catalog`, `MSUpdates`, `WimManagement`) with explicit public and private surfaces.
  - [ ] Replace direct script invocation inside the GUI with service interfaces returned from factory functions stored in the new folders (e.g. `Get-WimCatalogService`, `Get-ImageProvisioningService`).
  - [ ] Centralize concurrency helpers into a utilities module that exposes `Start-ToolkitParallelMonitor` with consistent cancellation and throttling options.
  - [ ] Ensure services accept dependency injection for logging, file paths, and cancellation tokens so GUI code passes delegates instead of using global state.
  - [ ] Verify every function has a single, focused responsibility and relocate multi-purpose scripts into smaller, dedicated files.
- **Deliverables**:
  - [ ] Service factory functions returning `[PSCustomObject]` instances with methods such as `Invoke`, `Query`, and `Save`.
  - [ ] GUI service calls rewritten to use the new service interfaces instead of dot-sourcing individual scripts.
  - [ ] Updated comment-based help describing each service and its available operations.
  - [ ] Service layer architecture notes capturing module boundaries and dependency flow.

## Phase 4 - Function Renames
- **Goal**: Align function names with PowerShell verb-noun guidance and the new module boundaries.
- **Renames**:
  - [ ] `Resolve-ToolkitUpdatePath` -> `Resolve-WimUpdatePath`
  - [ ] `Get-ToolkitUpdatePath` -> `Get-WimUpdatePath`
  - [ ] `ConvertTo-ToolkitPathSegment` -> `ConvertTo-SafePathSegment`
  - [ ] `ConvertTo-ToolkitSizeInMb` -> `ConvertTo-MegabyteSize`
  - [ ] `Invoke-ParallelProgress` -> `Start-ToolkitParallelMonitor`
  - [ ] `Start-ParallelProvisioning` -> `Invoke-WimProvisioningBatch`
  - [ ] `Get-ToolkitCatalogData` -> `Get-WimCatalogData`
  - [ ] `Get-ToolkitCatalogFacet` -> `Get-WimCatalogFacet`
  - [ ] `Invoke-ParseDate` -> `ConvertTo-DateTime`
  - [ ] `Write-ToolkitLog` -> `Write-ToolkitLogEntry`
- **Actions**:
  - [ ] Apply renames within respective files and update all invocations across `source/Private`, `source/GUI`, and `source/Public`.
  - [ ] Adjust logging source identifiers to match the new function names for consistent telemetry.
  - [ ] Run script analyzer naming rules to confirm compliance with approved verbs and resolve remaining warnings.
  - [ ] Adopt consistent file naming to match the primary function defined in each script.
- **Deliverables**:
  - [ ] Updated function names across the module with consistent noun phrases and logging identifiers.
  - [ ] Revised manifest aliases if backward compatibility requires temporary alias creation.
  - [ ] Style guide snippet summarizing the enforced naming conventions for functions, files, and folders.

## Phase 5 - User Experience
- **Goal**: Polish GUI behaviors and scripting ergonomics so future maintenance stays manageable.
- **Actions**:
  - [ ] Implement centralized error and status messaging via a `NotificationService` injected into GUI commands.
  - [ ] Abstract repeated dialog definitions (AutoDetect, WimDetails, Catalog) into reusable window factories stored under `source/GUI/Dialogs`.
  - [ ] Document the GUI command workflow in `README.md` and comment-based help, outlining how services, view models, and controllers interact.
  - [ ] Streamline user-facing scripts so each exported function stays concise, readable, and documented with examples.
- **Deliverables**:
  - [ ] `NotificationService` with methods `Show-Info`, `Show-Warning`, and `Show-Error` consumed by GUI controllers.
  - [ ] Shared dialog factory functions reducing duplicated XAML loading patterns.
  - [ ] Updated documentation explaining the modular GUI architecture for contributors.
  - [ ] Reference guide for contributors covering usability standards and simplicity guidelines.
