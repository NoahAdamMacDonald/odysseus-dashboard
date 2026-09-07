# ==============================================================================
# SERVICE OPTION: TOGGLE STABLE DIFFUSION
# PURPOSE : Manages the Stable Diffusion local PyTorch/Diffusers server process.
# OPTIONAL: For use to run/stop stable diffusion
# ==============================================================================

# ==============================================================================
# CONFIGURATION:
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

# Map service key from $cfg.Services
$svcKey = "StableDiffusion"
$svc = if ($cfg -and $cfg.Services -and $cfg.Services.ContainsKey($svcKey)) { 
    $cfg.Services[$svcKey] 
}

$OptionId    = "toggle-stable-diffusion"
$MaxWaitSec  = 90 # Extended timeout to allow pipeline and model weights to load into VRAM

# Path resolution leveraging $cfg with fallback
$TargetDir   = if ($cfg -and $cfg.RootDir) { $cfg.RootDir } else { Split-Path $PSScriptRoot -Parent }
$VenvPython  = if ($cfg -and $cfg.VenvPython) { $cfg.VenvPython } else { Join-Path $TargetDir "venv\Scripts\python.exe" }
$ServerScript= Join-Path $TargetDir "scripts\diffusion_server.py"

# Construct Launch Command with CUDA environment variables and model parameters
$NegPrompt   = "low quality, blurry, out of focus, deformed, distorted, disfigured, unfinished, smudged, watermark, artifacts"
$LaunchArgs  = "--model stabilityai/stable-diffusion-3.5-medium --host $($svc.Host) --port $($svc.Port) --steps 20 --guidance-scale 3.5 --negative-prompt `"$NegPrompt`""

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

            # Terminate secondary named processes if defined
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
            Write-Host "  (Loading weights into VRAM may take up to 60 seconds...)" -ForegroundColor DarkGray
            
            $cmd = "set CUDA_VISIBLE_DEVICES=0 && `"$VenvPython`" `"$ServerScript`" $LaunchArgs"
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