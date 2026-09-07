# ==============================================================================
# TEMPLATE: INTERACTIVE TERMINAL UI (TUI) MODULE
# PURPOSE : Renders a full-screen interactive console menu with key navigation,
#           item selection, and sub-module dot-sourcing capabilities.
# PLACE   : Place at "..\dashboard-options\<module-folder>\main.ps1"
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : Dependency name
# 	LOCATION   : path/to/dependency
# 	INSTALL	   : any install instructions
# 	PURPOSE	   : what it does
# ==============================================================================


# ==============================================================================
# CONFIGURATION & SUB-MODULE LOADING:
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

# TEMP / CONFIG HOOK: Map optional target service key from $cfg.Services
$svcKey = "MyServiceKey" # <-- Replace with your service key if bound to a service
$svc = if ($cfg -and $cfg.Services -and $cfg.Services.ContainsKey($svcKey)) { $cfg.Services[$svcKey] } else { $null }

$OptionId    = "my-interactive-ui"
$ViewTitle   = "My Interactive Dashboard"


# Service target parameters for status polling
$TargetHost  = if ($svc -and $svc.Host) { $svc.Host } else { "127.0.0.1" }
$TargetPort  = if ($svc -and $svc.Port) { $svc.Port } else { 8080 }

# Dot-source sub-modules relative to script location (e.g., ./sub/*.ps1)
$subDirPath = Join-Path $PSScriptRoot "sub"
if (Test-Path $subDirPath) {
    Get-ChildItem -Path $subDirPath -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -ne "main.ps1") { . $_.FullName }
    }
}

# ==============================================================================
# HELPER FUNCTIONS:
# ==============================================================================

