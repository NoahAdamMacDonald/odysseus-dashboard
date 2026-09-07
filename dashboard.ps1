# Requires -Version 5.1

$ErrorActionPreference = "Stop"

try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    
    $TargetDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    Get-ChildItem -Path $TargetDir -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

    $WindowTitle = "Odysseus Control Center"
    $Host.UI.RawUI.WindowTitle = $WindowTitle
    [Console]::CursorVisible = $false
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8

    # Enable Virtual Terminal (ANSI) Processing in Windows Console Host
    function Enable-VTMode {
        try {
            if (-not ("Win32.WinConsole" -as [type])) {
                $code = @"
using System;
using System.Runtime.InteropServices;
namespace Win32 {
    public class WinConsole {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    }
}
"@
                Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
            }
            $hOut = [Win32.WinConsole]::GetStdHandle(-11)
            $mode = 0
            if ([Win32.WinConsole]::GetConsoleMode($hOut, [ref]$mode)) {
                [Win32.WinConsole]::SetConsoleMode($hOut, $mode -bor 4) | Out-Null
            }
        } catch {}
    }

    Enable-VTMode

    # ANSI Escape Codes for Flicker-Free Single-Buffer Rendering
    $ESC           = [char]27
    $C_RESET       = "$ESC[0m"
    $FG_RED        = "$ESC[31m"
    $FG_GREEN      = "$ESC[32m"
    $FG_YEL        = "$ESC[33m"
    $FG_CYAN       = "$ESC[36m"
    $FG_WHITE      = "$ESC[37m"
    $FG_GRAY       = "$ESC[90m"
    $FG_BLK        = "$ESC[30m"
    $BG_CYAN       = "$ESC[46m"
    $C_CLEAR_BELOW = "$ESC[J"  # Erase from cursor to end of screen

    $TemplatesDir = Join-Path $TargetDir "dashboard-templates"
    if (Test-Path $TemplatesDir) {
        Get-ChildItem -Path $TemplatesDir -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
    }

    $ServicesDir = Join-Path $TargetDir "dashboard-services"
    if (Test-Path $ServicesDir) {
        Get-ChildItem -Path $ServicesDir -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
    }

	function global:Test-PortFast {
		param(
			[string]$hostName = "127.0.0.1",
			[int]$port = 0,
			[int]$timeoutMs = 100
		)
		if ($port -le 0) { return $false }

		# Map wildcard listener addresses to local loopback for client probes
		$targetHost = if ($hostName -eq "0.0.0.0" -or $hostName -eq "::") { "127.0.0.1" } else { $hostName }

		$client = New-Object System.Net.Sockets.TcpClient
		try {
			$async = $client.BeginConnect($targetHost, $port, $null, $null)
			if (-not $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
				$client.Close()
				return $false
			}
			$client.EndConnect($async)
			$client.Close()
			return $true
		} catch {
			return $false
		}
	}

    $script:OptionsCache     = @()
    $script:StatusCache      = @{}
    $script:IsLoadingOptions = $false
    $script:ExcludeFiles     = @("dashboard.ps1", "dashboard-settings.ps1")

    function Update-DashboardOptionsCache {
        if ($script:IsLoadingOptions) { return }
        $script:IsLoadingOptions = $true

        try {
            $OptionsDir = Join-Path $TargetDir "dashboard-options"
            $OrderFile  = Join-Path $TargetDir "order.json"
            $discovered = @()

            $orderMap = @{}
            if (Test-Path $OrderFile) {
                try {
                    $jsonObj = Get-Content -Path $OrderFile -Raw -ErrorAction Stop | ConvertFrom-Json
                    if ($jsonObj) {
                        # Recursively walk properties to support both flat maps and nested JSON sections
                        function Read-OrderNode ($node) {
                            foreach ($prop in $node.psobject.Properties) {
                                if ($prop.Value -is [PSCustomObject]) {
                                    Read-OrderNode $prop.Value
                                } elseif ($null -ne $prop.Value) {
                                    $orderMap[$prop.Name] = [int]$prop.Value
                                }
                            }
                        }
                        Read-OrderNode $jsonObj
                    }
                } catch {}
            }

            if (Test-Path $OptionsDir) {
                $targetFiles = Get-ChildItem -Path $OptionsDir -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
                    Where-Object { 
                        $script:ExcludeFiles -notcontains $_.Name -and
                        $_.FullName -notmatch '[\/\\]sub[\/\\]'
                    }

                foreach ($file in $targetFiles) {
                    try {
                        $output = & $file.FullName
                        $validOpts = @($output | Where-Object { $_ -is [hashtable] -and $_.ContainsKey("Execute") })

                        foreach ($opt in $validOpts) {
                            if ($opt.Title -is [scriptblock]) { 
                                $opt.Title = & $opt.Title 
                            }

                            $ord = 999
                            if ($null -ne $orderMap[$file.Name]) {
                                $ord = [int]$orderMap[$file.Name]
                            } elseif ($null -ne $orderMap[$file.BaseName]) {
                                $ord = [int]$orderMap[$file.BaseName]
                            } elseif ($opt.ContainsKey("Id") -and $null -ne $orderMap[$opt.Id]) {
                                $ord = [int]$orderMap[$opt.Id]
                            }

                            $opt["Order"] = $ord
                            $discovered += $opt
                        }
                    } catch {}
                }
            }

            $uniqueList = @()
            $seenKeys = @{}
            foreach ($item in $discovered) {
                $key = if ($item.Id) { $item.Id } else { $item.Title }
                if (-not $seenKeys.ContainsKey($key)) {
                    $seenKeys[$key] = $true
                    $uniqueList += $item
                }
            }

            $script:OptionsCache = @($uniqueList | Sort-Object { [int]$_.Order }, { $_.Title })
        } finally {
            $script:IsLoadingOptions = $false
        }
    }

    function Update-StatusCache {
        $script:StatusCache.Clear()
        foreach ($opt in $script:OptionsCache) {
            $keyId = if ($opt.Id) { $opt.Id } else { $opt.Title }
            $entry = @{
                StatusText  = $null
                StatusColor = "DarkGray"
                State       = $null
            }

            if ($opt.ContainsKey("GetStatus") -and $opt.GetStatus) {
                try { 
                    $res = & $opt.GetStatus
                    if ($res -is [hashtable]) {
                        $entry.StatusText  = $res.Text
                        $entry.StatusColor = $res.Color
                    } elseif ($res) {
                        $entry.StatusText = $res.ToString()
                    }
                } catch {}
            }
            
            if ($opt.ContainsKey("GetState") -and $opt.GetState) {
                try { 
                    $res = & $opt.GetState
                    if ($res) { $entry.State = $res.ToString() }
                } catch {}
            }

            $script:StatusCache[$keyId] = $entry
        }
    }

    # Frame Buffer Engine: Constructs the full UI in memory and flushes atomically
    function Render-Dashboard {
        param([int]$selectedIndex = 0)

        if ($script:IsLoadingOptions) { return }

        $lineWidth = 74
        $sb = New-Object System.Text.StringBuilder

        # Position cursor at top-left home (0,0) without clearing screen
        [void]$sb.Append("$ESC[H")

        # Header - Redirect Stream 6 (Information Stream) to prevent Write-Host leak
        if (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue) {
            $capturedHeader = & { Write-AsciiHeader -Name "odysseus" -ForegroundColor Red -Width 65 } 6>&1 | Out-String
            $asciiLines = $capturedHeader -split "`r?\n"
            foreach ($line in $asciiLines) {
                if ($line.Trim().Length -gt 0) {
                    $cleanLine = $line -replace '\e\[[0-9;]*m', ''
                    $clipped = if ($cleanLine.Length -gt $lineWidth) { $cleanLine.Substring(0, $lineWidth) } else { $cleanLine.PadRight($lineWidth) }
                    [void]$sb.AppendLine("${FG_RED}${clipped}${C_RESET}")
                }
            }
        } else {
            [void]$sb.AppendLine("${FG_RED}" + ("  ==============================================================".PadRight($lineWidth)) + "${C_RESET}")
            [void]$sb.AppendLine("${FG_RED}" + ("                    ODYSSEUS CONTROL CENTER                    ".PadRight($lineWidth)) + "${C_RESET}")
        }

        [void]$sb.AppendLine("${FG_GRAY}" + ("  ==============================================================".PadRight($lineWidth)) + "${C_RESET}")
        [void]$sb.AppendLine("${FG_CYAN}" + ("  SYSTEM SERVICE STATUS                                          ".PadRight($lineWidth)) + "${C_RESET}")
        [void]$sb.AppendLine("${FG_GRAY}" + ("  --------------------------------------------------------------".PadRight($lineWidth)) + "${C_RESET}")

        # Status lines
        $statusPrinted = 0
        foreach ($opt in $script:OptionsCache) {
            $keyId = if ($opt.Id) { $opt.Id } else { $opt.Title }
            if ($script:StatusCache.ContainsKey($keyId)) {
                $s = $script:StatusCache[$keyId]
                if ($s.StatusText) {
                    $txt = $s.StatusText
                    $lineStr = if ($txt.Length -gt $lineWidth) { $txt.Substring(0, $lineWidth) } else { $txt.PadRight($lineWidth) }
                    
                    $col = switch ($s.StatusColor) {
                        "Green"    { $FG_GREEN }
                        "Red"      { $FG_RED }
                        "Cyan"     { $FG_CYAN }
                        "Yellow"   { $FG_YEL }
                        "DarkGray" { $FG_GRAY }
                        default    { $FG_WHITE }
                    }
                    [void]$sb.AppendLine("${col}${lineStr}${C_RESET}")
                    $statusPrinted++
                }
            }
        }

        if ($statusPrinted -eq 0) {
            [void]$sb.AppendLine("${FG_GRAY}" + ("  (No background service status reported)".PadRight($lineWidth)) + "${C_RESET}")
        }

        [void]$sb.AppendLine("${FG_GRAY}" + ("  --------------------------------------------------------------".PadRight($lineWidth)) + "${C_RESET}")
        [void]$sb.AppendLine("${FG_YEL}" + ("  ACTIONS (Arrows/W/S/Numbers + ENTER | [ESC] Settings | [R] Refresh)".PadRight($lineWidth)) + "${C_RESET}")
        [void]$sb.AppendLine("".PadRight($lineWidth))

        # Menu Options
        for ($i = 0; $i -lt $script:OptionsCache.Count; $i++) {
            $opt = $script:OptionsCache[$i]
            $keyId = if ($opt.Id) { $opt.Id } else { $opt.Title }
            
            $numLabel = "[" + ($i + 1) + "] "
            $isSel = ($i -eq $selectedIndex)
            $prefix = if ($isSel) { "  > " + $numLabel } else { "    " + $numLabel }

            $state = if ($script:StatusCache.ContainsKey($keyId)) { $script:StatusCache[$keyId].State } else { $null }

            if ($state) {
                $leftStr = $prefix + $opt.Title
                $tagStr  = "[" + $state + "]"
                $padLen  = [math]::Max(1, $lineWidth - $leftStr.Length - $tagStr.Length)
                $midPad  = "".PadRight($padLen)

                $tagCol = switch ($state) {
                    "START" { $FG_GREEN }
                    "STOP"  { $FG_RED }
                    "OPEN"  { $FG_CYAN }
                    "RUN"   { $FG_YEL }
                    default { $FG_GRAY }
                }

                if ($isSel) {
                    [void]$sb.AppendLine("${BG_CYAN}${FG_BLK}${leftStr}${midPad}${tagCol}${tagStr}${C_RESET}")
                } else {
                    [void]$sb.AppendLine("${FG_WHITE}${leftStr}${midPad}${tagCol}${tagStr}${C_RESET}")
                }
            } else {
                $fullLine = ($prefix + $opt.Title).PadRight($lineWidth)
                if ($isSel) {
                    [void]$sb.AppendLine("${BG_CYAN}${FG_BLK}${fullLine}${C_RESET}")
                } else {
                    [void]$sb.AppendLine("${FG_WHITE}${fullLine}${C_RESET}")
                }
            }
        }

        # Exit Option
        $exitIdx = $script:OptionsCache.Count
        $exitSel = ($selectedIndex -eq $exitIdx)
        $exitPrefix = if ($exitSel) { "  > [" } else { "    [" }
        $exitLine = ($exitPrefix + ($exitIdx + 1) + "] Exit").PadRight($lineWidth)

        if ($exitSel) {
            [void]$sb.Append("${BG_CYAN}${FG_BLK}${exitLine}${C_RESET}")
        } else {
            [void]$sb.Append("${FG_WHITE}${exitLine}${C_RESET}")
        }

        # Wipe any leftover buffer lines below option menu
        [void]$sb.Append($C_CLEAR_BELOW)

        # Atomic flush to stdout
        [Console]::Write($sb.ToString())
    }

    [Console]::Clear()
    Update-DashboardOptionsCache
    Update-StatusCache
    $selectedIndex = 0

    while ($true) {
        Render-Dashboard -selectedIndex $selectedIndex

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $maxIndex = $script:OptionsCache.Count

        if ($key.VirtualKeyCode -in 16, 17, 18, 20, 91, 92) {
            continue
        }

        if ($key.VirtualKeyCode -eq 27) {
            $settingsScript = Join-Path $TargetDir "dashboard-settings.ps1"
            if (Test-Path $settingsScript) {
                [Console]::Clear()
                [Console]::CursorVisible = $true
                & $settingsScript -TargetDir $TargetDir
                [Console]::CursorVisible = $false
                [Console]::Clear()
                Update-DashboardOptionsCache
                Update-StatusCache
            }
            continue
        }

        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
            [Console]::Clear()
            [Console]::CursorVisible = $true
            exit
        }

        if ($key.Character -eq 'r' -or $key.Character -eq 'R') {
            Update-StatusCache
            [Console]::Clear()
            continue
        }

        $executeIndex = -1

        if ($key.VirtualKeyCode -eq 38 -or $key.Character -eq 'w' -or $key.Character -eq 'W') {
            $selectedIndex--
            if ($selectedIndex -lt 0) { $selectedIndex = $maxIndex }
            while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
            continue
        }

        if ($key.VirtualKeyCode -eq 40 -or $key.Character -eq 's' -or $key.Character -eq 'S') {
            $selectedIndex++
            if ($selectedIndex -gt $maxIndex) { $selectedIndex = 0 }
            while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
            continue
        }

        if ($key.VirtualKeyCode -eq 13) {
            $executeIndex = $selectedIndex
        }

        if ($executeIndex -eq -1 -and $key.Character -ge '1' -and $key.Character -le '9') {
            $num = [int]::Parse($key.Character.ToString()) - 1
            if ($num -le $maxIndex) {
                $executeIndex = $num
            }
        }

        if ($executeIndex -ne -1) {
            if ($executeIndex -eq $maxIndex) {
                [Console]::Clear()
                [Console]::CursorVisible = $true
                exit
            } else {
                [Console]::Clear()
                [Console]::CursorVisible = $true
                $targetOption = $script:OptionsCache[$executeIndex]
                
                Write-Host "================================================================" -ForegroundColor Cyan
                Write-Host " EXECUTING: $($targetOption.Title)" -ForegroundColor Yellow
                Write-Host "================================================================" -ForegroundColor Cyan
                Write-Host ""

                try {
                    & $targetOption.Execute
                } catch {
                    Write-Host "`n[ERROR] Failed to execute task: $_" -ForegroundColor Red
                } finally {
                    Write-Host ""
                    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
                    Write-Host "[COMPLETE] Process finished. Returning to dashboard..." -ForegroundColor Green
                    Start-Sleep -Milliseconds 1200
                    [Console]::CursorVisible = $false
                    [Console]::Clear()
                    Update-DashboardOptionsCache
                    Update-StatusCache
                }
            }
        }
    }
} catch {
    [Console]::CursorVisible = $true
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host " DASHBOARD FATAL ERROR DETECTED" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}