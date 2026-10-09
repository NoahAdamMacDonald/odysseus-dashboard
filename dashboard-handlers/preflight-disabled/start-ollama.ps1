# ==============================================================================
# TITLE: Start Ollama Server
# ==============================================================================

if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Ollama
$port = if ($svc) { $svc.Port } else { 11434 }
$hostName = if ($svc) { $svc.Host } else { "127.0.0.1" }

# Fast socket check using dashboard utility or native fallback
$online = if (Get-Command Test-PortFast -ErrorAction SilentlyContinue) {
    Test-PortFast -hostName $hostName -port $port
} else {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($hostName, $port, $null, $null)
        $async.AsyncWaitHandle.WaitOne(300, $false)
    } catch { $false } finally { $client.Close() }
}

if (-not $online) {
    $OllamaCmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    $OllamaExe = if ($OllamaCmd) { $OllamaCmd.Source } else { Join-Path $env:LocalAppData "Programs\Ollama\ollama.exe" }

    if (Test-Path $OllamaExe) {
        $rootDir = if ($Global:DashboardConfig) { $Global:DashboardConfig.RootDir } else { $PSScriptRoot }
        Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden -WorkingDirectory $rootDir

        if (Get-Command Wait-ForPortOnline -ErrorAction SilentlyContinue) {
            Wait-ForPortOnline -port $port -serviceName "Ollama" -maxSeconds 15
        } else {
            $elapsed = 0
            while ($elapsed -lt 15) {
                $test = New-Object System.Net.Sockets.TcpClient
                try {
                    $async = $test.BeginConnect($hostName, $port, $null, $null)
                    if ($async.AsyncWaitHandle.WaitOne(300, $false)) { $test.Close(); break }
                } catch {} finally { $test.Close() }
                Start-Sleep -Seconds 1
                $elapsed++
            }
        }
    }
}