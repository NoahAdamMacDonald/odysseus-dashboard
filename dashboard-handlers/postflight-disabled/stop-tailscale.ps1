# ==============================================================================
# TITLE: Stop Tailscale Mesh VPN
# ==============================================================================

Write-Host "`n  [POSTFLIGHT] Disconnecting Tailscale Mesh VPN..." -ForegroundColor Yellow

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
    & $exe down 2>$null
    Write-Host "  [POSTFLIGHT] Tailscale Mesh VPN disconnected." -ForegroundColor DarkGray
} else {
    Write-Host "  [POSTFLIGHT ERROR] tailscale.exe not found!" -ForegroundColor Red
}