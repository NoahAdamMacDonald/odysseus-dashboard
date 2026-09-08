# ==============================================================================
# TITLE: STOP CHROMADB VECTOR SERVICE
# Optional: Use if having errors with default odysseus chromadb
# ==============================================================================

$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$chroma = $Global:DashboardConfig.Services.ChromaDB

Write-Host "`n  Stopping $($chroma.Name)..." -ForegroundColor Yellow

$netstat = Get-NetTCPConnection -LocalPort $chroma.Port -ErrorAction SilentlyContinue
if ($netstat) {
    $pids = $netstat.OwningProcess | Select-Object -Unique
    foreach ($pidToKill in $pids) {
        Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
    }

    if (Get-Command "Wait-ForPortOffline" -ErrorAction SilentlyContinue) {
        Wait-ForPortOffline -port $chroma.Port -serviceName $chroma.Name -maxSeconds 10
    } else {
        $elapsed = 0
        while ($elapsed -lt 10) {
            $conn = Get-NetTCPConnection -LocalPort $chroma.Port -ErrorAction SilentlyContinue
            if (-not $conn) { break }
            Start-Sleep -Seconds 1
            $elapsed++
        }
    }
    Write-Host "  $($chroma.Name) stopped." -ForegroundColor DarkGray
} else {
    Write-Host "  $($chroma.Name) is not running." -ForegroundColor DarkGray
}