# ==============================================================================
# TITLE: DATABASE & VECTOR STORE BACKUP
# ==============================================================================

# Load central configuration
$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg       = $Global:DashboardConfig
$rootDir   = $cfg.RootDir
$backupDir = Join-Path $rootDir "backups"

function Backup-OdysseusData {
    try {
        if (-not (Test-Path $backupDir)) { 
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null 
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        
        # Resolve SQLite database location
        $dbPaths = @(
            (Join-Path $rootDir "app.db"),
            (Join-Path $rootDir "data\app.db")
        )
        foreach ($dbPath in $dbPaths) {
            if (Test-Path $dbPath) {
                Write-Host "    -> Backing up SQLite database..." -ForegroundColor DarkGray
                Copy-Item -Path $dbPath -Destination (Join-Path $backupDir "app_$timestamp.db") -Force
                break
            }
        }
        
        # Resolve Chroma / Vector store location (checks configured Chroma path first)
        $chromaPaths = @(
            $cfg.Services.ChromaDB.DataPath,
            (Join-Path $rootDir "chroma_db"),
            (Join-Path $rootDir "data\chroma"),
            (Join-Path $rootDir "data\vector_store"),
            (Join-Path $rootDir "chroma")
        ) | Select-Object -Unique

        foreach ($cPath in $chromaPaths) {
            if (Test-Path $cPath) {
                Write-Host "    -> Backing up vector store..." -ForegroundColor DarkGray
                Copy-Item -Path $cPath -Destination (Join-Path $backupDir "chroma_$timestamp") -Recurse -Force
                break
            }
        }

        # Auto-prune backups (retain 10 newest backups)
        Get-ChildItem -Path $backupDir -Filter "app_*.db" -ErrorAction SilentlyContinue | 
            Sort-Object CreationTime -Descending | 
            Select-Object -Skip 10 | 
            Remove-Item -Force -ErrorAction SilentlyContinue

        Get-ChildItem -Path $backupDir -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -like "chroma_*" } | 
            Sort-Object CreationTime -Descending | 
            Select-Object -Skip 10 | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Host "    -> [ ERROR ] Backup failed: $_" -ForegroundColor Red
    }
}

Backup-OdysseusData