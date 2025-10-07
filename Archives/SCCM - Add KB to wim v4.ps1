#region Script Information
<#
.SYNOPSIS
    Script to update Windows Image files with latest updates and .NET Framework
.DESCRIPTION
    Updates Windows 10/11 WIM files with latest updates and enables .NET Framework 3.5
.NOTES
    Name:        Add KB to Wim
    Author:      Mickaël CHAVE
    Created:     2025-02-12
    Version:     3.1.0
#>
#endregion

#region Path Definitions
# Modification de la déclaration des chemins pour PS 5.1
$script:Paths = @{
    "Base" = "C:\ImageBuilder"
    "WIM" = @{
        "Root" = "C:\ImageBuilder\WIM"
        "Mount" = "C:\ImageBuilder\WIM\Mount"
        "Working" = "C:\ImageBuilder\WIM\Wim"
    }
    "Masters" = "C:\ImageBuilder\Masters"
    "Updates" = @{
        "Win10" = "C:\ImageBuilder\WIM\Updates\Windows10"
        "Win11" = "C:\ImageBuilder\WIM\Updates\Windows11"
        "Win11_24h2" = "C:\ImageBuilder\WIM\Updates\Windows11_24h2"
    }
    "SxS" = @{
        "Win10_22H2" = "C:\ImageBuilder\WIM\SxS\Windows 10 22H2"
        "Win11_23H2" = "C:\ImageBuilder\WIM\SxS\Windows 11 23H2"
        "Win11_24H2" = "C:\ImageBuilder\WIM\SxS\Windows 11 24H2"
    }
    "Logs" = "C:\ImageBuilder\WIM\Logs"
}

# Modification de la structure Results pour PS 5.1
$script:Results = @{
    "ProcessedFiles" = @()
    "Updates" = @{
        "Windows10" = @{} 
        "Windows11" = @{} 
        "Windows11_24h2" = @{} 
    }
    "Statistics" = @{
        "TotalAttempted" = 0
        "TotalSuccess" = 0
        "TotalFailed" = 0
    }
    "TimingInfo" = @{
        "StartTime" = $null
        "EndTime" = $null
        "WimTimings" = @{}
    }
}

Clear-Host
#endregion

#region Core Functions
# Modification de la fonction Log-Write pour PS 5.1
function Log-Write {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Stage')]
        [string]$Type = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        'Info'    { '[INFO]   ' }
        'Warning' { '[WARN]   ' }
        'Error'   { '[ERROR]  ' }
        'Success' { '[SUCCESS]' }
        'Stage'   { '[STAGE]  ' }
        default   { '[INFO]   ' }
    }

    $color = switch ($Type) {
        'Info'    { 'White' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
        'Stage'   { 'Cyan' }
        default   { 'White' }
    }

    Write-Host ("`[$timestamp`] $prefix $Message") -ForegroundColor $color
}

# Function to verify if all prerequisites are met before script execution
Function Test-Prerequisites {
    $requirements = @{
        "Admin Rights" = { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
        "Disk Space" = { (Get-PSDrive -Name ($Paths.Base[0])).Free -gt 10GB }
    }

    $failed = @()
    foreach ($req in $requirements.GetEnumerator()) {
        if (-not (& $req.Value)) {
            $failed += $req.Key
        }
    }
    return $failed
}

# Function to perform cleanup operations, especially for mounted images
Function Invoke-Cleanup {
    param([string]$mountDir)
    Log-Write -Message "Starting cleanup procedure..." -Type Stage
    
    try {
        $mountedImages = Get-WindowsImage -Mounted
        if ($mountedImages.ImagePath -match $mountDir) {
            Log-Write -Message "Found mounted image, attempting to unmount..." -Type Stage
            Dismount-WindowsImage -Path $mountDir -Discard
            Log-Write -Message "Successfully unmounted image." -Type Success
        }
    }
    catch {
        Log-Write -Message "Failed to perform cleanup: $($_.Exception.Message)" -Type Error
    }
}

# Function to write menu without logging
function Write-Menu {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'White'
    )
    Write-Host $Text -ForegroundColor $Color
}

# New function for menu separators
function Write-MenuSeparator {
    param([string]$Title = "")
    Write-Menu ""
    Write-Menu "============================================================"
    if ($Title) {
        Write-Menu "  $Title"
        Write-Menu "============================================================"
    }
    Write-Menu ""
}

