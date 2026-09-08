# ==============================================================================
# PERSISTENT BACKGROUND SERVICE: OLLAMA
# PURPOSE : Manages a long-running Ollama local LLM inference server.
#           Includes dynamic binary path resolution and REST API socket polling.
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Ollama Installer Setup
# 	LOCATION   : https://ollama.com/download/OllamaSetup.exe
# 	INSTALL	   : Download and run OllamaSetup.exe on the target host machine
# 	PURPOSE	   : Installs the Ollama service runtime, system PATH binaries, and model directory.
#
# 	NAME	   : Ollama CLI / Binary
# 	LOCATION   : System PATH or %LocalAppData%\Programs\Ollama\ollama.exe
# 	PURPOSE	   : Invoked with "serve" argument to spin up local REST API.
# ==============================================================================

# ==============================================================================
# CONFIGURATION: OLLAMA SERVICE
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.Ollama

$OptionId    = "ollama"
$MaxWaitSec  = 15

$OllamaCmd = Get-Command "ollama" -ErrorAction SilentlyContinue
$OllamaExe = if ($OllamaCmd) { $OllamaCmd.Source } else { Join-Path $env:LocalAppData "Programs\Ollama\ollama.exe" }

# ==============================================================================

@{
    Id        = $OptionId
    Title     = "Toggle $($svc.Name)"
    Order     = $OptionOrder

    GetStatus = ({
        $online = Test-PortFast -hostName $svc.Host -port $svc.Port
        $statusStr = if ($online) { 
            "  [ ONLINE  ] $($svc.Name.PadRight(25)) (Port $($svc.Port))" 
        } else { 
            "  [ OFFLINE ] $($svc.Name.PadRight(25)) (Port $($svc.Port))" 
        }
        return @{ Text = $statusStr; Color = if ($online) { "Green" } else { "DarkGray" } }
    }).GetNewClosure()

    GetState  = ({
        if (Test-PortFast -hostName $svc.Host -port $svc.Port) { return "STOP" } else { return "START" }
    }).GetNewClosure()

    Execute   = ({
        $online = Test-PortFast -hostName $svc.Host -port $svc.Port

        if ($online) {
            Write-Host "`n  Stopping $($svc.Name)..." -ForegroundColor Yellow

            $netstat = Get-NetTCPConnection -LocalPort $svc.Port -ErrorAction SilentlyContinue
            if ($netstat) {
                $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
                    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
                }
            }

            foreach ($procName in $svc.NamedProcesses) {
                Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }

            if (Get-Command "Wait-ForPortOffline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOffline -port $svc.Port -serviceName $svc.Name -maxSeconds 10
            } else {
                $elapsed = 0
                while ((Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt 10)) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
            }
            Write-Host "  $($svc.Name) stopped." -ForegroundColor DarkGray

        } else {
            Write-Host "`n  Launching $($svc.Name)..." -ForegroundColor Green
            
            if (Test-Path $OllamaExe) {
                Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden -WorkingDirectory $cfg.RootDir

                if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                    Wait-ForPortOnline -port $svc.Port -serviceName $svc.Name -maxSeconds $MaxWaitSec
                } else {
                    $elapsed = 0
                    while (-not (Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt $MaxWaitSec)) {
                        Start-Sleep -Seconds 1
                        $elapsed++
                    }
                }
            } else {
                Write-Host "  [ ERROR ] Ollama executable not found at $OllamaExe" -ForegroundColor Red
            }
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}