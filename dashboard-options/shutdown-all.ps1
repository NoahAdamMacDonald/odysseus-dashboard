# ==============================================================================
# ONE-OFF TASK: SHUTDOWN ALL SERVICES
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Dashboard Config
# 	LOCATION   : odysseus root
# 	PURPOSE	   : Stores services ports and IP
# ==============================================================================

# Load central configuration
$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

$OptionId       = "shutdown-all"
$TaskName       = "Shutdown All Services"
$PostflightDir  = Join-Path $cfg.RootDir "dashboard-handlers\postflight"
$OrderFile      = Join-Path $cfg.RootDir "order.json"

@{
    Id        = $OptionId
    Title     = $TaskName
    Order     = $OptionOrder
    GetState  = ({ "RUN" }).GetNewClosure()

    GetStatus = ({
        # Read live services configuration dynamically on each refresh
        $services = $Global:DashboardConfig.Services.Values
        
        # Explicit array wrapping ensures accurate counting across all PowerShell versions
        $activeCount = @($services | Where-Object { 
            $_.Port -gt 0 -and (Test-PortFast -hostName $_.Host -port $_.Port) 
        }).Count

        if ($activeCount -gt 0) {
            return @{ Text = "  [ ACTIVE  ] $TaskName ($activeCount active service(s))"; Color = "Yellow" }
        }
        return @{ Text = "  [ IDLE    ] $TaskName (All services offline)"; Color = "DarkGray" }
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

        Write-Host "`n  ==========================================" -ForegroundColor Yellow
        Write-Host "    STOPPING ALL ACTIVE SERVICES" -ForegroundColor Yellow
        Write-Host "  ==========================================" -ForegroundColor Yellow

        $services = $Global:DashboardConfig.Services.Values

        foreach ($svc in $services) {
            # 1. Terminate process holding open TCP port
            $conn = Get-NetTCPConnection -LocalPort $svc.Port -ErrorAction SilentlyContinue
            if ($conn) {
                $conn.OwningProcess | Select-Object -Unique | ForEach-Object {
                    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
                }
            }

            # 2. Terminate named processes
            foreach ($procName in $svc.NamedProcesses) {
                Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }

            # 3. Wait for port release
            if (Get-Command "Wait-ForPortOffline" -ErrorAction SilentlyContinue) {
                Wait-ForPortOffline -port $svc.Port -serviceName $svc.Name
            }
        }

        # 4. Clean up lingering processes
        if (Get-Command "Stop-LingeringPythonProcesses" -ErrorAction SilentlyContinue) { 
            Stop-LingeringPythonProcesses 
        }

        # 5. Execute ordered postflight handlers
        $handlers = Get-OrderedHandlers -dirPath $PostflightDir -category "Postflight"
        foreach ($h in $handlers) {
            Write-Host "  [Postflight] Executing $($h.Name)..." -ForegroundColor DarkGray
            & $h.FullName
        }

        Write-Host "`n  All services stopped." -ForegroundColor Green
        Write-Host "  Press ANY KEY to return to dashboard..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }).GetNewClosure()
}