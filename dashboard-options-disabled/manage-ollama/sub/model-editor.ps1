# ==============================================================================
# OLLAMA MODEL INSPECTOR & CONFIG TUNER MODULE
# PLACE : ..\manage-ollama\sub\model-editor.ps1
# ==============================================================================

# Ensure ASCII headers module is loaded if not already in session scope
if (-not (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue)) {
    $asciiModulePath = Join-Path $PSScriptRoot "..\..\dashboard-templates\ascii\ascii-headers.ps1"
    if (Test-Path $asciiModulePath) {
        . $asciiModulePath
    }
}

function global:Show-OllamaModelInspector {
    param (
        [string]$ModelName,
        [object]$LocalState
    )

    Clear-Host
    [Console]::CursorVisible = $false

    $rawShow = try { ollama show $ModelName 2>$null | Out-String } catch { "" }
    $rawModelfile = try { ollama show $ModelName --modelfile 2>$null | Out-String } catch { "" }

    $isLoaded = $LocalState.Running.ContainsKey($ModelName)
    $vramGB   = if ($isLoaded) { $LocalState.Running[$ModelName] } else { 0 }

    # Initialize empty — only populate parameters that actually exist in the Modelfile
    $params = [ordered]@{}

    if ($rawModelfile) {
        $lines = $rawModelfile -split "`r?\n"
        foreach ($line in $lines) {
            if ($line -match '^\s*PARAMETER\s+([a-zA-Z0-9_]+)\s+(.+)$') {
                $pKey = $matches[1]
                $pVal = $matches[2].Trim()
                $params[$pKey] = $pVal
            }
        }
    }

    $editIndex = 0
    $lastRenderLines = 0

    # Helper function to safely fit strings inside console window width
    function script:Write-SafeLine {
        param (
            [string]$Text,
            [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
            [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
        )
        $w = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 79 }
        if ($Text.Length -gt $w) {
            $Text = $Text.Substring(0, [Math]::Max(0, $w - 3)) + "..."
        }
        Write-Host $Text.PadRight($w) -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
        $script:lineCount++
    }

    while ($true) {
        $script:lineCount = 0
        $w = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 79 }
        [Console]::SetCursorPosition(0, 0)

        # Dynamic ASCII Header rendering using central ASCII module
        if (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue) {
            Write-AsciiHeader -Name "ollama" -ForegroundColor Yellow -WriterScriptBlock {
                param($line)
                script:Write-SafeLine $line -ForegroundColor Yellow
            }
        }
        script:Write-SafeLine "  ================================================================" -ForegroundColor DarkGray
        script:Write-SafeLine "  [ MODEL INSPECTOR & CONFIG TUNER ] -- $ModelName" -ForegroundColor Cyan
        script:Write-SafeLine "  ----------------------------------------------------------------" -ForegroundColor DarkGray

        if ($isLoaded) {
            script:Write-SafeLine "  STATUS:             ACTIVE IN VRAM ($vramGB GB VRAM allocated)" -ForegroundColor Black -BackgroundColor Green
        } else {
            script:Write-SafeLine "  STATUS:             Idle on Disk (Unloaded)" -ForegroundColor DarkGray
        }

        # Dynamic multi-line spec wrapper
        $rawSpecMatches = ($rawShow -split "`r?\n" | Where-Object { $_ -like "*architecture*" -or $_ -like "*parameter_count*" -or $_ -like "*quantization*" -or $_ -like "*context length*" })
        if ($rawSpecMatches) {
            $specItems = $rawSpecMatches.ForEach({ ($_.Trim() -replace '\s+', ' ') })
            $indent = "                      " # 22 spaces
            $label  = "  SPECS:              "
            
            $currentLine = ""
            $isFirstLine = $true
            
            foreach ($item in $specItems) {
                $candidate = if ($currentLine) { "$currentLine | $item" } else { $item }
                $prefix = if ($isFirstLine) { $label } else { $indent }
                
                if (($prefix.Length + $candidate.Length) -gt $w) {
                    if ($currentLine) {
                        script:Write-SafeLine "$prefix$currentLine" -ForegroundColor Gray
                        $isFirstLine = $false
                        $currentLine = $item
                    } else {
                        script:Write-SafeLine "$prefix$item" -ForegroundColor Gray
                        $isFirstLine = $false
                        $currentLine = ""
                    }
                } else {
                    $currentLine = $candidate
                }
            }
            if ($currentLine) {
                $prefix = if ($isFirstLine) { $label } else { $indent }
                script:Write-SafeLine "$prefix$currentLine" -ForegroundColor Gray
            }
        } else {
            script:Write-SafeLine "  SPECS:              Ollama Native Model" -ForegroundColor Gray
        }

        script:Write-SafeLine "  ----------------------------------------------------------------" -ForegroundColor DarkGray
        script:Write-SafeLine "  CONFIGURABLE PARAMETERS (Arrow Keys + ENTER to Edit):" -ForegroundColor White

        $paramKeys = @($params.Keys)
        if ($paramKeys.Count -eq 0) {
            script:Write-SafeLine "    (No custom parameters set in Modelfile. Press 'A' to add one)" -ForegroundColor DarkGray
        } else {
            if ($editIndex -ge $paramKeys.Count) { $editIndex = [math]::Max(0, $paramKeys.Count - 1) }

            for ($k = 0; $k -lt $paramKeys.Count; $k++) {
                $pName = $paramKeys[$k]
                $pVal  = $params[$pName]
                
                $desc = switch ($pName) {
                    "num_ctx"        { "(Context Window)" }
                    "num_predict"    { "(Max Output Tokens)" }
                    "temperature"    { "(Creativity Rate)" }
                    "top_p"          { "(Nucleus Sampling)" }
                    "top_k"          { "(Top-K Sampling)" }
                    "repeat_penalty" { "(Repeat Penalty)" }
                    default          { "(Custom Parameter)" }
                }

                $lineText = "$($pName.PadRight(18)) : $($pVal.PadRight(10)) $desc"

                if ($k -eq $editIndex) {
                    script:Write-SafeLine "  > $lineText" -ForegroundColor Black -BackgroundColor Cyan
                } else {
                    script:Write-SafeLine "    $lineText" -ForegroundColor Yellow
                }
            }
        }

        script:Write-SafeLine "  ----------------------------------------------------------------" -ForegroundColor DarkGray
        script:Write-SafeLine "  ACTIONS:" -ForegroundColor White
        script:Write-SafeLine "    [S] Save & Rebuild Model Overwrite" -ForegroundColor Green
        script:Write-SafeLine "    [A] Add Custom PARAMETER" -ForegroundColor Cyan
        script:Write-SafeLine "    [X / DEL] Delete Selected PARAMETER" -ForegroundColor Red
        script:Write-SafeLine "    [ESC] Cancel & Return" -ForegroundColor Gray

        script:Write-SafeLine "  ----------------------------------------------------------------" -ForegroundColor DarkGray
        script:Write-SafeLine "  KEYS: [UP/DN] Select | [ENTER] Edit | [A] Add | [X/DEL] Delete | [S] Save" -ForegroundColor DarkGray

        # Clear remaining buffer lines if previous frame had more rows
        if ($lastRenderLines -gt $script:lineCount) {
            for ($cl = $script:lineCount; $cl -lt $lastRenderLines; $cl++) {
                script:Write-SafeLine ""
            }
        }
        $lastRenderLines = $script:lineCount

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 27) { # ESC
            Clear-Host
            return
        }

        # Navigation
        if ($key.VirtualKeyCode -eq 38) { if ($editIndex -gt 0) { $editIndex-- }; continue } # Up
        if ($key.VirtualKeyCode -eq 40) { if ($editIndex -lt ($paramKeys.Count - 1)) { $editIndex++ }; continue } # Down

        # Edit Value
        if ($key.VirtualKeyCode -eq 13 -and $paramKeys.Count -gt 0) { # ENTER
            $selectedKey = $paramKeys[$editIndex]
            Clear-Host
            [Console]::CursorVisible = $true
            Write-Host "`n  EDIT PARAMETER: $selectedKey" -ForegroundColor Cyan
            Write-Host "  Current Value: $($params[$selectedKey])" -ForegroundColor Gray
            $newVal = Read-Host "  Enter New Value (Press ENTER to leave unchanged)"
            if (-not [string]::IsNullOrWhiteSpace($newVal)) {
                $params[$selectedKey] = $newVal.Trim()
            }
            [Console]::CursorVisible = $false
            Clear-Host
            continue
        }

        # Add Parameter
        if ($key.Character -eq 'a' -or $key.Character -eq 'A') {
            Clear-Host
            [Console]::CursorVisible = $true
            Write-Host "`n  ADD CUSTOM PARAMETER" -ForegroundColor Cyan
            $customKey = Read-Host "  Parameter Name (e.g. num_ctx, repeat_penalty, top_k)"
            if (-not [string]::IsNullOrWhiteSpace($customKey)) {
                $customVal = Read-Host "  Parameter Value"
                if (-not [string]::IsNullOrWhiteSpace($customVal)) {
                    $params[$customKey.Trim()] = $customVal.Trim()
                }
            }
            [Console]::CursorVisible = $false
            Clear-Host
            continue
        }

        # Delete Parameter (Supports Delete key or X)
        if (($key.VirtualKeyCode -eq 46 -or $key.Character -eq 'x' -or $key.Character -eq 'X') -and $paramKeys.Count -gt 0) {
            $keyToRemove = $paramKeys[$editIndex]
            $params.Remove($keyToRemove)
            if ($editIndex -ge $params.Count -and $editIndex -gt 0) {
                $editIndex--
            }
            Clear-Host
            continue
        }

        # Save and Recompile Model
        if ($key.Character -eq 's' -or $key.Character -eq 'S') {
            Clear-Host
            [Console]::CursorVisible = $true
            Write-Host "`n  [ REBUILDING MODEL ] Updating '$ModelName' parameters..." -ForegroundColor Cyan

            $modelfileLines = @("FROM $ModelName")
            foreach ($pKey in $params.Keys) {
                $modelfileLines += "PARAMETER $pKey $($params[$pKey])"
            }

            $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "Ollama_Modelfile_$([Guid]::NewGuid().ToString('N')).txt")
            Set-Content -Path $tempPath -Value $modelfileLines -Encoding UTF8

            Write-Host "`n  Executing 'ollama create $ModelName -f ...'" -ForegroundColor Yellow
            ollama create $ModelName -f $tempPath

            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n  [ SUCCESS ] Model '$ModelName' recompiled with new settings!" -ForegroundColor Green
            } else {
                Write-Host "`n  [ ERROR ] Failed to update model '$ModelName'." -ForegroundColor Red
            }

            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            }

            Write-Host "`n  Press ANY KEY or ESC to return..." -ForegroundColor Gray
            [Console]::CursorVisible = $false
            [void][Console]::ReadKey($true)
            Clear-Host
            return
        }
    }
}