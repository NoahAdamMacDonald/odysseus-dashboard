# ==============================================================================
# MAIN ENGINE: OLLAMA MODEL MANAGER DASHBOARD OPTION
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME	   : ASCII Headers
# 	LOCATION   : "..\dashboard-templates\ascii\ascii-headers.ps1"
# 	PURPOSE	   : Stores ascii art to be used
# ==============================================================================


# Load Dashboard Configuration
$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

# Dynamically locate ASCII Header Template Module
if (-not (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue)) {
    $asciiModulePath = Join-Path $PSScriptRoot "..\..\dashboard-templates\ascii\ascii-headers.ps1"
    if (Test-Path $asciiModulePath) {
        . $asciiModulePath
    }
}

$cfg = $Global:DashboardConfig
$svc = $cfg.Services.Ollama

# Automatically load editor UI sub-modules relative to this script
$subDirPath = Join-Path $PSScriptRoot "sub"
if (Test-Path $subDirPath) {
    Get-ChildItem -Path $subDirPath -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$OptionId    = "manage-ollama-models"
$ViewTitle   = "Manage Ollama Models"

$TargetHost  = if ($svc -and $svc.Host) { $svc.Host } else { "127.0.0.1" }
$TargetPort  = if ($svc -and $svc.Port) { $svc.Port } else { 11434 }

function global:Get-OllamaExePath {
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return (Join-Path $env:LocalAppData "Programs\Ollama\ollama.exe")
}

$OllamaExe = Get-OllamaExePath

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function global:Write-PaddedLine {
    param (
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray,
        $BackgroundColor = $null,
        [int]$Width = 0
    )
    if ($Width -le 0) {
        try { $Width = [Console]::WindowWidth - 1 } catch { $Width = 79 }
    }
    if ($Width -lt 20) { $Width = 79 }

    if ($Text.Length -gt $Width) {
        $Text = $Text.Substring(0, $Width)
    } else {
        $Text = $Text.PadRight($Width)
    }

    if ($null -ne $BackgroundColor) {
        Write-Host $Text -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    } else {
        Write-Host $Text -ForegroundColor $ForegroundColor
    }
}

function global:Get-OllamaLocalState {
    param (
        [string]$HostName = "127.0.0.1",
        [int]$Port = 11434
    )

    try {
        $res = Invoke-RestMethod -Uri "http://${HostName}:${Port}/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
        $running = Invoke-RestMethod -Uri "http://${HostName}:${Port}/api/ps" -Method Get -TimeoutSec 3 -ErrorAction SilentlyContinue
        
        $runningDict = @{}
        if ($running -and $running.models) {
            foreach ($rm in $running.models) {
                $vramGB = if ($rm.size_vram) { [math]::Round($rm.size_vram / 1GB, 2) } else { [math]::Round($rm.size / 1GB, 2) }
                $runningDict[$rm.name] = $vramGB
            }
        }

        $totalBytes = 0
        $models = @()

        foreach ($m in $res.models) {
            $totalBytes += $m.size
            $sizeGB = [math]::Round($m.size / 1GB, 2)
            $isLoaded = $runningDict.ContainsKey($m.name)
            $vramUsed = if ($isLoaded) { $runningDict[$m.name] } else { 0 }

            $models += [PSCustomObject]@{
                Name          = $m.name
                SizeBytes     = $m.size
                SizeFormatted = "$sizeGB GB"
                Family        = $m.details.family
                ParamSize     = $m.details.parameter_size
                IsLoaded      = $isLoaded
                VramGB        = $vramUsed
            }
        }

        return @{
            ServiceOnline = $true
            TotalGB       = [math]::Round($totalBytes / 1GB, 2)
            Models        = $models
            Running       = $runningDict
        }
    } catch {
        return @{
            ServiceOnline = $false
            TotalGB       = 0
            Models        = @()
            Running       = @{}
        }
    }
}

function global:Get-OllamaOnlineLibrary {
    try {
        $req = Invoke-WebRequest -Uri "https://ollama.com/library" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $html = $req.Content
        
        $matches = [regex]::Matches($html, 'href="/library/([a-zA-Z0-9\.\-_]+)"[^>]*>([\s\S]*?)</a>')
        $library = [System.Collections.Generic.List[psobject]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new()

        if ($matches.Count -gt 0) {
            foreach ($m in $matches) {
                $slug = $m.Groups[1].Value
                $block = $m.Groups[2].Value
                if ($slug -and -not $seen.Contains($slug)) {
                    [void]$seen.Add($slug)
                    $sizeMatches = [regex]::Matches($block, '(\d+(\.\d+)?(M|B))', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    $sizes = @()
                    foreach ($sm in $sizeMatches) {
                        if (-not $sizes.Contains($sm.Value.ToUpper())) { $sizes += $sm.Value.ToUpper() }
                    }
                    $sizeTag = if ($sizes.Count -gt 0) { $sizes -join ', ' } else { "" }

                    $library.Add([PSCustomObject]@{ Slug = $slug; Size = $sizeTag })
                }
            }
        } else {
            $simpleMatches = [regex]::Matches($html, 'href="/library/([a-zA-Z0-9\.\-_]+)"')
            foreach ($m in $simpleMatches) {
                $slug = $m.Groups[1].Value
                if ($slug -and -not $seen.Contains($slug)) {
                    [void]$seen.Add($slug)
                    $library.Add([PSCustomObject]@{ Slug = $slug; Size = "" })
                }
            }
        }
        return $library
    } catch {
        return @(
            [PSCustomObject]@{ Slug = "llama3.3"; Size = "70b" },
            [PSCustomObject]@{ Slug = "llama3.2"; Size = "1b, 3b" },
            [PSCustomObject]@{ Slug = "llama3.1"; Size = "8b, 70b, 405b" },
            [PSCustomObject]@{ Slug = "qwen2.5"; Size = "0.5b - 72b" },
            [PSCustomObject]@{ Slug = "qwen2.5-coder"; Size = "0.5b - 32b" },
            [PSCustomObject]@{ Slug = "phi4"; Size = "14b" },
            [PSCustomObject]@{ Slug = "deepseek-r1"; Size = "1.5b - 671b" },
            [PSCustomObject]@{ Slug = "mistral"; Size = "7b" }
        )
    }
}

# ==============================================================================
# MAIN UI MANAGER
# ==============================================================================

function global:Show-OllamaModelManager {
    param (
        [string]$HostName = "127.0.0.1",
        [int]$Port = 11434
    )

    $needsDataFetch   = $true
    $hasFetchedOnline = $false

    $collapseInstalled = $false
    $collapseOnline    = $true   
    $onlineMode        = "PULL"  
    $filterText        = ""
    $onlineScrollPos   = 0

    $localState   = $null
    $onlineModels = @()

    $activeSection  = "INSTALLED" 
    $installedIndex = 0
    $onlineIndex    = 0
    $systemIndex    = 0

    $lastRenderLines = 0

    [Console]::CursorVisible = $false
    Clear-Host

    try {
        while ($true) {
            $w = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 79 }

            if ($needsDataFetch) {
                [Console]::SetCursorPosition(0, 0)
                Write-PaddedLine "   Checking local Ollama status..." -ForegroundColor Cyan -Width $w

                $localState = Get-OllamaLocalState -HostName $HostName -Port $Port

                # Automatically attempt to launch Ollama if offline
                if (-not $localState.ServiceOnline) {
                    [Console]::SetCursorPosition(0, 0)
                    Write-PaddedLine "   [ AUTO-START ] Ollama service is offline. Launching Ollama..." -ForegroundColor Cyan -Width $w

                    $ollamaExe = Get-OllamaExePath

                    if (Test-Path $ollamaExe) {
                        Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

                        if (Get-Command "Wait-ForPortOnline" -ErrorAction SilentlyContinue) {
                            Wait-ForPortOnline -port $Port -serviceName "Ollama Service" -maxSeconds 15
                        } else {
                            $elapsed = 0
                            while (-not (Test-PortFast -hostName $HostName -port $Port) -and ($elapsed -lt 15)) {
                                Start-Sleep -Seconds 1
                                $elapsed++
                            }
                        }

                        $localState = Get-OllamaLocalState -HostName $HostName -Port $Port
                    }
                }

                if (-not $localState.ServiceOnline) {
                    Clear-Host
                    Write-Host "`n   [ ERROR ] Failed to start Ollama service on port $Port." -ForegroundColor Red
                    Write-Host "   Please ensure Ollama is installed properly on your system." -ForegroundColor Yellow
                    Write-Host "`n   Press ENTER or ESC to return..." -ForegroundColor Gray
                    [void][Console]::ReadKey($true)
                    return
                }

                if (-not $collapseOnline -and -not $hasFetchedOnline) {
                    [Console]::SetCursorPosition(0, 0)
                    Write-PaddedLine "   Fetching online model library from ollama.com..." -ForegroundColor Cyan -Width $w
                    $onlineModels = Get-OllamaOnlineLibrary
                    $hasFetchedOnline = $true
                }

                $needsDataFetch = $false
                Clear-Host
            }

            $filteredOnline = if ($filterText) {
                @($onlineModels | Where-Object { $_.Slug -like "*$filterText*" })
            } else {
                @($onlineModels)
            }

            $installedModels = @($localState.Models)

            if ($installedModels.Count -eq 0 -and $activeSection -eq "INSTALLED") {
                if (-not $collapseOnline -and $filteredOnline.Count -gt 0) { $activeSection = "ONLINE"; $onlineIndex = 0 }
                else { $activeSection = "SYSTEM"; $systemIndex = 0 }
            }

            if ($installedIndex -ge $installedModels.Count) { $installedIndex = [math]::Max(0, $installedModels.Count - 1) }
            if ($onlineIndex -ge $filteredOnline.Count) { $onlineIndex = [math]::Max(0, $filteredOnline.Count - 1) }

            $maxVisibleOnline = if ($collapseInstalled) { 10 } else { 6 }
            if ($filteredOnline.Count -gt 0) {
                if ($onlineIndex -lt $onlineScrollPos) {
                    $onlineScrollPos = $onlineIndex
                } elseif ($onlineIndex -ge ($onlineScrollPos + $maxVisibleOnline)) {
                    $onlineScrollPos = $onlineIndex - $maxVisibleOnline + 1
                }
            } else {
                $onlineScrollPos = 0
            }

            # Frame Render
            $lineCount = 0
            [Console]::SetCursorPosition(0, 0)

            if (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue) {
                Write-AsciiHeader -Name "ollama" -ForegroundColor Yellow -WriterScriptBlock { param($line) Write-PaddedLine $line -ForegroundColor Yellow -Width $w }
                $lineCount += (Get-AsciiArtData -Name "ollama").Count
            }

            Write-PaddedLine "   ================================================================" -ForegroundColor DarkGray -Width $w; $lineCount++

            $stat1 = "   TOTAL DISK STORAGE:  $($localState.TotalGB) GB"
            Write-PaddedLine $stat1 -ForegroundColor Cyan -Width $w; $lineCount++

            if ($localState.Running.Count -gt 0) {
                $activeList = @()
                foreach ($key in $localState.Running.Keys) {
                    $activeList += "$key ($($localState.Running[$key]) GB VRAM)"
                }
                $vramStr = $activeList -join ", "
                Write-PaddedLine ("   ACTIVE IN VRAM:      " + $vramStr) -ForegroundColor Green -BackgroundColor Black -Width $w; $lineCount++
            } else {
                Write-PaddedLine "   ACTIVE IN VRAM:      None (VRAM clear / Idle)" -ForegroundColor DarkGray -Width $w; $lineCount++
            }

            Write-PaddedLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -Width $w; $lineCount++

            $instStatus = if ($collapseInstalled) { "[+] EXPAND (Press 'I')" } else { "[-] COLLAPSE (Press 'I')" }
            Write-PaddedLine "   [ INSTALLED MODELS ($($installedModels.Count)) ]  -- $instStatus" -ForegroundColor White -Width $w; $lineCount++

            if (-not $collapseInstalled) {
                if ($installedModels.Count -eq 0) {
                    Write-PaddedLine "     (No models installed locally)" -ForegroundColor DarkGray -Width $w; $lineCount++
                } else {
                    for ($i = 0; $i -lt $installedModels.Count; $i++) {
                        $m = $installedModels[$i]
                        $status = if ($m.IsLoaded) { "[*] ACTIVE IN VRAM ($($m.VramGB) GB) - [ENTER Unload]" } else { "[ ] ON DISK - [ENTER Load]" }
                        $paramTag = if ($m.ParamSize) { "($($m.ParamSize))" } else { "" }
                        $labelText = "$($m.Name.PadRight(22)) $($m.SizeFormatted.PadRight(8)) $($paramTag.PadRight(7)) $status"

                        if ($activeSection -eq "INSTALLED" -and $i -eq $installedIndex) {
                            $bg = if ($m.IsLoaded) { "Green" } else { "Cyan" }
                            Write-PaddedLine ("   > " + $labelText) -ForegroundColor Black -BackgroundColor $bg -Width $w; $lineCount++
                        } else {
                            if ($m.IsLoaded) {
                                Write-PaddedLine ("     " + $labelText) -ForegroundColor Green -Width $w; $lineCount++
                            } else {
                                Write-PaddedLine ("     " + $labelText) -ForegroundColor Gray -Width $w; $lineCount++
                            }
                        }
                    }
                }
            }

            $onlineStatus = if ($collapseOnline) { "[+] EXPAND (Press 'O')" } else { "[-] COLLAPSE (Press 'O')" }
            Write-PaddedLine "" -Width $w; $lineCount++
            Write-PaddedLine "   [ OLLAMA ONLINE REGISTRY ]  -- $onlineStatus" -ForegroundColor White -Width $w; $lineCount++

            if (-not $collapseOnline) {
                $modeTag = if ($onlineMode -eq "PULL") { "[MODE: PULL/INSTALL | Press 'M' for RUN]" } else { "[MODE: RUN DIRECT | Press 'M' for PULL]" }
                $filterTag = if ($filterText) { "FILTER: '$filterText' (Press 'C' Clear)" } else { "Press 'F' Search" }
                Write-PaddedLine "     $modeTag  --  $filterTag" -ForegroundColor DarkGray -Width $w; $lineCount++

                if (-not $hasFetchedOnline) {
                    Write-PaddedLine "     (Press 'O' or 'R' to load online models)" -ForegroundColor DarkGray -Width $w; $lineCount++
                } elseif ($filteredOnline.Count -eq 0) {
                    Write-PaddedLine "     (No matching online models found)" -ForegroundColor DarkGray -Width $w; $lineCount++
                } else {
                    $winStart = $onlineScrollPos
                    $winEnd   = [math]::Min($winStart + $maxVisibleOnline - 1, $filteredOnline.Count - 1)

                    if ($winStart -gt 0) {
                        Write-PaddedLine "     [^] -- ($winStart more above) --" -ForegroundColor DarkGray -Width $w; $lineCount++
                    }

                    for ($idx = $winStart; $idx -le $winEnd; $idx++) {
                        $item = $filteredOnline[$idx]
                        $slug = $item.Slug
                        $sizeTag = if ($item.Size) { " ($($item.Size))" } else { "" }
                        $installedMatch = $installedModels | Where-Object { $_.Name -like "$slug*" }
                        $instTag = if ($installedMatch) { " [INSTALLED]" } else { "" }
                        $actionPrefix = if ($onlineMode -eq "PULL") { "PULL:" } else { "RUN DIRECT:" }
                        $labelText = "$actionPrefix $slug$sizeTag$instTag"

                        if ($activeSection -eq "ONLINE" -and $idx -eq $onlineIndex) {
                            Write-PaddedLine ("   > " + $labelText) -ForegroundColor Black -BackgroundColor Cyan -Width $w; $lineCount++
                        } else {
                            $color = if ($onlineMode -eq "PULL") { "Yellow" } else { "Magenta" }
                            Write-PaddedLine ("     " + $labelText) -ForegroundColor $color -Width $w; $lineCount++
                        }
                    }

                    if ($winEnd -lt ($filteredOnline.Count - 1)) {
                        $rem = $filteredOnline.Count - 1 - $winEnd
                        Write-PaddedLine "     [v] -- ($rem more below) --" -ForegroundColor DarkGray -Width $w; $lineCount++
                    }
                }
            }

            Write-PaddedLine "" -Width $w; $lineCount++
            Write-PaddedLine "   [ SYSTEM ACTIONS ]" -ForegroundColor White -Width $w; $lineCount++
            $sysLabels = @("Pull Specific Tag (e.g. gpt-oss:20b, gemma4:26b)...", "Return to Main Dashboard")

            for ($s = 0; $s -lt $sysLabels.Count; $s++) {
                if ($activeSection -eq "SYSTEM" -and $s -eq $systemIndex) {
                    Write-PaddedLine ("   > " + $sysLabels[$s]) -ForegroundColor Black -BackgroundColor Cyan -Width $w; $lineCount++
                } else {
                    Write-PaddedLine ("     " + $sysLabels[$s]) -ForegroundColor White -Width $w; $lineCount++
                }
            }

            Write-PaddedLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -Width $w; $lineCount++
            Write-PaddedLine "   KEYS: [ESC] Back | [ENTER] Action | [E] Inspect/Edit | [DEL]/[X] Delete | [M] [I] [O] [F] [C]" -ForegroundColor DarkGray -Width $w; $lineCount++

            # Clear trailing lines if previous frame had more rows
            if ($lastRenderLines -gt $lineCount) {
                for ($cl = $lineCount; $cl -lt $lastRenderLines; $cl++) {
                    Write-PaddedLine "" -Width $w
                }
            }
            $lastRenderLines = $lineCount

            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            if ($key.VirtualKeyCode -eq 27) {
                Clear-Host
                return
            }

            if (($key.Character -eq 'e' -or $key.Character -eq 'E') -and $activeSection -eq "INSTALLED" -and $installedModels.Count -gt 0) {
                $selectedModel = $installedModels[$installedIndex]
                if (Get-Command Show-OllamaModelInspector -ErrorAction SilentlyContinue) {
                    Show-OllamaModelInspector -ModelName $selectedModel.Name -LocalState $localState
                }
                $needsDataFetch = $true
                Clear-Host
                continue
            }

            if (($key.VirtualKeyCode -eq 46 -or $key.Character -eq 'x' -or $key.Character -eq 'X') -and $activeSection -eq "INSTALLED" -and $installedModels.Count -gt 0) {
                $selectedModel = $installedModels[$installedIndex]
                [Console]::SetCursorPosition(0, [Console]::WindowHeight - 3)
                Write-PaddedLine "   [ CONFIRM DELETE ] Remove '$($selectedModel.Name)' from disk? (Y/N): " -ForegroundColor Red -Width $w
                $confirm = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
                
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    Clear-Host
                    Write-Host "`n   Deleting model $($selectedModel.Name)..." -ForegroundColor Red
                    ollama rm $selectedModel.Name
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "   Successfully removed model." -ForegroundColor Green
                    } else {
                        Write-Host "   Failed to remove model." -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                    }

                    if ($installedIndex -ge ($installedModels.Count - 1) -and $installedIndex -gt 0) {
                        $installedIndex--
                    }
                    
                    Start-Sleep -Milliseconds 800
                    $needsDataFetch = $true
                }
                Clear-Host
                continue
            }

            if ($key.Character -eq 'm' -or $key.Character -eq 'M') { $onlineMode = if ($onlineMode -eq "PULL") { "RUN" } else { "PULL" }; Clear-Host; continue }
            if ($key.Character -eq 'f' -or $key.Character -eq 'F') {
                Clear-Host
                [Console]::CursorVisible = $true
                Write-Host "`n   FILTER ONLINE MODEL REGISTRY" -ForegroundColor Cyan
                $searchInput = Read-Host "   Search"
                if ($searchInput -ne $null) {
                    $filterText = $searchInput.Trim()
                    $onlineIndex = 0
                    $onlineScrollPos = 0
                    if ($collapseOnline) {
                        $collapseOnline = $false
                        if (-not $hasFetchedOnline) { $needsDataFetch = $true }
                    }
                }
                [Console]::CursorVisible = $false
                Clear-Host
                continue
            }
            if ($key.Character -eq 'c' -or $key.Character -eq 'C') { $filterText = ""; $onlineIndex = 0; $onlineScrollPos = 0; Clear-Host; continue }
            if ($key.Character -eq 'i' -or $key.Character -eq 'I') {
                $collapseInstalled = -not $collapseInstalled
                if ($collapseInstalled -and $activeSection -eq "INSTALLED") {
                    if (-not $collapseOnline) { $activeSection = "ONLINE"; $onlineIndex = 0 }
                    else { $activeSection = "SYSTEM"; $systemIndex = 0 }
                }
                Clear-Host
                continue
            }
            if ($key.Character -eq 'o' -or $key.Character -eq 'O') {
                $collapseOnline = -not $collapseOnline
                if (-not $collapseOnline -and -not $hasFetchedOnline) {
                    $needsDataFetch = $true
                } elseif ($collapseOnline -and $activeSection -eq "ONLINE") {
                    $activeSection = "SYSTEM"
                    $systemIndex = 0
                }
                Clear-Host
                continue
            }
            if ($key.Character -eq 'r' -or $key.Character -eq 'R') { $needsDataFetch = $true; if (-not $collapseOnline) { $hasFetchedOnline = $false }; continue }

            switch ($key.VirtualKeyCode) {
                38 {
                    if ($activeSection -eq "INSTALLED") {
                        if ($installedIndex -gt 0) { $installedIndex-- }
                        else { $activeSection = "SYSTEM"; $systemIndex = $sysLabels.Count - 1 }
                    } elseif ($activeSection -eq "ONLINE") {
                        if ($onlineIndex -gt 0) { $onlineIndex-- }
                        else {
                            if (-not $collapseInstalled -and $installedModels.Count -gt 0) { $activeSection = "INSTALLED"; $installedIndex = $installedModels.Count - 1 }
                            else { $activeSection = "SYSTEM"; $systemIndex = $sysLabels.Count - 1 }
                        }
                    } elseif ($activeSection -eq "SYSTEM") {
                        if ($systemIndex -gt 0) { $systemIndex-- }
                        else {
                            if (-not $collapseOnline -and $filteredOnline.Count -gt 0) { $activeSection = "ONLINE"; $onlineIndex = $filteredOnline.Count - 1 }
                            elseif (-not $collapseInstalled -and $installedModels.Count -gt 0) { $activeSection = "INSTALLED"; $installedIndex = $installedModels.Count - 1 }
                        }
                    }
                }
                40 {
                    if ($activeSection -eq "INSTALLED") {
                        if ($installedIndex -lt ($installedModels.Count - 1)) { $installedIndex++ }
                        else {
                            if (-not $collapseOnline -and $filteredOnline.Count -gt 0) { $activeSection = "ONLINE"; $onlineIndex = 0 }
                            else { $activeSection = "SYSTEM"; $systemIndex = 0 }
                        }
                    } elseif ($activeSection -eq "ONLINE") {
                        if ($onlineIndex -lt ($filteredOnline.Count - 1)) { $onlineIndex++ }
                        else { $activeSection = "SYSTEM"; $systemIndex = 0 }
                    } elseif ($activeSection -eq "SYSTEM") {
                        if ($systemIndex -lt ($sysLabels.Count - 1)) { $systemIndex++ }
                        else {
                            if (-not $collapseInstalled -and $installedModels.Count -gt 0) { $activeSection = "INSTALLED"; $installedIndex = 0 }
                            elseif (-not $collapseOnline -and $filteredOnline.Count -gt 0) { $activeSection = "ONLINE"; $onlineIndex = 0 }
                        }
                    }
                }
                13 {
                    if ($activeSection -eq "INSTALLED" -and $installedModels.Count -gt 0) {
                        $selected = $installedModels[$installedIndex]
                        if ($selected.IsLoaded) {
                            [Console]::SetCursorPosition(0, [Console]::WindowHeight - 3)
                            Write-PaddedLine "   Unloading $($selected.Name) from VRAM..." -ForegroundColor Yellow -Width $w
                            ollama stop $selected.Name
                            Start-Sleep -Milliseconds 800
                        } else {
                            [Console]::SetCursorPosition(0, [Console]::WindowHeight - 3)
                            Write-PaddedLine "   Warming up $($selected.Name) in VRAM..." -ForegroundColor Green -Width $w
                            Start-Process -FilePath "ollama" -ArgumentList "run $($selected.Name) `"`"" -WindowStyle Hidden
                            Start-Sleep -Milliseconds 1200
                        }
                        $needsDataFetch = $true
                    } elseif ($activeSection -eq "ONLINE" -and $filteredOnline.Count -gt 0) {
                        $selectedOnline = $filteredOnline[$onlineIndex]
                        $targetSlug = $selectedOnline.Slug
                        Clear-Host
                        [Console]::CursorVisible = $true
                        if ($onlineMode -eq "PULL") {
                            Write-Host "`n   [ PULL MODEL ] Executing 'ollama pull $targetSlug'..." -ForegroundColor Cyan
                            ollama pull $targetSlug
                        } else {
                            Write-Host "`n   [ RUN MODEL ] Executing 'ollama run $targetSlug'..." -ForegroundColor Green
                            ollama run $targetSlug
                        }
                        Write-Host "`n   Press ANY KEY to return..." -ForegroundColor Gray
                        [void][Console]::ReadKey($true)
                        [Console]::CursorVisible = $false
                        $needsDataFetch = $true
                    } elseif ($activeSection -eq "SYSTEM") {
                        if ($systemIndex -eq 1) {
                            Clear-Host
                            return
                        } elseif ($systemIndex -eq 0) {
                            Clear-Host
                            [Console]::CursorVisible = $true
                            Write-Host "`n   PULL OLLAMA MODEL TAG" -ForegroundColor Cyan
                            $pullTag = Read-Host "   Enter Model Tag (e.g., llama3.3:70b, qwen2.5-coder:32b)"
                            if (-not [string]::IsNullOrWhiteSpace($pullTag)) {
                                Write-Host "`n   Executing 'ollama pull $pullTag'..." -ForegroundColor Yellow
                                ollama pull $pullTag.Trim()
                                Write-Host "`n   Press ANY KEY to return..." -ForegroundColor Gray
                                [void][Console]::ReadKey($true)
                            }
                            [Console]::CursorVisible = $false
                            $needsDataFetch = $true
                        }
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# ==============================================================================
# DASHBOARD REGISTRATION HASHTABLE
# ==============================================================================

@{
    Id        = $OptionId
    Title     = $ViewTitle
    Order     = $OptionOrder

    GetState  = ({ "OPEN" }).GetNewClosure()

    GetStatus = ({
        $online = try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect($TargetHost, $TargetPort, $null, $null)
            $wait = $async.AsyncWaitHandle.WaitOne(300, $false)
            if ($wait) { $tcp.EndConnect($async); $true } else { $false }
        } catch { $false } finally { if ($tcp) { $tcp.Close() } }

        $text = if ($online) { 
            "   [ ONLINE  ] $($ViewTitle.PadRight(25)) (Port $TargetPort Active)" 
        } else { 
            "   [ OFFLINE ] $($ViewTitle.PadRight(25)) (Port $TargetPort Inactive)" 
        }
        return @{ Text = $text; Color = if ($online) { "Cyan" } else { "DarkGray" } }
    }).GetNewClosure()

    Execute   = ({
        try {
            Show-OllamaModelManager -HostName $TargetHost -Port $TargetPort
        } finally {
            [Console]::CursorVisible = $true
            Clear-Host
        }
    }).GetNewClosure()
}