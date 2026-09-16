# ==============================================================================
# TEMPLATE: PERSISTENT BACKGROUND SERVICE
# PURPOSE : Manages Tailscale Windows service state and mesh network connectivity.
# PLACE   : Place at "..\dashboard-options\tailscale.ps1"
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Tailscale
# 	LOCATION   : C:\Program Files\Tailscale\tailscale.exe
# 	INSTALL	   : winget install Tailscale.Tailscale
# 	PURPOSE	   : Mesh VPN connectivity for remote dashboard access
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = if ($cfg -and $cfg.Services -and $cfg.Services.Tailscale) { 
    $cfg.Services.Tailscale 
} else {
    @{ Name = "Tailscale Mesh VPN" }
}

$OptionId   = "tailscale"
$OptionName = if ($svc -and $svc.Name) { $svc.Name } else { "Tailscale Mesh VPN" }

# Helper to find tailscale.exe
$GetExe = {
    $cmd = Get-Command "tailscale.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    
    $paths = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
        "$env:LOCALAPPDATA\Tailscale\tailscale.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# Direct CLI status checker
$CheckOnline = {
    param($exePath)
    if (-not $exePath) { return $false }
    $raw = & $exePath status 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $raw -notmatch "Tailscale is stopped" -and $raw -notmatch "Logged out" -and -not [string]::IsNullOrWhiteSpace($raw)) {
        return $true
    }
    return $false
}

# ==============================================================================

@{
    Id        = $OptionId
    Title     = "Toggle $OptionName"

    GetStatus = ({
        $exe = &$GetExe
        $online = &$CheckOnline $exe
        $namePadded = $OptionName.PadRight(25)
        
        $statusStr = if ($online) { 
            "  [ ONLINE  ] $namePadded (Connected)" 
        } else { 
            "  [ OFFLINE ] $namePadded (Disconnected)" 
        }
        return @{ Text = $statusStr; Color = if ($online) { "Green" } else { "DarkGray" } }
    }).GetNewClosure()

    GetState  = ({
        $exe = &$GetExe
        if (&$CheckOnline $exe) { return "STOP" } else { return "START" }
    }).GetNewClosure()

    Execute   = ({
        $exe = &$GetExe
        if (-not $exe) {
            Write-Host "  [ERROR] tailscale.exe not found!" -ForegroundColor Red
            Start-Sleep -Seconds 2
            return
        }

        $online = &$CheckOnline $exe

        if ($online) {
            Write-Host "`n  Disconnecting $OptionName..." -ForegroundColor Yellow
            & $exe down
            Write-Host "  $OptionName disconnected." -ForegroundColor DarkGray
        } else {
            Write-Host "`n  Connecting $OptionName..." -ForegroundColor Green
            
            # Ensure background service is running (handles both display name and key name)
            Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
                Where-Object { $_.Status -ne "Running" } | 
                Start-Service -ErrorAction SilentlyContinue

            & $exe up
            Write-Host "  $OptionName connected." -ForegroundColor Green
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}