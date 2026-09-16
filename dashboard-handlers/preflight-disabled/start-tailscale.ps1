# ==============================================================================
# TITLE: Start Tailscale Mesh VPN
# ==============================================================================

if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Tailscale

# Check if background service is running
$runningService = Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Status -eq "Running" }
$online = [bool]$runningService

if (-not $online) {
    # Start background service if present
    Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Status -ne "Running" } | 
        Start-Service -ErrorAction SilentlyContinue

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

    if ($tsExe -and (Test-Path $tsExe)) {
        $rootDir = if ($Global:DashboardConfig) { $Global:DashboardConfig.RootDir } else { $PSScriptRoot }

        Start-Process -FilePath $tsExe -ArgumentList "up" -WindowStyle Hidden -WorkingDirectory $rootDir

        # Wait loop for service initialization
        $elapsed = 0
        while ($elapsed -lt 10) {
            $status = Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
                Where-Object { $_.Status -eq "Running" }
            if ($status) { break }
            Start-Sleep -Seconds 1
            $elapsed++
        }
    }
}