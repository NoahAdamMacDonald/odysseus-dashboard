# ==============================================================================
# TITLE: Start Proton Mail Bridge
# OptionaL: Use to connect proton mail
# ==============================================================================

# Load central configuration
$ParentDir = Split-Path $PSScriptRoot -Parent
$ConfigFile = Join-Path (Split-Path $ParentDir -Parent) "dashboard-config.ps1"
if (-not (Test-Path $ConfigFile)) { $ConfigFile = Join-Path $ParentDir "dashboard-config.ps1" }
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.ProtonBridge
$MaxWaitSec = 15

if (-not $svc) {
    Write-Host "  [Preflight] Proton Bridge service configuration not found." -ForegroundColor Red
    return
}

if (Test-PortFast -hostName $svc.Host -port $svc.Port) {
    Write-Host "  [Preflight] $($svc.Name) is already running." -ForegroundColor DarkGray
    return
}

function Get-ProtonBridgePath {
    $candidates = @(
        "C:\Program Files\Proton AG\Proton Mail Bridge\proton-bridge.exe",
        (Join-Path $env:ProgramFiles "Proton AG\Proton Mail Bridge\proton-bridge.exe"),
        (Join-Path $env:ProgramFiles "Proton\Bridge\proton-bridge.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Proton\Bridge\proton-bridge.exe"),
        (Join-Path $env:LocalAppData "Programs\Proton\Bridge\proton-bridge.exe"),
        (Join-Path $env:LocalAppData "Programs\Proton\Proton Mail Bridge\proton-bridge.exe"),
        (Join-Path $env:LocalAppData "Programs\Proton Mail Bridge\proton-bridge.exe")
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) { return [string]$path }
    }

    $regKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($key in $regKeys) {
        $items = Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Proton*Bridge*" }
        foreach ($item in $items) {
            if ($item.InstallLocation -and (Test-Path (Join-Path $item.InstallLocation "proton-bridge.exe"))) {
                return [string](Join-Path $item.InstallLocation "proton-bridge.exe")
            }
            if ($item.DisplayIcon -and (Test-Path $item.DisplayIcon) -and $item.DisplayIcon -like "*.exe") {
                return [string]$item.DisplayIcon
            }
        }
    }

    $searchFolders = @(
        "C:\Program Files\Proton AG",
        (Join-Path $env:ProgramFiles "Proton"),
        (Join-Path ${env:ProgramFiles(x86)} "Proton")
    )
    foreach ($folder in $searchFolders) {
        if (Test-Path $folder) {
            $found = Get-ChildItem -Path $folder -Filter "proton-bridge.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return [string]$found.FullName }
        }
    }

    $cmd = Get-Command "proton-bridge.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return [string]$cmd.Source }

    return $null
}

$bridgeExe = Get-ProtonBridgePath
if ($bridgeExe -is [array]) { $bridgeExe = [string]$bridgeExe[0] }

if ($bridgeExe) {
    Write-Host "  [Preflight] Starting $($svc.Name)..." -ForegroundColor Cyan
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $bridgeExe
        $psi.Arguments = "--noninteractive"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true

        $process = [System.Diagnostics.Process]::Start($psi)

        if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
            Wait-ForPortOnline -port $svc.Port -serviceName $svc.Name -maxSeconds $MaxWaitSec
        } else {
            $elapsed = 0
            while (-not (Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt $MaxWaitSec)) {
                Start-Sleep -Seconds 1
                $elapsed++
            }
        }

        if (Test-PortFast -hostName $svc.Host -port $svc.Port) {
            Write-Host "  [Preflight] $($svc.Name) started successfully." -ForegroundColor Green
        } else {
            Write-Host "  [Preflight] $($svc.Name) launch timed out." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [Preflight] Failed to launch $($svc.Name): $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [Preflight] Could not locate proton-bridge.exe. Skipping." -ForegroundColor Yellow
}