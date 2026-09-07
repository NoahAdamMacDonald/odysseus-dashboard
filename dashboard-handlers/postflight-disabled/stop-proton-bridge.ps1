# ==============================================================================
# TITLE: Stop Proton Mail Bridge
# OPTIONAL: Used to allow sync with protonmail, requires ProtonBridge
# ==============================================================================

# Load central configuration
$ParentDir = Split-Path $PSScriptRoot -Parent
$ConfigFile = Join-Path (Split-Path $ParentDir -Parent) "dashboard-config.ps1"
if (-not (Test-Path $ConfigFile)) { $ConfigFile = Join-Path $ParentDir "dashboard-config.ps1" }
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.ProtonBridge

if (-not $svc) {
    Write-Host "  [Postflight] Proton Bridge service configuration not found." -ForegroundColor Red
    return
}

$online = Test-PortFast -hostName $svc.Host -port $svc.Port
if (-not $online) {
    Write-Host "  [Postflight] $($svc.Name) is not running." -ForegroundColor DarkGray
    return
}

Write-Host "  [Postflight] Stopping $($svc.Name)..." -ForegroundColor Yellow

foreach ($procName in $svc.NamedProcesses) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

$netstat = Get-NetTCPConnection -LocalPort $svc.Port -ErrorAction SilentlyContinue
if ($netstat) {
    $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Command "Wait-ForPortOffline" -ErrorAction SilentlyContinue) {
    Wait-ForPortOffline -port $svc.Port -serviceName $svc.Name -maxSeconds 10
} else {
    $elapsed = 0
    while ((Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt 10)) {
        Start-Sleep -Seconds 1
        $elapsed++
    }
}

if (-not (Test-PortFast -hostName $svc.Host -port $svc.Port)) {
    Write-Host "  [Postflight] $($svc.Name) stopped successfully." -ForegroundColor Green
} else {
    Write-Host "  [Postflight] Failed to stop $($svc.Name)." -ForegroundColor Red
}