# ==============================================================================
# DASHBOARD MODULE & SETTINGS MANAGER
# PLACE : Root folder next to dashboard.ps1 (".\dashboard-settings.ps1")
# ==============================================================================
param(
    [string]$TargetDir = ""
)

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
}

$OrderFile    = Join-Path $TargetDir "order.json"
$ExcludeFiles = @("model-editor.ps1", "dashboard.ps1", "dashboard-settings.ps1")

$managedCategories = @(
    @{ Name = "Options"   ; Active = Join-Path $TargetDir "dashboard-options"            ; Disabled = Join-Path $TargetDir "dashboard-options-disabled" },
    @{ Name = "Preflight" ; Active = Join-Path $TargetDir "dashboard-handlers\preflight"  ; Disabled = Join-Path $TargetDir "dashboard-handlers\preflight-disabled" },
    @{ Name = "Postflight"; Active = Join-Path $TargetDir "dashboard-handlers\postflight" ; Disabled = Join-Path $TargetDir "dashboard-handlers\postflight-disabled" }
)

$modes = @("Options", "Preflight", "Postflight")
$currentModeIdx = 0

function Get-OrderMap {
    $map = @{
        "Options"   = @{}
        "Preflight"  = @{}
        "Postflight" = @{}
    }
    if (Test-Path $OrderFile) {
        try {
            $jsonObj = Get-Content -Path $OrderFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($jsonObj) {
                foreach ($cat in @("Options", "Preflight", "Postflight")) {
                    if ($jsonObj.psobject.Properties[$cat]) {
                        foreach ($prop in $jsonObj.$cat.psobject.Properties) {
                            $map[$cat][$prop.Name] = [int]$prop.Value
                        }
                    }
                }
            }
        } catch {}
    }
    return $map
}

function Save-OrderConfig ($moduleList) {
    $config = [ordered]@{
        "Options"   = [ordered]@{}
        "Preflight"  = [ordered]@{}
        "Postflight" = [ordered]@{}
    }

    foreach ($cat in @("Options", "Preflight", "Postflight")) {
        $catItems = @($moduleList | Where-Object { $_.Category -eq $cat })
        $idx = 1
        foreach ($item in $catItems) {
            $config[$cat][$item.Name] = $idx
            $idx++
        }
    }

    $config | ConvertTo-Json -Depth 3 | Set-Content -Path $OrderFile -Force
}

