# ==============================================================================
# SERVICE HELPERS: PORT & PROCESS MANAGEMENT
# ==============================================================================

function Wait-ForPortOnline ([int]$port, [string]$serviceName, [int]$maxSeconds = 35) {
    Write-Host ""
    for ($i = 1; $i -le $maxSeconds; $i++) {
        if (Test-PortFast -hostName "127.0.0.1" -port $port) {
            Write-Host ("`r  [ ONLINE  ] $serviceName is ready! (took ${i}s)".PadRight(70)) -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        $dots = "." * (($i % 4) + 1)
        Write-Host ("`r  Waiting for $serviceName on port $port (${i}s / ${maxSeconds}s)$dots".PadRight(70)) -ForegroundColor Yellow -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ("`n  [ WARNING ] $serviceName did not respond within ${maxSeconds}s.".PadRight(70)) -ForegroundColor Red
    Start-Sleep -Seconds 2
}

function Wait-ForPortOffline ([int]$port, [string]$serviceName, [int]$maxSeconds = 10) {
    Write-Host ""
    for ($i = 1; $i -le $maxSeconds; $i++) {
        if (-not (Test-PortFast -hostName "127.0.0.1" -port $port)) {
            Write-Host ("`r  [ OFFLINE ] $serviceName stopped successfully.".PadRight(70)) -ForegroundColor Gray
            Start-Sleep -Seconds 1
            return
        }
        $dots = "." * (($i % 4) + 1)
        Write-Host ("`r  Stopping $serviceName on port $port (${i}s)$dots".PadRight(70)) -ForegroundColor Yellow -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ("`n  [ WARNING ] $serviceName on port $port is still listening.".PadRight(70)) -ForegroundColor Red
    Start-Sleep -Seconds 1
}

function Stop-LingeringPythonProcesses {
    param([string[]]$keywords = @("app.py", "sync_proton.py", "uvicorn", "fastapi"))
    
    Get-Process -Name "python", "pythonw" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
            foreach ($kw in $keywords) {
                if ($cmdLine -and $cmdLine -like "*$kw*") {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    break
                }
            }
        } catch {}
    }
}