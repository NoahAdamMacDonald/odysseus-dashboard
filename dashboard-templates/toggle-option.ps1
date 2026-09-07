# ==============================================================================
# TEMPLATE: PERSISTENT BACKGROUND SERVICE
# PURPOSE : Manages a long-running service/server bound to a local TCP port.
# PLACE   : Place at "..\dashboard-options\<option-name>.ps1"
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Dependency name
# 	LOCATION   : path/to/dependency
# 	INSTALL	   : any install instructions
# 	PURPOSE	   : what it does
# ==============================================================================


# ==============================================================================
# CONFIGURATION:
# 
# To register this service in dashboard-config.ps1, add an entry under $Services:
#   "MyServiceKey" = @{
#       Name           = "My Service Name"
#       Host           = "127.0.0.1"
#       Port           = 8000
#       NamedProcesses = @("myservice") # Optional process names to kill on stop
#   }
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

# TEMP / CONFIG HOOK: Map your service key defined in $cfg.Services (e.g., $cfg.Services.MyServiceKey)
$svc = if ($cfg -and $cfg.Services -and $cfg.Services.MyServiceKey) { 
    $cfg.Services.MyServiceKey 
}

$OptionId    = "my-service"
$MaxWaitSec  = 30

# Path resolution leveraging $cfg with fallback
$TargetDir   = if ($cfg -and $cfg.RootDir) { $cfg.RootDir } else { Split-Path $PSScriptRoot -Parent }
$VenvPython  = if ($cfg -and $cfg.VenvPython) { $cfg.VenvPython } else { Join-Path $TargetDir "venv\Scripts\python.exe" }
$ServerScript= Join-Path $TargetDir "scripts\server.py"
$LaunchArgs  = "--host $($svc.Host) --port $($svc.Port)"

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

            # Terminate active socket connection process
            $netstat = Get-NetTCPConnection -LocalPort $svc.Port -ErrorAction SilentlyContinue
            if ($netstat) {
                $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
                    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
                }
            }

            # Terminate secondary processes defined in config
            if ($svc.NamedProcesses) {
                foreach ($procName in $svc.NamedProcesses) {
                    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
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
            
            $cmd = "`"$VenvPython`" `"$ServerScript`" $LaunchArgs"
            Start-Process cmd.exe -ArgumentList "/k `"$cmd`"" -WorkingDirectory $TargetDir

            if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOnline -port $svc.Port -serviceName $svc.Name -maxSeconds $MaxWaitSec
            } else {
                $elapsed = 0
                while (-not (Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt $MaxWaitSec)) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
            }
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}