# ==============================================================================
# OPTIONAL: Add if you have errors with the default chromadb install
# PURPOSE : Installs own chromadb to replace one odysseus tries to install
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Python Virtual Environment
# 	LOCATION   : ..\odysseus\venv\Scripts\python.exe
#	PURPOSE	   : Used to run pip auto-installation if chromadb package is missing.
#
# 	NAME	   : ChromaDB Executable
# 	LOCATION   : ..\odysseus\venv\Scripts\chroma.exe
#	PURPOSE	   : Core vector database binary executed on startup.
# ==============================================================================

# ==============================================================================
# CONFIGURATION: CHROMADB VECTOR SERVICE
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg    = $Global:DashboardConfig
$chroma = $cfg.Services.ChromaDB

$OptionId    = "chromadb"


# ==============================================================================

@{
    Id        = $OptionId
    Title     = "Toggle $($chroma.Name)"
    Order     = $OptionOrder

    GetStatus = ({
        $online = Test-PortFast -hostName $chroma.Host -port $chroma.Port
        $statusStr = if ($online) { 
            "  [ ONLINE  ] $($chroma.Name.PadRight(25)) (Port $($chroma.Port))" 
        } else { 
            "  [ OFFLINE ] $($chroma.Name.PadRight(25)) (Port $($chroma.Port))" 
        }
        return @{ Text = $statusStr; Color = if ($online) { "Green" } else { "DarkGray" } }
    }).GetNewClosure()

    GetState  = ({
        if (Test-PortFast -hostName $chroma.Host -port $chroma.Port) { return "STOP" } else { return "START" }
    }).GetNewClosure()

    Execute   = ({
        $online = Test-PortFast -hostName $chroma.Host -port $chroma.Port

        if ($online) {
            Write-Host "`n  Stopping $($chroma.Name)..." -ForegroundColor Yellow

            $netstat = Get-NetTCPConnection -LocalPort $chroma.Port -ErrorAction SilentlyContinue
            if ($netstat) {
                $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
                    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
                }
            }

            if (Get-Command "Wait-ForPortOffline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOffline -port $chroma.Port -serviceName $chroma.Name -maxSeconds 10
            } else {
                $elapsed = 0
                while ((Test-PortFast -hostName $chroma.Host -port $chroma.Port) -and ($elapsed -lt 10)) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
            }

            Write-Host "  $($chroma.Name) stopped." -ForegroundColor DarkGray

        } else {
            Write-Host "`n  Launching $($chroma.Name)..." -ForegroundColor Green

            if (-not (Test-Path $chroma.DataPath)) { 
                New-Item -ItemType Directory -Path $chroma.DataPath -Force | Out-Null 
            }

            if (-not (Test-Path $chroma.ExePath)) {
                Write-Host "  [Setup] Installing chromadb package..." -ForegroundColor Yellow
                & $cfg.VenvPython -m pip install chromadb --quiet
            }

            Start-Process -FilePath $chroma.ExePath -ArgumentList "run --path `"$($chroma.DataPath)`" --host $($chroma.Host) --port $($chroma.Port)" -WindowStyle Hidden

            if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOnline -port $chroma.Port -serviceName $chroma.Name -maxSeconds 15
            } else {
                $elapsed = 0
                while (-not (Test-PortFast -hostName $chroma.Host -port $chroma.Port) -and ($elapsed -lt 15)) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
            }
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}