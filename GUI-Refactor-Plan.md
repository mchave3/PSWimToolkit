# PSWimToolkit GUI Refactor Plan

## Vision

Reduce the complexity of `source/GUI/MainWindow.ps1` by introducing a modular MVVM-inspired architecture that runs on PowerShell 7.4 or later, improving testability, maintainability, and scalability of the WPF interface.

## Phase 0 – Initial Assessment
- [ ] Inventory all functions and logical blocks currently living in `MainWindow.ps1`.
- [ ] Map dependencies between those functions, XAML controls, and shared resources (`Styles.xaml`, dialog layouts, data sources).
- [ ] Identify functional groupings (GUI helpers, business services, dialog handlers, data models).
- [ ] Document existing pain points (duplication, tight coupling, limited testability).

## Phase 1 – Target Architecture & Folder Layout
- [ ] Define the target folder structure: `GUI/Core`, `GUI/ViewModels`, `GUI/Services`, `GUI/Views`, `GUI/Dialogs`.
- [ ] Specify responsibilities and naming/export conventions for each folder.
- [ ] Update or stage build/import scripts so they accommodate the new layout.
- [ ] Produce a high-level diagram or table showing how the new modules interact.

## Phase 2 – Data Models & Conventions
- [ ] Design typed data models (classes or `[PSCustomObject]`) for WimItem, CatalogEntry, LogEntry, ProvisioningSession, etc.
- [ ] Select and document the serialization format (JSON, PSD1) for configuration and persistence scenarios.
- [ ] Define PowerShell 7.4 coding conventions for the MVVM scripts (comment style, `param` blocks, approved verbs).
- [ ] Prepare reusable snippets/templates to accelerate migration.

## Phase 3 – Business Service Extraction
- [ ] Create dedicated modules for the major business capabilities: WIM import/export, provisioning, logging, configuration management.
- [ ] Incrementally move logic out of `MainWindow.ps1` into these services while preserving public signatures.
- [ ] Introduce a dependency injection mechanism (parameters, modules, classes) so view models can consume the services.
- [ ] Author Pester tests for the extracted services before wiring them back into the UI.

## Phase 4 – View Models & Binding
- [ ] Implement `MainWindowViewModel` with `INotifyPropertyChanged` and observable collections compatible with PowerShell 7.4.
- [ ] Create view models for each dialog (`WimDetailsDialog`, `CatalogDialog`, `AutoDetectDialog`, etc.).
- [ ] Replace inline callbacks with commands (e.g., `RelayCommand` implementations written in PowerShell) exposed by the view models.
- [ ] Update XAML bindings (`DataContext`, `Command`, `ItemsSource`) to target the new view models.

## Phase 5 – Cross-Cutting GUI Services
- [ ] Build a central `DialogService` that loads dialog XAML, attaches view models, and manages modal/non-modal display.
- [ ] Centralize style and resource dictionary loading in `GUI/Core` (modern successor to `Add-SharedGuiStyles`).
- [ ] Provide a GUI-focused `LogService` (buffering, levels, export) consumable from any view model.
- [ ] Introduce a shared `StateStore` or `SessionContext` for global application state (selection, progress, configuration).

## Phase 6 – Asynchronous Operations & Workflows
- [ ] Extract long-running operations (provisioning, log harvesting, downloads) into a `TaskService` that manages runspaces/jobs.
- [ ] Surface events or callbacks from the services so view models can update the UI in real time (status, progress, errors).
- [ ] Standardize error handling and cancellation (`Stop-Provisioning`) through those shared services.
- [ ] Evaluate performance impact and add configurable throttles where needed.

## Phase 7 – Final Simplification & Validation
- [ ] Reduce `MainWindow.ps1` to orchestration only: load XAML, instantiate services, create the `MainWindowViewModel`, show the window.
- [ ] Remove obsolete references and delete functions migrated into other modules.
- [ ] Refresh or add Pester tests for view model commands, key services, and basic integration flows (XAML load + DataContext).
- [ ] Run a full review (code review + manual test pass) and update documentation (README, diagrams, contributor guides).

## Phase 8 – Follow-Up & Future Enhancements
- [ ] Add prospective enhancements to the backlog (localization, accessibility, dark theme, telemetry).
- [ ] Schedule periodic MVVM architecture reviews to prevent logic from leaking back into XAML code-behind.
- [ ] Assess automated UI testing needs and plan investment if critical workflows warrant it.

---

**Last Updated**: _(set once the plan is adopted)_  
**Owner**: _(assign a maintainer)_  
**Next Milestone**: _(define after Phase 0 review)_
