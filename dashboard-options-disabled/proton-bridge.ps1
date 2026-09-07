# ==============================================================================
# OPTION : PROTON MAIL BRIDGE
# PURPOSE: Manages the background Proton Mail Bridge service and IMAP socket.
#          Allows protonmail users to sync their email
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Proton Mail Bridge Application
# 	LOCATION   : https://proton.me/mail/bridge
# 	PLACE	   : Installed on target host machine (Program Files or AppData)
# 	PURPOSE	   : Runs the background daemon to expose local IMAP (port 1143) and SMTP sockets.
#
# 	NAME	   : Paid Proton Account Subscription
# 	LOCATION   : https://proton.me/pricing
# 	PURPOSE	   : Active paid account (Mail Plus, Unlimited, Duo, Family, or Business) required to unlock Bridge authentication.
# ==============================================================================

# ==============================================================================
# CONFIGURATION
# ==============================================================================
$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.ProtonBridge

$OptionId    = "bridge"
$MaxWaitSec  = 15

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
        function Get-ProtonBridgePath {
            $candidates = @(
                "C:\Program Files\Proton AG\Proton Mail Bridge\proton-bridge.exe",
                (Join-Path $env:ProgramFiles "Proton AG\Proton Mail Bridge\proton-bridge.exe"),
                (Join-Path $env:ProgramFiles "Proton\Bridge\proton-bridge.exe"),
                (Join-Path ${env:ProgramFiles(x86)} "Proton\Bridge\proton-bridge.exe"),
                (Join-Path $env:LocalAppData "Programs\Proton\Bridge\proton-bridge.exe"),
                (Join-Path $env:LocalAppData "Programs\Proton\Proton Mail Bridge\proton-bridge.exe"),
                (Join-Path $env:LocalAppData "Programs\Proton Mail Bridge\proton-bridge.exe")
            )
            foreach ($path in $candidates) {
                if ($path -and (Test-Path $path)) { return [string]$path }
            }

            $regKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
            foreach ($key in $regKeys) {
                $items = Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Proton*Bridge*" }
                foreach ($item in $items) {
                    if ($item.InstallLocation -and (Test-Path (Join-Path $item.InstallLocation "proton-bridge.exe"))) {
                        return [string](Join-Path $item.InstallLocation "proton-bridge.exe")
                    }
                    if ($item.DisplayIcon -and (Test-Path $item.DisplayIcon) -and $item.DisplayIcon -like "*.exe") {
                        return [string]$item.DisplayIcon
                    }
                }
            }

            $searchFolders = @(
                "C:\Program Files\Proton AG",
                (Join-Path $env:ProgramFiles "Proton"),
                (Join-Path ${env:ProgramFiles(x86)} "Proton")
            )
            foreach ($folder in $searchFolders) {
                if (Test-Path $folder) {
                    $found = Get-ChildItem -Path $folder -Filter "proton-bridge.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { return [string]$found.FullName }
                }
            }

            $cmd = Get-Command "proton-bridge.exe" -ErrorAction SilentlyContinue
            if ($cmd) { return [string]$cmd.Source }

            return $null
        }

        $online = Test-PortFast -hostName $svc.Host -port $svc.Port

        if ($online) {
            Write-Host "`n  Stopping $($svc.Name)..." -ForegroundColor Yellow
            
            foreach ($procName in $svc.NamedProcesses) {
                Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            
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
            Write-Host "  $($svc.Name) stopped." -ForegroundColor DarkGray

        } else {
            $bridgeExe = Get-ProtonBridgePath
            if ($bridgeExe -is [array]) { $bridgeExe = [string]$bridgeExe[0] }

            if (-not $bridgeExe) {
                Write-Host "`n  [ WARNING ] Could not automatically locate proton-bridge.exe." -ForegroundColor Yellow
                [Console]::CursorVisible = $true
                $userPath = Read-Host "  Please enter full path to proton-bridge.exe (or ENTER to skip)"
                [Console]::CursorVisible = $false
                if ($userPath -and (Test-Path $userPath.Trim('"'))) {
                    $bridgeExe = $userPath.Trim('"')
                }
            }

            if ($bridgeExe) {
                Write-Host "`n  Launching $($svc.Name) ($bridgeExe)..." -ForegroundColor Green
                try {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $bridgeExe
                    $psi.Arguments = "--noninteractive"
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError  = $true
                    $psi.RedirectStandardInput  = $true

                    $process = [System.Diagnostics.Process]::Start($psi)

                    if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                        Wait-ForPortOnline -port $svc.Port -serviceName $svc.Name -maxSeconds $MaxWaitSec
                    } else {
                        $elapsed = 0
                        while (-not (Test-PortFast -hostName $svc.Host -port $svc.Port) -and ($elapsed -lt $MaxWaitSec)) {
                            Start-Sleep -Seconds 1
                            $elapsed++
                        }
                    }
                } catch {
                    Write-Host "  [ ERROR ] Failed to launch Bridge process: $_" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            } else {
                Write-Host "  Skipping Proton Mail Bridge launch. Press ANY KEY to continue..." -ForegroundColor Yellow
                [void][Console]::ReadKey($true)
            }
        }
        Start-Sleep -Seconds 1
    }).GetNewClosure()
}