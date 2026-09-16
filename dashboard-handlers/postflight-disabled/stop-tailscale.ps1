# ==============================================================================
# TITLE: Stop Tailscale Mesh VPN
# ==============================================================================

if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Tailscale
$namedProcesses = if ($svc -and $svc.NamedProcesses) { $svc.NamedProcesses } else { @("tailscale") }

# Dynamically locate tailscale.exe
$tsCmd = Get-Command "tailscale.exe" -ErrorAction SilentlyContinue
$tsExe = if ($tsCmd) { 
    $tsCmd.Source 
} else { 
    $paths = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
        "$env:LocalAppData\Tailscale\tailscale.exe"
    )
    ($paths | Where-Object { Test-Path $_ })[0]
}

# Bring Tailscale tunnel down gracefully
if ($tsExe -and (Test-Path $tsExe)) {
    Start-Process -FilePath $tsExe -ArgumentList "down" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
}

# Stop processes defined in configuration or defaults
foreach ($procName in $namedProcesses) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Poll background service until offline
$elapsed = 0
while ($elapsed -lt 10) {
    $runningService = Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Status -eq "Running" }
    if (-not $runningService) { break }
    Start-Sleep -Seconds 1
    $elapsed++
}