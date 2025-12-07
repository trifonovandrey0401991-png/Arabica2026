# Скрипт для исправления импортов Firebase Core
# Использование: powershell -ExecutionPolicy Bypass -File .\fix-firebase-imports.ps1

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ИСПРАВЛЕНИЕ ИМПОРТОВ FIREBASE CORE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = $PSScriptRoot
if (-not $projectPath) {
    $projectPath = Get-Location
}

Write-Host "Путь к проекту: $projectPath" -ForegroundColor Yellow
Write-Host ""

# Файлы для проверки и исправления
$filesToFix = @(
    @{
        Path = "lib/firebase_wrapper.dart"
        LineNumber = 5
        NewLine = "import 'package:firebase_core/firebase_core.dart' as firebase_core;"
    },
    @{
        Path = "lib/firebase_service.dart"
        LineNumber = 15
        NewLine = "import 'package:firebase_core/firebase_core.dart' as firebase_core;"
    },
    @{
        Path = "lib/main.dart"
        LineNumber = 14
        NewLine = "import 'package:firebase_core/firebase_core.dart' as firebase_core;"
    }
)

$fixedCount = 0
$checkedCount = 0

foreach ($fileInfo in $filesToFix) {
    $filePath = Join-Path $projectPath $fileInfo.Path
    
    if (-not (Test-Path $filePath)) {
        Write-Host "WARNING: File not found: $($fileInfo.Path)" -ForegroundColor Yellow
        continue
    }
    
    $checkedCount++
    Write-Host "Checking: $($fileInfo.Path)..." -ForegroundColor Yellow
    
    $content = Get-Content $filePath -Raw -Encoding UTF8
    $lines = Get-Content $filePath -Encoding UTF8
    
    # Проверяем, есть ли неправильный импорт
    $hasWrongImport = $false
    $lineIndex = -1
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "firebase_core_stub") {
            $hasWrongImport = $true
            $lineIndex = $i
            break
        }
    }
    
    if ($hasWrongImport) {
        Write-Host "  ERROR: Found wrong import at line $($lineIndex + 1)" -ForegroundColor Red
        
        # Заменяем неправильный импорт построчно
        $newLines = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -eq $lineIndex) {
                $newLines += $fileInfo.NewLine
            } else {
                $newLines += $lines[$i]
            }
        }
        
        try {
            $newContent = $newLines -join "`r`n"
            Set-Content -Path $filePath -Value $newContent -Encoding UTF8 -NoNewline
            Write-Host "  FIXED!" -ForegroundColor Green
            $fixedCount++
        } catch {
            Write-Host "  ERROR saving: $_" -ForegroundColor Red
        }
    } else {
        # Проверяем, правильный ли импорт
        $hasCorrectImport = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "package:firebase_core/firebase_core\.dart.*as firebase_core") {
                $hasCorrectImport = $true
                break
            }
        }
        
        if ($hasCorrectImport) {
            Write-Host "  OK: Import is correct" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Firebase Core import not found" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files checked: $checkedCount" -ForegroundColor White
Write-Host "Files fixed: $fixedCount" -ForegroundColor $(if ($fixedCount -gt 0) { "Green" } else { "White" })
Write-Host ""

if ($fixedCount -gt 0) {
    Write-Host "SUCCESS: Imports fixed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. flutter clean" -ForegroundColor Cyan
    Write-Host "2. flutter pub get" -ForegroundColor Cyan
    Write-Host "3. flutter run" -ForegroundColor Cyan
} else {
    Write-Host "SUCCESS: All imports are correct!" -ForegroundColor Green
    Write-Host ""
    Write-Host "If problem persists, try:" -ForegroundColor Yellow
    Write-Host "1. flutter clean" -ForegroundColor Cyan
    Write-Host "2. cd android && .\gradlew clean && cd .." -ForegroundColor Cyan
    Write-Host "3. flutter pub get" -ForegroundColor Cyan
    Write-Host "4. flutter run" -ForegroundColor Cyan
}

Write-Host ""
