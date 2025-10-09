<#
.SYNOPSIS
    Script de test pour valider les améliorations du logging de PSWimToolkit.

.DESCRIPTION
    Ce script teste toutes les nouvelles fonctionnalités de logging ajoutées au module.

.EXAMPLE
    .\Test-LoggingImprovements.ps1 -Verbose
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Test du Logging PSWimToolkit ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Variables
$logPath = Join-Path -Path $env:ProgramData -ChildPath 'PSWimToolkit\Logs'
$testResults = @()

function Test-LogEntry {
    param(
        [string]$TestName,
        [string]$Pattern,
        [string]$LogFile
    )

    $content = Get-Content -Path $LogFile -Raw -ErrorAction SilentlyContinue
    $found = $content -match $Pattern

    $result = [PSCustomObject]@{
        Test = $TestName
        Pattern = $Pattern
        Success = $found
        Timestamp = Get-Date
    }

    if ($found) {
        Write-Host "  ✅ $TestName" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $TestName" -ForegroundColor Red
    }

    return $result
}

try {
    # Nettoyer les anciens logs pour ce test
    Write-Host "`n📋 Nettoyage des anciens logs de test..." -ForegroundColor Yellow
    if (Test-Path $logPath) {
        Get-ChildItem -Path $logPath -Filter "PSWimToolkit_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-5) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Test 1: Chargement du module
    Write-Host "`n🔄 Test 1: Chargement du module..." -ForegroundColor Cyan

    if (Get-Module -Name PSWimToolkit) {
        Remove-Module PSWimToolkit -Force
    }

    $moduleLoadStart = Get-Date
    Import-Module "$PSScriptRoot\source\PSWimToolkit.psd1" -Force -Verbose
    $moduleLoadEnd = Get-Date

    Write-Host "  Durée de chargement: $([Math]::Round(($moduleLoadEnd - $moduleLoadStart).TotalMilliseconds, 2))ms" -ForegroundColor Gray

    # Attendre que le log soit écrit
    Start-Sleep -Milliseconds 500

    # Trouver le dernier fichier de log
    $latestLog = Get-ChildItem -Path $logPath -Filter "PSWimToolkit_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestLog) {
        Write-Host "  ❌ Aucun fichier de log trouvé" -ForegroundColor Red
        throw "Aucun fichier de log créé"
    }

    Write-Host "  📄 Fichier de log: $($latestLog.Name)" -ForegroundColor Gray

    # Vérifier les logs de chargement
    Write-Host "`n  Vérification des logs de chargement:" -ForegroundColor Yellow
    $testResults += Test-LogEntry -TestName "Log de début de chargement" -Pattern "PSWimToolkit Module Loading" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de chargement des classes" -Pattern "Loading \d+ class file\(s\)" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de chargement des fonctions private" -Pattern "Loading \d+ private function\(s\)" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de chargement des fonctions public" -Pattern "Loading \d+ public function\(s\)" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de fonctions exportées" -Pattern "Exported \d+ public function\(s\)" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de fin de chargement avec durée" -Pattern "Module Loaded Successfully in [\d\.]+ms" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log d'initialisation de l'environnement" -Pattern "environment initialized in [\d\.]+ms" -LogFile $latestLog.FullName

    # Test 2: Fonctions Public
    Write-Host "`n🔍 Test 2: Fonctions Public..." -ForegroundColor Cyan

    Write-Host "  Test de Get-ToolkitCatalogFacet..." -ForegroundColor Yellow
    $facets = Get-ToolkitCatalogFacet -Facet OperatingSystems -Verbose
    Start-Sleep -Milliseconds 200
    $testResults += Test-LogEntry -TestName "Log Get-ToolkitCatalogFacet" -Pattern "Retrieving catalog facet" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log résultat facet" -Pattern "Returning \d+ operating system" -LogFile $latestLog.FullName

    Write-Host "  Test de Get-ToolkitUpdatePath..." -ForegroundColor Yellow
    $updatePath = Get-ToolkitUpdatePath -OperatingSystem "Windows 11" -Release "24H2" -Verbose
    Start-Sleep -Milliseconds 200
    $testResults += Test-LogEntry -TestName "Log Get-ToolkitUpdatePath" -Pattern "Getting toolkit update path" -LogFile $latestLog.FullName

    # Test 3: Fonctions Private (via fonctions Public qui les appellent)
    Write-Host "`n⚙️ Test 3: Fonctions Private..." -ForegroundColor Cyan

    Write-Host "  Test de Get-ToolkitCatalogData (via Get-ToolkitCatalogFacet)..." -ForegroundColor Yellow
    $testResults += Test-LogEntry -TestName "Log Get-ToolkitCatalogData" -Pattern "Catalog data initialized" -LogFile $latestLog.FullName

    Write-Host "  Test de Resolve-ToolkitUpdatePath..." -ForegroundColor Yellow
    $testResults += Test-LogEntry -TestName "Log Resolve-ToolkitUpdatePath" -Pattern "Resolving update path" -LogFile $latestLog.FullName

    # Test 4: Affichage du contenu des logs
    Write-Host "`n📜 Test 4: Contenu du fichier de log (dernières 30 lignes)..." -ForegroundColor Cyan
    Get-Content -Path $latestLog.FullName -Tail 30 | ForEach-Object {
        if ($_ -match '\[STAGE\]') {
            Write-Host "  $_" -ForegroundColor Cyan
        } elseif ($_ -match '\[SUCCESS\]') {
            Write-Host "  $_" -ForegroundColor Green
        } elseif ($_ -match '\[ERROR\]') {
            Write-Host "  $_" -ForegroundColor Red
        } elseif ($_ -match '\[WARNING\]') {
            Write-Host "  $_" -ForegroundColor Yellow
        } elseif ($_ -match '\[DEBUG\]') {
            Write-Host "  $_" -ForegroundColor Gray
        } else {
            Write-Host "  $_" -ForegroundColor White
        }
    }

    # Test 5: Déchargement du module
    Write-Host "`n🔄 Test 5: Déchargement du module..." -ForegroundColor Cyan
    Remove-Module PSWimToolkit
    Start-Sleep -Milliseconds 500

    $testResults += Test-LogEntry -TestName "Log de déchargement du module" -Pattern "PSWimToolkit Module Unloading" -LogFile $latestLog.FullName
    $testResults += Test-LogEntry -TestName "Log de fin de déchargement" -Pattern "PSWimToolkit Module Unloaded" -LogFile $latestLog.FullName

    # Résumé
    Write-Host "`n📊 Résumé des tests:" -ForegroundColor Cyan
    $successCount = ($testResults | Where-Object { $_.Success }).Count
    $totalCount = $testResults.Count
    $successRate = [Math]::Round(($successCount / $totalCount) * 100, 2)

    Write-Host "  Total: $totalCount tests" -ForegroundColor White
    Write-Host "  Réussis: $successCount ✅" -ForegroundColor Green
    Write-Host "  Échoués: $($totalCount - $successCount) ❌" -ForegroundColor Red
    Write-Host "  Taux de réussite: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { 'Green' } elseif ($successRate -ge 70) { 'Yellow' } else { 'Red' })

    # Afficher les tests échoués
    $failedTests = $testResults | Where-Object { -not $_.Success }
    if ($failedTests) {
        Write-Host "`n⚠️ Tests échoués:" -ForegroundColor Red
        $failedTests | ForEach-Object {
            Write-Host "  - $($_.Test): $($_.Pattern)" -ForegroundColor Red
        }
    }

    # Statistiques du fichier de log
    Write-Host "`n📈 Statistiques du fichier de log:" -ForegroundColor Cyan
    $logContent = Get-Content -Path $latestLog.FullName
    $logStats = @{
        Total = $logContent.Count
        Stage = ($logContent | Where-Object { $_ -match '\[STAGE\]' }).Count
        Success = ($logContent | Where-Object { $_ -match '\[SUCCESS\]' }).Count
        Info = ($logContent | Where-Object { $_ -match '\[INFO\]' }).Count
        Debug = ($logContent | Where-Object { $_ -match '\[DEBUG\]' }).Count
        Warning = ($logContent | Where-Object { $_ -match '\[WARNING\]' }).Count
        Error = ($logContent | Where-Object { $_ -match '\[ERROR\]' }).Count
    }

    Write-Host "  Total de lignes: $($logStats.Total)" -ForegroundColor White
    Write-Host "  Stage: $($logStats.Stage)" -ForegroundColor Cyan
    Write-Host "  Success: $($logStats.Success)" -ForegroundColor Green
    Write-Host "  Info: $($logStats.Info)" -ForegroundColor White
    Write-Host "  Debug: $($logStats.Debug)" -ForegroundColor Gray
    Write-Host "  Warning: $($logStats.Warning)" -ForegroundColor Yellow
    Write-Host "  Error: $($logStats.Error)" -ForegroundColor Red

    Write-Host "`n✅ Tests terminés avec succès!" -ForegroundColor Green
    Write-Host "📄 Fichier de log: $($latestLog.FullName)" -ForegroundColor Gray

    # Export des résultats
    $reportPath = Join-Path -Path $PSScriptRoot -ChildPath "LoggingTestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $testReport = @{
        Timestamp = Get-Date
        LogFile = $latestLog.FullName
        Tests = $testResults
        Statistics = $logStats
        SuccessRate = $successRate
    }
    $testReport | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath
    Write-Host "📊 Rapport exporté: $reportPath" -ForegroundColor Gray

} catch {
    Write-Host "`n❌ Erreur lors des tests: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    if (Get-Module -Name PSWimToolkit) {
        Remove-Module PSWimToolkit -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Fin des tests ===" -ForegroundColor Cyan
