# ==============================================================================
# TITLE: Start Tailscale Mesh VPN
# ==============================================================================

Write-Host "`n  [PREFLIGHT] Checking Tailscale Mesh VPN..." -ForegroundColor Cyan

# Locate tailscale.exe dynamically
$exe = Get-Command "tailscale.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $exe) {
    $paths = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
        "$env:LOCALAPPDATA\Tailscale\tailscale.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { $exe = $p; break } }
}

if ($exe) {
    # Ensure background service is active
    Get-Service -Name "IPNService", "Tailscale" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Status -ne "Running" } | 
        Start-Service -ErrorAction SilentlyContinue

    # Connect Tailscale
    & $exe up 2>$null
    Write-Host "  [PREFLIGHT] Tailscale Mesh VPN connected." -ForegroundColor Green
} else {
    Write-Host "  [PREFLIGHT ERROR] tailscale.exe not found!" -ForegroundColor Red
}