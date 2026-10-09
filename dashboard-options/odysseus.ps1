# ==============================================================================
# PERSISTENT BACKGROUND SERVICE: ODYSSEUS CORE
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Preflight
# 	LOCATION   : "..\odysseus\dashboard-handlers\preflight"
# 	PURPOSE	   : Executes preflight files before starting odysseus
#
# 	NAME	   : Postflight
# 	LOCATION   : "..\odysseus\dashboard-handlers\postflight"
# 	PURPOSE	   : Executes postflight files at odysseus shutdown
# ==============================================================================


# ==============================================================================
# CONFIGURATION: ODYSSEUS CORE
# ==============================================================================
$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.Odysseus

$OptionId     = "odysseus"

$LaunchScript  = Join-Path $cfg.RootDir "launch-windows.ps1"
$HandlersDir   = Join-Path $cfg.RootDir "dashboard-handlers"
$PreflightDir  = Join-Path $HandlersDir "preflight"
$PostflightDir = Join-Path $HandlersDir "postflight"
$OrderFile     = Join-Path $cfg.RootDir "order.json"

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
        function Get-OrderedHandlers ($dirPath, $category) {
            if (-not (Test-Path $dirPath)) { return @() }
            
            $orderMap = @{}
            if (Test-Path $OrderFile) {
                try {
                    $jsonObj = Get-Content -Path $OrderFile -Raw -ErrorAction Stop | ConvertFrom-Json
                    if ($jsonObj -and $jsonObj.$category) {
                        foreach ($prop in $jsonObj.$category.psobject.Properties) {
                            $orderMap[$prop.Name] = [int]$prop.Value
                        }
                    }
                } catch {}
            }

            $files = Get-ChildItem -Path $dirPath -Filter "*.ps1" -ErrorAction SilentlyContinue
            return @($files | Sort-Object @{ Expression = { if ($null -ne $orderMap[$_.Name]) { [int]$orderMap[$_.Name] } else { 999 } } }, Name)
        }

        $online = Test-PortFast -hostName $svc.Host -port $svc.Port

        if ($online) {
            Write-Host "`n  Stopping $($svc.Name)..." -ForegroundColor Yellow

            $netstat = Get-NetTCPConnection -LocalPort $svc.Port -ErrorAction SilentlyContinue
            if ($netstat) {
                $netstat.OwningProcess | Select-Object -Unique | ForEach-Object {
                    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
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

            $handlers = Get-OrderedHandlers -dirPath $PostflightDir -category "Postflight"
            foreach ($h in $handlers) {
                Write-Host "  [Postflight] Executing $($h.Name)..." -ForegroundColor DarkGray
                & $h.FullName
            }

            Write-Host "  $($svc.Name) stopped." -ForegroundColor DarkGray

        } else {
            $handlers = Get-OrderedHandlers -dirPath $PreflightDir -category "Preflight"
            foreach ($h in $handlers) {
                Write-Host "  [Preflight] Executing $($h.Name)..." -ForegroundColor Cyan
                & $h.FullName
            }

            Write-Host "`n  Launching $($svc.Name)..." -ForegroundColor Green
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$LaunchScript`" -Port $($svc.Port) -BindHost $($svc.Host)" -WorkingDirectory $cfg.RootDir

            if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOnline -port $svc.Port -serviceName $svc.Name -maxSeconds 45
            } else {
                $elapsed = 0
                while (-not (Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt 45)) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
            }
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}