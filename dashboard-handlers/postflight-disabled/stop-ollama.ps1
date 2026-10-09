# ==============================================================================
# TITLE: Stop Ollama Server
# ==============================================================================

if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Ollama
$port = if ($svc) { $svc.Port } else { 11434 }

# Connect to 127.0.0.1 for local health probes if Host is set to 0.0.0.0
$rawHost = if ($svc) { $svc.Host } else { "127.0.0.1" }
$testHost = if ($rawHost -eq "0.0.0.0") { "127.0.0.1" } else { $rawHost }

$namedProcesses = if ($svc -and $svc.NamedProcesses) { $svc.NamedProcesses } else { @("ollama", "ollama_llama_server") }

# Kill owning process on port 11434
$netstat = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
if ($netstat) {
    $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
}

# Kill named process dependencies from central config
foreach ($procName in $namedProcesses) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Poll port until socket closes
if (Get-Command Wait-ForPortOffline -ErrorAction SilentlyContinue) {
    Wait-ForPortOffline -port $port -serviceName "Ollama" -maxSeconds 10
} else {
    $elapsed = 0
    while ($elapsed -lt 10) {
        $test = New-Object System.Net.Sockets.TcpClient
        try {
            $async = $test.BeginConnect($testHost, $port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne(300, $false)) { $test.Close(); break }
        } catch { break } finally { $test.Close() }
        Start-Sleep -Seconds 1
        $elapsed++
    }
}