# Simplified Initialize-Directories function
function Initialize-Directories {
    foreach ($path in $Paths.GetEnumerator()) {
        if ($path.Value -is [string]) {
            if (!(Test-Path -Path $path.Value)) {
                New-Item -Path $path.Value -ItemType Directory -Force | Out-Null
            }
        }
        elseif ($path.Value -is [hashtable]) {
            foreach ($subPath in $path.Value.Values) {
                if (!(Test-Path -Path $subPath)) {
                    New-Item -Path $subPath -ItemType Directory -Force | Out-Null
                }
            }
        }
    }
}
#endregion

#region WIM Management Functions
# Function to mount a Windows Image file with specified index
Function Mount-WimFile {
    Param (
        [string]$wimPath,
        [string]$mountDir,
        [int]$index = 1
    )
    Log-Write -Message "Mounting $wimPath (Index: $index)" -Type Stage
    try {
        Mount-WindowsImage -ImagePath $wimPath -Index $index -Path $mountDir
        Log-Write -Message "$wimPath mounted successfully." -Type Success
    }
    catch {
        Log-Write -Message "Error occurred while mounting: $($_.Exception.Message)" -Type Error
    }
}

# Function to safely unmount a Windows Image file
Function Dismount-WimFile {
    Param ([string]$mountDir)
    Log-Write -Message "Unmounting $mountDir" -Type Stage
    try {
        Dismount-WindowsImage -Path $mountDir -Save
        Log-Write -Message "$mountDir unmounted successfully." -Type Success
    }
    catch {
        Log-Write -Message "Error occurred while unmounting: $($_.Exception.Message)" -Type Error
    }
}

# Function to copy WIM files from source to destination folder
Function Copy-WimFiles {
    Param ([string]$sourceFolder, [string]$destinationFolder, [string[]]$versions)
    try {
        Log-Write -Message "Removing all .wim files in $destinationFolder" -Type Stage
        Remove-Item -Path $destinationFolder\* -Recurse -Force
        Log-Write -Message "All .wim files removed from $destinationFolder" -Type Success

        foreach ($ver in $versions) {
            Log-Write -Message "Copying .wim files from $sourceFolder to $destinationFolder" -Type Stage
            $files = Get-ChildItem -Path $sourceFolder -Recurse -File -Include "*$ver*"
            foreach ($file in $files) {
                Copy-Item -Path $file.FullName -Destination $destinationFolder -Force
                Log-Write -Message "$file copied to $destinationFolder" -Type Success
            }
        }
        Log-Write -Message ".wim files copied successfully." -Type Success
    }
    catch {
        Log-Write -Message "Error occurred while copying .wim files : $($_.Exception.Message)" -Type Error
    }
}

# Function to let user select which index of a WIM file to process
Function Select-WimIndex {
    param (
        [System.IO.FileInfo]$wimFile
    )
    
    $indices = Get-WindowsImage -ImagePath $wimFile.FullName
    
    Log-Write -Message "Available indices for $($wimFile.Name):" -Type Info
    Log-Write -Message "----------------------------------------" -Type Info
    foreach ($idx in $indices) {
        Log-Write -Message "Index: $($idx.ImageIndex)" -Type Info
        Log-Write -Message "Name: $($idx.ImageName)" -Type Info
        Log-Write -Message "Description: $($idx.ImageDescription)" -Type Info
        Log-Write -Message "----------------------------------------" -Type Info
    }
    
    $selectedIndex = Read-Host "Select index number (default: 1)"
    if ([string]::IsNullOrWhiteSpace($selectedIndex)) {
        return 1
    }
    
    if ($selectedIndex -match '^\d+$' -and [int]$selectedIndex -ge 1 -and [int]$selectedIndex -le $indices.Count) {
        return [int]$selectedIndex
    }
    
    Log-Write -Message "Invalid index, using default (1)" -Type Warning
    return 1
}

