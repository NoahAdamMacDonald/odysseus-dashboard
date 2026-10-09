# ==============================================================================
# ODYSSEUS SERVICE CONFIGURATION
# ==============================================================================
# Import central dashboard configuration if not already loaded in session
if (-not $Global:DashboardConfig) {
    $configPath = Get-ChildItem -Path $PSScriptRoot -Filter "dashboard-config.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($configPath) { . $configPath.FullName }
}

$cfg = $Global:DashboardConfig

# Dynamically resolve root working directory from central config or relative script location
$ServicesDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$global:OdysseusWorkDir = if ($cfg -and $cfg.RootDir) { $cfg.RootDir } else { Split-Path $ServicesDir -Parent }

# Bind host and port configurations linked to central DashboardConfig
$global:OdysseusBindHost = "0.0.0.0"
$global:OdysseusPort     = if ($cfg -and $cfg.Services.Odysseus) { $cfg.Services.Odysseus.Port } else { 7000 }
$global:SDPort           = if ($cfg -and $cfg.Services.StableDiffusion) { $cfg.Services.StableDiffusion.Port } else { 8000 }
$global:ChromaPort       = if ($cfg -and $cfg.Services.ChromaDB) { $cfg.Services.ChromaDB.Port } else { 8100 }

$global:LaunchScript     = "launch-windows.ps1"
# ==============================================================================

function Start-OdysseusService {
    param ([string]$TargetDir = $global:OdysseusWorkDir)

    Write-Host "`n[Odysseus] Initializing environment..." -ForegroundColor Cyan

    $env:TORCH_CUDNN_ENABLED = "0"
    $env:TORCH_CUDNN_V8_API_DISABLED = "1"

    $scriptPath = Join-Path $TargetDir $global:LaunchScript

    if (Test-Path $scriptPath) {
        Write-Host "[Odysseus] Executing $global:LaunchScript on host $global:OdysseusBindHost (Port $global:OdysseusPort)..." -ForegroundColor Green
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`" -BindHost $global:OdysseusBindHost" -WorkingDirectory $TargetDir
    } else {
        Write-Host "[ERROR] Could not find launch script at $scriptPath" -ForegroundColor Red
    }
}

function Invoke-OdysseusCleanup {
    param (
        [string]$TargetDir = $global:OdysseusWorkDir,
        [int[]]$Ports = @($global:OdysseusPort, $global:SDPort, $global:ChromaPort)
    )

    Write-Host "`n[Odysseus] Server stopped. Running cleanup tasks..." -ForegroundColor Yellow

    # 1. Terminate processes listening on configured ports
    foreach ($port in $Ports) {
        try {
            $netstat = netstat -aon | Select-String ":$port\s+.*LISTENING"
            foreach ($line in $netstat) {
                $parts = $line.ToString().Trim() -split '\s+'
                $pidToKill = $parts[-1]
                if ($pidToKill -and $pidToKill -ne "0") {
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }

    # 2. Purge compiled Python bytecode (__pycache__)
    if (Test-Path $TargetDir) {
        Get-ChildItem -Path $TargetDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 3. Clear system temp directories
    $tempPath = Join-Path $env:TEMP "odysseus"
    if (Test-Path $tempPath) {
        Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[Odysseus] Cleanup complete." -ForegroundColor Green
    Start-Sleep -Seconds 2
}