function Get-ScriptTitle ($fileInfo, $category) {
    $title = $fileInfo.Name
    if (-not (Test-Path $fileInfo.FullName)) { return $title }

    try {
        # Check top 15 lines for explicit '# TITLE:' header tag
        $topLines = Get-Content -Path $fileInfo.FullName -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $topLines) {
            if ($line -match '^\s*#\s*TITLE\s*:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }

        # NEVER execute Preflight or Postflight scripts to derive titles
        if ($category -eq "Options") {
            $output = & $fileInfo.FullName
            $validOpts = @($output | Where-Object { $_ -is [hashtable] -and $_.ContainsKey("Execute") })
            if ($validOpts.Count -gt 0) {
                $opt = $validOpts[0]
                if ($opt.Title -is [scriptblock]) {
                    $title = & $opt.Title
                } elseif ($opt.Title) {
                    $title = $opt.Title.ToString()
                }
            }
        }
    } catch {}
    return $title
}

function Get-AllModuleItems {
    $orderMap = Get-OrderMap
    $items = @()

    foreach ($cat in $managedCategories) {
        $catName = $cat.Name
        $catOrders = $orderMap[$catName]

        if (Test-Path $cat.Active) {
            Get-ChildItem -Path $cat.Active -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { -not $_.PSIsContainer -and $ExcludeFiles -notcontains $_.Name } | 
                ForEach-Object {
                    $ord = 999
                    if ($catOrders -and $null -ne $catOrders[$_.Name]) { $ord = [int]$catOrders[$_.Name] }
                    elseif ($catOrders -and $null -ne $catOrders[$_.BaseName]) { $ord = [int]$catOrders[$_.BaseName] }

                    $friendlyTitle = Get-ScriptTitle -fileInfo $_ -category $catName

                    $items += [PSCustomObject]@{
                        Name        = $_.Name
                        Title       = $friendlyTitle
                        Category    = $catName
                        IsEnabled   = $true
                        FullPath    = $_.FullName
                        ActiveDir   = $cat.Active
                        DisabledDir = $cat.Disabled
                        Order       = $ord
                    }
                }
        }

        if (Test-Path $cat.Disabled) {
            Get-ChildItem -Path $cat.Disabled -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { -not $_.PSIsContainer -and $ExcludeFiles -notcontains $_.Name } | 
                ForEach-Object {
                    $ord = 999
                    if ($catOrders -and $null -ne $catOrders[$_.Name]) { $ord = [int]$catOrders[$_.Name] }
                    elseif ($catOrders -and $null -ne $catOrders[$_.BaseName]) { $ord = [int]$catOrders[$_.BaseName] }

                    $friendlyTitle = Get-ScriptTitle -fileInfo $_ -category $catName

                    $items += [PSCustomObject]@{
                        Name        = $_.Name
                        Title       = $friendlyTitle
                        Category    = $catName
                        IsEnabled   = $false
                        FullPath    = $_.FullName
                        ActiveDir   = $cat.Active
                        DisabledDir = $cat.Disabled
                        Order       = $ord
                    }
                }
        }
    }
    return @($items | Sort-Object Category, Order, Name)
}

function Toggle-ModuleState ($item) {
    if ($item.IsEnabled) {
        if (-not (Test-Path $item.DisabledDir)) { New-Item -ItemType Directory -Path $item.DisabledDir -Force | Out-Null }
        $relPath = $item.FullPath.Substring($item.ActiveDir.Length)
        $destPath = Join-Path $item.DisabledDir $relPath
        $destParent = Split-Path -Parent $destPath
        if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
        Move-Item -Path $item.FullPath -Destination $destPath -Force
    } else {
        if (-not (Test-Path $item.ActiveDir)) { New-Item -ItemType Directory -Path $item.ActiveDir -Force | Out-Null }
        $relPath = $item.FullPath.Substring($item.DisabledDir.Length)
        $destPath = Join-Path $item.ActiveDir $relPath
        $destParent = Split-Path -Parent $destPath
        if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
        Move-Item -Path $item.FullPath -Destination $destPath -Force
    }
}

$selIndex = 0
[Console]::CursorVisible = $false
$modules = Get-AllModuleItems

while ($true) {
    Clear-Host
    $activeMode = $modes[$currentModeIdx]
    $visibleModules = @($modules | Where-Object { $_.Category -eq $activeMode })

    $totalCount = $visibleModules.Count
    $backIdx = $totalCount

    if ($selIndex -gt $backIdx) { $selIndex = $backIdx }

    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host "                    MODULE & SETTINGS MANAGER                     " -ForegroundColor Red
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host "  MODE: [$activeMode] (Press 'M' to Switch) | [W/S] Move | [ESC] Exit" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray

    if ($totalCount -eq 0) {
        Write-Host "  No modules found for current mode [$activeMode]." -ForegroundColor DarkGray
    } else {
        for ($i = 0; $i -lt $totalCount; $i++) {
            $mod = $visibleModules[$i]
            $isSel = ($i -eq $selIndex)
            
            $numStr = "[" + ($i + 1) + "] "
            $prefix = if ($isSel) { "  > " + $numStr } else { "    " + $numStr }
            
            $catTag = "[$($mod.Category)]".PadRight(13)
            $leftStr = ($prefix + $catTag + " " + $mod.Title).PadRight(60)
            $statusTag = if ($mod.IsEnabled) { "[ENABLED]" } else { "[DISABLED]" }
            
            if ($isSel) {
                $fg = if ($mod.IsEnabled) { "DarkGreen" } else { "DarkRed" }
                Write-Host $leftStr -NoNewline -ForegroundColor Black -BackgroundColor Cyan
                Write-Host $statusTag -ForegroundColor $fg -BackgroundColor Cyan
            } else {
                $fg = if ($mod.IsEnabled) { "Green" } else { "DarkGray" }
                Write-Host $leftStr -NoNewline -ForegroundColor White
                Write-Host $statusTag -ForegroundColor $fg
            }
        }
    }

    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    $backLine = if ($selIndex -eq $backIdx) { "  > [$($backIdx + 1)] Back to Dashboard" } else { "    [$($backIdx + 1)] Back to Dashboard" }
    if ($selIndex -eq $backIdx) {
        Write-Host $backLine -ForegroundColor Black -BackgroundColor Cyan
    } else {
        Write-Host $backLine -ForegroundColor White
    }

    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    if ($key.VirtualKeyCode -eq 27) { 
        Save-OrderConfig -moduleList $modules
        break 
    }

    if ($key.Character -eq 'm' -or $key.Character -eq 'M') {
        $currentModeIdx = ($currentModeIdx + 1) % $modes.Count
        $selIndex = 0
        continue
    }

    if ($key.Character -eq 'w' -or $key.Character -eq 'W') {
        if ($selIndex -gt 0 -and $selIndex -lt $totalCount) {
            $targetMod = $visibleModules[$selIndex]
            $prevMod = $visibleModules[$selIndex - 1]

            $idxA = [array]::IndexOf($modules, $targetMod)
            $idxB = [array]::IndexOf($modules, $prevMod)

            $temp = $modules[$idxA]
            $modules[$idxA] = $modules[$idxB]
            $modules[$idxB] = $temp

            $selIndex--
            Save-OrderConfig -moduleList $modules
        } else {
            $selIndex--
            if ($selIndex -lt 0) { $selIndex = $backIdx }
        }
        continue
    }

    if ($key.Character -eq 's' -or $key.Character -eq 'S') {
        if ($selIndex -lt ($totalCount - 1)) {
            $targetMod = $visibleModules[$selIndex]
            $nextMod = $visibleModules[$selIndex + 1]

            $idxA = [array]::IndexOf($modules, $targetMod)
            $idxB = [array]::IndexOf($modules, $nextMod)

            $temp = $modules[$idxA]
            $modules[$idxA] = $modules[$idxB]
            $modules[$idxB] = $temp

            $selIndex++
            Save-OrderConfig -moduleList $modules
        } else {
            $selIndex++
            if ($selIndex -gt $backIdx) { $selIndex = 0 }
        }
        continue
    }

    if ($key.VirtualKeyCode -eq 38) {
        $selIndex--
        if ($selIndex -lt 0) { $selIndex = $backIdx }
        continue
    }
    if ($key.VirtualKeyCode -eq 40) {
        $selIndex++
        if ($selIndex -gt $backIdx) { $selIndex = 0 }
        continue
    }

    if ($key.Character -ge '1' -and $key.Character -le '9') {
        $num = [int]::Parse($key.Character.ToString()) - 1
        if ($num -le $backIdx) { $selIndex = $num }
    }

    if ($key.VirtualKeyCode -eq 13 -or $key.VirtualKeyCode -eq 32) {
        if ($selIndex -eq $backIdx) { 
            Save-OrderConfig -moduleList $modules
            break 
        } else { 
            Toggle-ModuleState -item $visibleModules[$selIndex]
            $modules = Get-AllModuleItems
            Save-OrderConfig -moduleList $modules
        }
    }
}