# New function to collect WIM indices
Function Get-AllWimIndices {
    param (
        [System.IO.FileInfo[]]$wimFiles
    )
    
    $indexSelections = @{}
    
    Log-Write -Message "Selecting indices for all WIM files..." -Type Stage
    foreach ($wimFile in $wimFiles) {
        Clear-Host
        Write-MenuSeparator "Index Selection for $($wimFile.Name)"
        
        $indices = Get-WindowsImage -ImagePath $wimFile.FullName
        foreach ($idx in $indices) {
            Write-Menu ""
            Write-Menu " Index: $($idx.ImageIndex)"
            Write-Menu " Name: $($idx.ImageName)"
            Write-Menu " Description: $($idx.ImageDescription)"
            Write-Menu " ----------------------------------------"
        }
        
        Write-Menu ""
        $selectedIndex = Read-Host "Select index number for $($wimFile.Name) (default: 1)"
        if ([string]::IsNullOrWhiteSpace($selectedIndex)) {
            $selectedIndex = 1
        }
        
        if ($selectedIndex -match '^\d+$' -and [int]$selectedIndex -ge 1 -and [int]$selectedIndex -le $indices.Count) {
            $indexSelections[$wimFile.Name] = [int]$selectedIndex
        } else {
            Write-Menu "`nInvalid index, using default (1)" -Color Yellow
            $indexSelections[$wimFile.Name] = 1
            Start-Sleep -Seconds 5  # Pause to read the error message
        }
        
        Clear-Host  # Clear the screen after selection
    }
    
    return $indexSelections
}
#endregion

#region Update Management Functions
# Function to display progress bars for both overall progress and update installation
# Modification de la fonction Show-Progress pour PS 5.1
function Show-Progress {
    param (
        [int]$Current,
        [int]$Total,
        [string]$Status,
        [switch]$IsUpdate,
        [int]$ParentPercentComplete
    )

    $percentComplete = [math]::Round(($Current / $Total) * 100, 2)
    if ($IsUpdate.IsPresent) {
        Write-Progress -Id 1 -Activity "Processing Updates" -Status $Status -PercentComplete $percentComplete
    } else {
        Write-Progress -Activity "Processing WIM Files" -Status $Status -PercentComplete $ParentPercentComplete
    }
}

# Simplified Add-Updates function
Function Add-Updates {
    Param (
        [string]$wimName,
        [string]$mountDir,
        [System.IO.FileInfo[]]$updates,
        [string]$updatePath,
        [int]$parentProgress
    )
    
    $results = @{
        Total = $updates.Count
        Success = 0
        Failed = @()
    }

    # Update global statistics for total attempted
    $script:Results.Statistics.TotalAttempted += $updates.Count

    # Special handling for Windows 11 24H2
    if ($updatePath -eq $Paths.Updates.Win11_24h2) {
        $priorityUpdate = $updates | Where-Object { $_.Name -like "*kb5043080*" }
        if ($priorityUpdate) {
            Log-Write -Message "Found KB5043080, checking if already installed..." -Type Info
            
            $kb5043080Installed = Get-WindowsPackage -Path $mountDir | Where-Object { $_.PackageName -like "*KB5043080*" }
            
            if ($kb5043080Installed) {
                Log-Write -Message "KB5043080 is already installed, skipping..." -Type Info
                $results.Success++
                $script:Results.Statistics.TotalSuccess++
            } else {
                Log-Write -Message "KB5043080 not found, installing it first..." -Type Info
                Show-Progress -Current 1 -Total $results.Total -Status "Installing KB5043080" -IsUpdate -ParentPercentComplete $parentProgress
                
                try {
                    # Utiliser le chemin complet du fichier
                    $updateFullPath = $priorityUpdate.FullName
                    Add-WindowsPackage -Path $mountDir -PackagePath $updateFullPath
                    Log-Write -Message "KB5043080 installed successfully." -Type Success
                    $results.Success++
                    $script:Results.Statistics.TotalSuccess++
                }
                catch {
                    Log-Write -Message "Error installing KB5043080: $($_.Exception.Message)" -Type Error
                    $results.Failed += $priorityUpdate.Name
                    $script:Results.Statistics.TotalFailed++
                }
            }
            
            $updates = $updates | Where-Object { $_ -ne $priorityUpdate }
        }
    }

    # Process remaining updates
    ForEach ($update in $updates) {
        Show-Progress -Current ($results.Success + $results.Failed.Count + 1) -Total $results.Total -Status "Checking $($update.Name)" -IsUpdate -ParentPercentComplete $parentProgress
        
        $updateInfo = Get-WindowsPackage -Path $mountDir | Where-Object { $_.PackageName -like "*$($update.BaseName)*" }
        if ($updateInfo) {
            Log-Write -Message "$($update.Name) is already installed, skipping..." -Type Info
            continue
        }

        Show-Progress -Current ($results.Success + $results.Failed.Count + 1) -Total $results.Total -Status "Adding $($update.Name)" -IsUpdate -ParentPercentComplete $parentProgress
        Log-Write -Message "Adding $update to $wimName..." -Type Info
        try {
            # Utiliser le chemin complet du fichier
            $updateFullPath = $update.FullName
            Add-WindowsPackage -Path $mountDir -PackagePath $updateFullPath
            Log-Write -Message "$update added to $wimName." -Type Success
            $results.Success++
            $script:Results.Statistics.TotalSuccess++
        }
        catch {
            Log-Write -Message "Error occurred while adding $update to $wimName : $($_.Exception.Message)" -Type Error
            $results.Failed += $update.Name
            $script:Results.Statistics.TotalFailed++
        }
    }
    Write-Progress -Id 1 -Activity "Processing Updates" -Completed
    return $results
}

