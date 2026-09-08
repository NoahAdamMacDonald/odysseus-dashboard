# ==============================================================================
# TITLE: PROTON CALENDAR SYNC
# Optional: use to create a oneway sync with proton calendar
# Dependency: "..\odysseus\dashboard-dependencies\sync_proton.py"
#			  Set your proton calendar share with everyone url
# ==============================================================================

# Load central configuration
$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg        = $Global:DashboardConfig
$rootDir    = $cfg.RootDir
$venvPython = $cfg.VenvPython

# Resolve script path
$syncScript = Join-Path $rootDir "dashboard-dependencies\sync_proton.py"
if (-not (Test-Path $syncScript)) {
    $syncScript = Join-Path $rootDir "sync_proton.py"
}

if (Test-Path $syncScript) {
    Write-Host "    -> Syncing Proton Calendar..." -ForegroundColor Cyan
    & "$venvPython" "$syncScript"
} else {
    Write-Host "    -> [ ERROR ] sync_proton.py not found at $syncScript" -ForegroundColor Red
}