# ==============================================================================
# TITLE: START CHROMADB VECTOR SERVICE
# Optional: Use if having errors with odysseus default chromadb
# ==============================================================================

$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg    = $Global:DashboardConfig
$chroma = $cfg.Services.ChromaDB
$MaxWaitSec = 15

Write-Host "[PREFLIGHT] Checking $($chroma.Name) on port $($chroma.Port)..." -ForegroundColor Cyan

# Test port availability
$online = if (Get-Command "Test-PortFast" -ErrorAction SilentlyContinue) {
    Test-PortFast -hostName $chroma.Host -port $chroma.Port
} else {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($chroma.Host, $chroma.Port, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne(300, $false)
        if ($wait) { $tcp.EndConnect($async); $true } else { $false }
    } catch { $false } finally { if ($tcp) { $tcp.Close() } }
}

if (-not $online) {
    Write-Host "  -> Launching $($chroma.Name)..." -ForegroundColor Green

    if (-not (Test-Path $chroma.DataPath)) { 
        New-Item -ItemType Directory -Path $chroma.DataPath -Force | Out-Null 
    }

    if (-not (Test-Path $chroma.ExePath)) {
        Write-Host "  -> [Setup] Installing chromadb package..." -ForegroundColor Yellow
        & $cfg.VenvPython -m pip install chromadb --quiet
    }

    Start-Process -FilePath $chroma.ExePath -ArgumentList "run --path `"$($chroma.DataPath)`" --host $($chroma.Host) --port $($chroma.Port)" -WindowStyle Hidden

    # Poll port until service is active
    if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
        Wait-ForPortOnline -port $chroma.Port -serviceName $chroma.Name -maxSeconds $MaxWaitSec
    } else {
        $elapsed = 0
        while ($elapsed -lt $MaxWaitSec) {
            $check = try {
                $c = New-Object System.Net.Sockets.TcpClient
                $a = $c.BeginConnect($chroma.Host, $chroma.Port, $null, $null)
                if ($a.AsyncWaitHandle.WaitOne(300, $false)) { $c.EndConnect($a); $true } else { $false }
            } catch { $false } finally { if ($c) { $c.Close() } }

            if ($check) { break }
            Start-Sleep -Seconds 1
            $elapsed++
        }
    }
} else {
    Write-Host "  -> $($chroma.Name) is already active." -ForegroundColor DarkGray
}