# Simplified Invoke-WimFileProcessing function
Function Invoke-WimFileProcessing {
    Param (
        [System.IO.FileInfo]$wimFile,
        [int]$parentProgress = 0,
        [int]$imageIndex = 1
    )
    Log-Write -Message "Processing $wimFile (Index: $imageIndex)" -Type Stage
    $wimName = $wimFile.Name
    $wimPath = $wimFile.FullName

    $wimInfo = Get-WindowsImage -ImagePath $wimPath -Index $imageIndex
    $wimVersion = [version]$wimInfo.Version

    Mount-WimFile -wimPath $wimPath -mountDir $Paths.WIM.Mount -index $imageIndex

    # Determine appropriate update path and store results
    $updateInfo = if ($wimVersion -lt "10.0.22000.0") {
        @{
            Path = $Paths.Updates.Win10
            Updates = Get-ChildItem -Path $Paths.Updates.Win10 -Filter "*.msu"
            ResultKey = 'Windows10'
        }
    }
    elseif ($wimVersion -ge "10.0.26100.0") {
        @{
            Path = $Paths.Updates.Win11_24h2
            Updates = Get-ChildItem -Path $Paths.Updates.Win11_24h2 -Filter "*.msu"
            ResultKey = 'Windows11_24h2'
        }
    }
    else {
        @{
            Path = $Paths.Updates.Win11
            Updates = Get-ChildItem -Path $Paths.Updates.Win11 -Filter "*.msu"
            ResultKey = 'Windows11'
        }
    }

    $Results.Updates[$updateInfo.ResultKey] = Add-Updates -wimName $wimFile.Name `
                                                         -mountDir $Paths.WIM.Mount `
                                                         -updates $updateInfo.Updates `
                                                         -updatePath $updateInfo.Path `
                                                         -parentProgress $parentProgress

    Log-Write -Message "Enabling .Net 3.5 for $wimName..." -Type Stage
    try {
        if ($wimVersion -lt "10.0.22000.0") {
            if (Test-Path -Path $Paths.SxS.Win10_22H2) {
                Enable-WindowsOptionalFeature -Path $Paths.WIM.Mount -FeatureName "NetFx3" -All -Source $Paths.SxS.Win10_22H2 -LimitAccess
                Log-Write -Message ".Net 3.5 enabled for $wimName using Windows 10 22H2 SxS." -Type Success
            }
            else {
                throw "The SxS folder for Windows 10 22H2 does not exist."
            }
        }
        elseif ($wimVersion -ge "10.0.22621.0" -and $wimVersion -lt "10.0.26100.0") {
            if (Test-Path -Path $Paths.SxS.Win11_23H2) {
                Enable-WindowsOptionalFeature -Path $Paths.WIM.Mount -FeatureName "NetFx3" -All -Source $Paths.SxS.Win11_23H2 -LimitAccess
                Log-Write -Message ".Net 3.5 enabled for $wimName using Windows 11 23H2 SxS." -Type Success
            }
            else {
                throw "The SxS folder for Windows 11 23H2 does not exist."
            }
        }
        elseif ($wimVersion -ge "10.0.26100.0") {
            if (Test-Path -Path $Paths.SxS.Win11_24H2) {
                Enable-WindowsOptionalFeature -Path $Paths.WIM.Mount -FeatureName "NetFx3" -All -Source $Paths.SxS.Win11_24H2 -LimitAccess
                Log-Write -Message ".Net 3.5 enabled for $wimName using Windows 11 24H2 SxS." -Type Success
            }
            else {
                throw "The SxS folder for Windows 11 24H2 does not exist."
            }
        }
        else {
            throw "The .wim file version is not supported for enabling .Net 3.5."
        }
    }
    catch {
        Log-Write -Message "Error occurred while enabling .Net 3.5 for $wimName : $($_.Exception.Message)" -Type Error
    }

    Dismount-WimFile -mountDir $Paths.WIM.Mount
}
#endregion