if (-not (Get-Command Write-SafeLine -ErrorAction SilentlyContinue)) {
    function global:Write-SafeLine {
        param (
            [string]$Text = "",
            [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
            [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black,
            [ref]$LineCounter = $null
        )
        $w = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 79 }
        
        if ($Text.Length -gt $w) {
            $Text = $Text.Substring(0, [Math]::Max(0, $w - 3)) + "..."
        }
        
        Write-Host $Text.PadRight($w) -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
        if ($null -ne $LineCounter) { $LineCounter.Value++ }
    }
}

# ==============================================================================
# INTERACTIVE ENGINE:
# ==============================================================================

function global:Show-InteractiveUI {
    param (
        [string]$Title = "Interactive Console UI"
    )

    $items = @(
        [PSCustomObject]@{ Id = 1; Name = "Primary Engine Core";   Status = "Running"; Priority = "High" }
        [PSCustomObject]@{ Id = 2; Name = "Background Sync Task"; Status = "Idle";    Priority = "Low"  }
        [PSCustomObject]@{ Id = 3; Name = "Network Gateway Node"; Status = "Online";  Priority = "Med"  }
    )

    $selectedIndex   = 0
    $lastRenderLines = 0
    $needsRefresh    = $true

    [Console]::CursorVisible = $false
    Clear-Host

    try {
        while ($true) {
            if ($needsRefresh) {
                $needsRefresh = $false
            }

            $lineCount = 0
            [Console]::SetCursorPosition(0, 0)

            if (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue) {
                Write-AsciiHeader -Name "template" -ForegroundColor Yellow -WriterScriptBlock {
                    param($line)
                    Write-SafeLine $line -ForegroundColor Yellow -LineCounter ([ref]$lineCount)
                }
            } else {
                Write-SafeLine "   === $Title ===" -ForegroundColor Yellow -LineCounter ([ref]$lineCount)
            }

            Write-SafeLine "   ================================================================" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)
            Write-SafeLine "   [ INTERACTIVE MANAGEMENT INTERFACE ]" -ForegroundColor Cyan -LineCounter ([ref]$lineCount)
            Write-SafeLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)

            if ($selectedIndex -ge $items.Count) { $selectedIndex = [Math]::Max(0, $items.Count - 1) }

            for ($i = 0; $i -lt $items.Count; $i++) {
                $item = $items[$i]
                $lineStr = "$($item.Id.ToString().PadRight(4)) | $($item.Name.PadRight(25)) | $($item.Status.PadRight(10)) | Priority: $($item.Priority)"

                if ($i -eq $selectedIndex) {
                    Write-SafeLine "   > $lineStr" -ForegroundColor Black -BackgroundColor Cyan -LineCounter ([ref]$lineCount)
                } else {
                    Write-SafeLine "     $lineStr" -ForegroundColor Gray -LineCounter ([ref]$lineCount)
                }
            }

            Write-SafeLine "" -LineCounter ([ref]$lineCount)
            Write-SafeLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)
            Write-SafeLine "   KEYS: [UP/DN] Navigate | [ENTER] Inspect / Edit | [R] Refresh | [ESC] Back" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)

            # Clear trailing lines from previous larger renders
            if ($lastRenderLines -gt $lineCount) {
                for ($cl = $lineCount; $cl -lt $lastRenderLines; $cl++) {
                    Write-SafeLine "" -LineCounter ([ref]$null)
                }
            }
            $lastRenderLines = $lineCount

            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            # ESC Key: Exit interface
            if ($key.VirtualKeyCode -eq 27) {
                Clear-Host
                return
            }

            # R Key: Force redraw
            if ($key.Character -eq 'r' -or $key.Character -eq 'R') {
                $needsRefresh = $true
                Clear-Host
                continue
            }

            switch ($key.VirtualKeyCode) {
                38 { # Up Arrow
                    if ($selectedIndex -gt 0) { $selectedIndex-- }
                }
                40 { # Down Arrow
                    if ($selectedIndex -lt ($items.Count - 1)) { $selectedIndex++ }
                }
                13 { # Enter Key
                    $selected = $items[$selectedIndex]
                    if (Get-Command Show-ItemInspector -ErrorAction SilentlyContinue) {
                        Show-ItemInspector -Item $selected -ContextState @{ TargetHost = $TargetHost; TargetPort = $TargetPort }
                    } else {
                        Clear-Host
                        [Console]::CursorVisible = $true
                        Write-Host "`n   [ ACTION TRIGGERED ] Selected: $($selected.Name)" -ForegroundColor Green
                        Write-Host "   (Sub-UI inspector command 'Show-ItemInspector' not loaded)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        [Console]::CursorVisible = $false
                    }
                    $needsRefresh = $true
                    Clear-Host
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# ==============================================================================
# DASHBOARD OPTION REGISTRATION:
# ==============================================================================

@{
    Id        = $OptionId
    Title     = $ViewTitle
    Order     = $OptionOrder

    GetState  = ({ "OPEN" }).GetNewClosure()

    GetStatus = ({
        $online = if (Get-Command "Test-PortFast" -ErrorAction SilentlyContinue) {
            Test-PortFast -hostName $TargetHost -port $TargetPort
        } else {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $async = $tcp.BeginConnect($TargetHost, $TargetPort, $null, $null)
                $wait = $async.AsyncWaitHandle.WaitOne(150, $false)
                if ($wait) { $tcp.EndConnect($async); $true } else { $false }
            } catch { $false } finally { if ($tcp) { $tcp.Close() } }
        }

        $text = if ($online) { 
            "  [ ONLINE  ] $($ViewTitle.PadRight(25)) (Port $TargetPort Active)" 
        } else { 
            "  [ READY   ] $($ViewTitle.PadRight(25)) (Standby)" 
        }
        return @{ Text = $text; Color = if ($online) { "Cyan" } else { "DarkGray" } }
    }).GetNewClosure()

    Execute   = ({
        try {
            Show-InteractiveUI -Title $ViewTitle
        } finally {
            [Console]::CursorVisible = $true
            Clear-Host
        }
    }).GetNewClosure()
}