#region Main Script Execution
try {
    # Verify administrator privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log-Write -Message "This script requires administrator privileges. Please restart as administrator." -Type Error
        throw "This script requires administrator privileges. Please restart as administrator."
    }

    # Initialize environment
    Initialize-Directories

    # Setup logging
    $logFile = Join-Path $Paths.Logs "Add-KB-to-wim_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    try {
        Start-Transcript -Path $logFile -Append
    }
    catch {
        Log-Write -Message "Could not start transcript: $($_.Exception.Message)" -Type Warning
    }

    # Check prerequisites and initialize cleanup
    $failedRequirements = Test-Prerequisites
    if ($failedRequirements.Count -gt 0) {
        Log-Write -Message "Missing prerequisites: $($failedRequirements -join ', ')" -Type Error
        throw "Missing prerequisites: $($failedRequirements -join ', ')"
    }

    $cleanupScript = {
        Invoke-Cleanup -mountDir $Paths.WIM.Mount
    }
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanupScript

    Log-Write -Message "Script started." -Type Stage

    $wimFiles = Get-ChildItem -Path $Paths.Masters -Filter "*.wim"

    # Initialize start time for global timing
    $Results.TimingInfo.StartTime = Get-Date

    # Main menu and processing logic
    if ((Test-Path $Paths.WIM.Working) -and (Test-Path $Paths.Masters)) {
        Clear-Host
        Write-MenuSeparator "Windows Image Update Manager"
        Write-Menu "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-MenuSeparator
        
        Write-Menu " Available Actions:"
        Write-Menu " ----------------"
        Write-Menu " 1  - Update ALL WIM files"
        Write-Menu " M  - Update Multiple WIM files (custom selection)"
        Write-MenuSeparator
        
        Write-Menu " Available WIM Files:"
        Write-Menu " ------------------"
        for ($i = 0; $i -lt $wimFiles.Length; $i++) {
            $wimSize = [math]::Round(($wimFiles[$i].Length / 1GB), 2)
            Write-Menu ""
            Write-Menu " $($i + 2)  - $($wimFiles[$i].Name)"
            Write-Menu "        Size: $wimSize GB"
        }
        
        Write-MenuSeparator
        Write-Menu " Press 'Q' to quit"
        Write-MenuSeparator

        $selection = Read-Host "Enter your selection"
        Log-Write -Message "" -Type Info

        switch ($selection) {
            "1" {
                Clear-Host
                Copy-WimFiles -sourceFolder $Paths.Masters -destinationFolder $Paths.WIM.Working -versions $wimFiles.Name

                $wimFiles = Get-ChildItem -Path $Paths.WIM.Working -Filter "*.wim"
                $totalWims = $wimFiles.Count
                
                # Collect all indices first
                $indexSelections = Get-AllWimIndices -wimFiles $wimFiles
                
                # Then process each WIM
                $currentWim = 0
                ForEach ($wimFile in $wimFiles) {
                    $wimStartTime = Get-Date
                    $currentWim++
                    $parentProgress = [math]::Round(($currentWim / $totalWims) * 100, 2)
                    Show-Progress -Current $currentWim -Total $totalWims -Status "Processing $($wimFile.Name)" -ParentPercentComplete $parentProgress

                    $selectedIndex = $indexSelections[$wimFile.Name]
                    Invoke-WimFileProcessing -wimFile $wimFile -parentProgress $parentProgress -imageIndex $selectedIndex
                    $Results.ProcessedFiles += $wimFile
                    
                    # Record timing for this WIM
                    $Results.TimingInfo.WimTimings[$wimFile.Name] = @{
                        "StartTime" = $wimStartTime
                        "EndTime" = Get-Date
                        "Duration" = (Get-Date) - $wimStartTime
                    }
                }
                Write-Progress -Activity "Processing WIM Files" -Completed
            }
            "M" {
                Clear-Host
                Write-MenuSeparator "Multiple WIM Selection Mode"
                
                Write-Menu " Available WIM Files:"
                Write-Menu " ------------------"
                
                for ($i = 0; $i -lt $wimFiles.Length; $i++) {
                    Write-Menu ""
                    Write-Menu " $($i + 1)  - $($wimFiles[$i].Name)"
                    Write-Menu "        Size: $([math]::Round(($wimFiles[$i].Length / 1GB), 2)) GB"
                }
                
                Write-MenuSeparator
                Write-Menu " Enter the numbers of the WIMs you want to process"
                Write-Menu " (separated by commas, example: 1,3,5)"
                Write-MenuSeparator

                $selectedIndices = Read-Host "Selection"
                Clear-Host
                
                try {
                    $selectedIndices = $selectedIndices.Split(',').Trim() | 
                                     Where-Object { $_ -match '^\d+$' } |
                                     ForEach-Object { [int]$_ - 1 } |
                                     Where-Object { $_ -ge 0 -and $_ -lt $wimFiles.Length }
                    
                    if ($selectedIndices.Count -eq 0) {
                        throw "No valid selections made"
                    }

                    $selectedWims = $selectedIndices | ForEach-Object { $wimFiles[$_] }
                    
                    Copy-WimFiles -sourceFolder $Paths.Masters -destinationFolder $Paths.WIM.Working -versions $selectedWims.Name
                    
                    $selectedWimFiles = Get-ChildItem -Path $Paths.WIM.Working -Filter "*.wim"
                    
                    # Collect all indices first
                    $indexSelections = Get-AllWimIndices -wimFiles $selectedWimFiles
                    
                    # Then process each WIM
                    $totalWims = $selectedWimFiles.Count
                    $currentWim = 0
                    ForEach ($wimFile in $selectedWimFiles) {
                        $wimStartTime = Get-Date
                        $currentWim++
                        $parentProgress = [math]::Round(($currentWim / $totalWims) * 100, 2)
                        Show-Progress -Current $currentWim -Total $totalWims -Status "Processing $($wimFile.Name)" -ParentPercentComplete $parentProgress

                        $selectedIndex = $indexSelections[$wimFile.Name]
                        Invoke-WimFileProcessing -wimFile $wimFile -parentProgress $parentProgress -imageIndex $selectedIndex
                        $Results.ProcessedFiles += $wimFile
                        
                        # Record timing for this WIM
                        $Results.TimingInfo.WimTimings[$wimFile.Name] = @{
                            "StartTime" = $wimStartTime
                            "EndTime" = Get-Date
                            "Duration" = (Get-Date) - $wimStartTime
                        }
                    }
                    Write-Progress -Activity "Processing WIM Files" -Completed
                }
                catch {
                    Log-Write -Message "Invalid selection: $($_.Exception.Message)" -Type Error
                    return
                }
            }
            "q"{
                Log-Write -Message "Exiting script..." -Type Info
                Stop-Transcript
                Exit
            }
            default {
                if (($selection -gt 1) -and ($selection -le ($wimFiles.Length + 1))) {
                    Clear-Host
                    $selectedWim = $wimFiles[$selection - 2]
                    Copy-WimFiles -sourceFolder $Paths.Masters -destinationFolder $Paths.WIM.Working -versions @($selectedWim.Name)
            
                    $wimFile = Get-ChildItem -Path $Paths.WIM.Working -Filter $selectedWim.Name
                    
                    # Collect the index for this WIM
                    $indexSelections = Get-AllWimIndices -wimFiles @($wimFile)
                    $selectedIndex = $indexSelections[$wimFile.Name]
                    
                    $wimStartTime = Get-Date
                    Invoke-WimFileProcessing -wimFile $wimFile -imageIndex $selectedIndex
                    $Results.ProcessedFiles += $wimFile
                    
                    # Record timing for this WIM
                    $Results.TimingInfo.WimTimings[$wimFile.Name] = @{
                        "StartTime" = $wimStartTime
                        "EndTime" = Get-Date
                        "Duration" = (Get-Date) - $wimStartTime
                    }
                }
                else {
                    Log-Write -Message "Invalid selection" -Type Warning
                }
            }
        }

        # Record end time for global timing
        $Results.TimingInfo.EndTime = Get-Date

        # Display processing summary
        Clear-Host
        Write-MenuSeparator "PROCESSING SUMMARY"
        Write-Menu " Total WIM files processed: $($Results.ProcessedFiles.Count)"
        Write-Menu " Total Processing Time: $([math]::Round(($Results.TimingInfo.EndTime - $Results.TimingInfo.StartTime).TotalMinutes, 2)) minutes"
        Write-Menu ""
        
        $totalUpdatesAttempted = 0
        $totalUpdatesSuccess = 0
        $totalUpdatesFailed = 0
        
        ForEach ($wimFile in $Results.ProcessedFiles) {
            Write-MenuSeparator
            Write-Menu " WIM File: $($wimFile.Name)"
            Write-Menu " ----------------------------------------"
            $version = [version](Get-WindowsImage -ImagePath $wimFile.FullName -Index 1).Version
            
            # Add timing information
            $timing = $Results.TimingInfo.WimTimings[$wimFile.Name]
            $duration = [math]::Round($timing.Duration.TotalMinutes, 2)
            Write-Menu " Processing Time: $duration minutes"
            Write-Menu " Started: $($timing.StartTime.ToString('HH:mm:ss'))"
            Write-Menu " Finished: $($timing.EndTime.ToString('HH:mm:ss'))"
            Write-Menu ""
            
            if ($version -lt "10.0.22000.0") {
                Write-Menu " Windows Version: Windows 10"
                $updateResults = $Results.Updates.Windows10
            } elseif ($version -ge "10.0.26100.0") {
                Write-Menu " Windows Version: Windows 11 24H2"
                $updateResults = $Results.Updates.Windows11_24h2
            } else {
                Write-Menu " Windows Version: Windows 11"
                $updateResults = $Results.Updates.Windows11
            }
            
            $totalUpdatesAttempted += $updateResults.Total
            $totalUpdatesSuccess += $updateResults.Success
            $totalUpdatesFailed += $updateResults.Failed.Count
            
            Write-Menu ""
            Write-Menu " Updates Summary:"
            Write-Menu "   - Total updates attempted: $($updateResults.Total)"
            Write-Menu "   - Successfully installed: $($updateResults.Success)"
            Write-Menu "   - Failed installations: $($updateResults.Failed.Count)"
            
            if ($updateResults.Failed.Count -gt 0) {
                Write-Menu ""
                Write-Menu " Failed Updates Details:"
                foreach ($failedUpdate in $updateResults.Failed) {
                    Write-Menu "   - $failedUpdate"
                }
            }
        }
        
        Write-MenuSeparator "GLOBAL STATISTICS"
        Write-Menu " Total updates attempted: $($Results.Statistics.TotalAttempted)"
        Write-Menu " Successfully installed: $($Results.Statistics.TotalSuccess)"
        Write-Menu " Failed installations: $($Results.Statistics.TotalFailed)"
        Write-Menu " Success rate: $(if ($Results.Statistics.TotalAttempted -gt 0) { 
            [math]::Round(($Results.Statistics.TotalSuccess/$Results.Statistics.TotalAttempted)*100,2) 
        } else { "0" })%"
        Write-Menu ""
        Write-Menu " Time Statistics:"
        $totalDuration = $Results.TimingInfo.EndTime - $Results.TimingInfo.StartTime
        Write-Menu " Total Processing Duration: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes"
        Write-Menu " Started at: $($Results.TimingInfo.StartTime.ToString('HH:mm:ss'))"
        Write-Menu " Finished at: $($Results.TimingInfo.EndTime.ToString('HH:mm:ss'))"
        Write-MenuSeparator
        Write-Menu ""
        Write-Menu " Script completed."

        Stop-Transcript
    }
    else {
        Log-Write -Message "The working folders do not exist." -Type Error
        Stop-Transcript
        Exit
    }
}
catch {
    # Handle any unexpected errors
    Log-Write -Message "A critical error occurred: $($_.Exception.Message)" -Type Error
    Invoke-Cleanup -mountDir $Paths.WIM.Mount
}
finally {
    # Ensure proper cleanup of resources
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    }
    catch { }

    try {
        Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    }
    catch { }
}
#endregion