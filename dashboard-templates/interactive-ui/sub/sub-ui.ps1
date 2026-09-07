# ==============================================================================
# TEMPLATE: INTERACTIVE SUB-UI / INSPECTOR MODULE
# PURPOSE : Secondary full-screen editor/inspector modal triggered by the main
#           interactive dashboard for detailed item inspection and editing.
# PLACE   : Place at "..\dashboard-options\<option-name>\sub\sub-ui.ps1"
# ==============================================================================

# Ensure ASCII headers module is available in session scope
if (-not (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue)) {
    $asciiModulePath = Join-Path $PSScriptRoot "..\..\..\dashboard-templates\ascii\ascii-headers.ps1"
    if (Test-Path $asciiModulePath) { . $asciiModulePath }
}

function global:Show-ItemInspector {
    param (
        [PSCustomObject]$Item,
        [hashtable]$ContextState = @{}
    )

    if ($null -eq $Item) { return }

    # Convert object properties into an editable key-value hashtable
    $properties = [ordered]@{}
    $Item.PSObject.Properties | ForEach-Object {
        $properties[$_.Name] = [string]$_.Value
    }

    $editIndex       = 0
    $lastRenderLines = 0

    [Console]::CursorVisible = $false
    Clear-Host

    try {
        while ($true) {
            $lineCount = 0
            $w = try { [Math]::Max(80, [Console]::WindowWidth - 1) } catch { 79 }
            [Console]::SetCursorPosition(0, 0)

            # Header Render
            if (Get-Command Write-AsciiHeader -ErrorAction SilentlyContinue) {
                Write-AsciiHeader -Name "inspector" -ForegroundColor Yellow -WriterScriptBlock {
                    param($line)
                    Write-SafeLine $line -ForegroundColor Yellow -LineCounter ([ref]$lineCount)
                }
            } else {
                Write-SafeLine "   === ITEM INSPECTOR ===" -ForegroundColor Yellow -LineCounter ([ref]$lineCount)
            }

            Write-SafeLine "   ================================================================" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)
            Write-SafeLine "   [ INSPECTOR & CONFIG TUNER ] -- Item ID: $($Item.Id)" -ForegroundColor Cyan -LineCounter ([ref]$lineCount)
            Write-SafeLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)

            $propKeys = @($properties.Keys)

            # Dynamic Parameter List Rendering
            if ($propKeys.Count -eq 0) {
                Write-SafeLine "     (No configurable parameters found. Press 'A' to add one)" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)
            } else {
                if ($editIndex -ge $propKeys.Count) { $editIndex = [Math]::Max(0, $propKeys.Count - 1) }

                for ($k = 0; $k -lt $propKeys.Count; $k++) {
                    $pKey = $propKeys[$k]
                    $pVal = $properties[$pKey]
                    $lineText = "$($pKey.PadRight(18)) : $($pVal.PadRight(20))"

                    if ($k -eq $editIndex) {
                        Write-SafeLine "   > $lineText" -ForegroundColor Black -BackgroundColor Cyan -LineCounter ([ref]$lineCount)
                    } else {
                        Write-SafeLine "     $lineText" -ForegroundColor White -LineCounter ([ref]$lineCount)
                    }
                }
            }

            Write-SafeLine "" -LineCounter ([ref]$lineCount)
            Write-SafeLine "   ----------------------------------------------------------------" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)
            Write-SafeLine "   ACTIONS:" -ForegroundColor White -LineCounter ([ref]$lineCount)
            Write-SafeLine "     [ENTER] Edit Property | [A] Add Custom Property" -ForegroundColor Cyan -LineCounter ([ref]$lineCount)
            Write-SafeLine "     [X / DEL] Remove Property | [S] Save Changes | [ESC] Cancel & Return" -ForegroundColor DarkGray -LineCounter ([ref]$lineCount)

            # Buffer Overwrite Cleanup
            if ($lastRenderLines -gt $lineCount) {
                for ($cl = $lineCount; $cl -lt $lastRenderLines; $cl++) {
                    Write-SafeLine "" -LineCounter ([ref]$null)
                }
            }
            $lastRenderLines = $lineCount

            # Keyboard Input Handler
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            # ESC: Return to Main TUI
            if ($key.VirtualKeyCode -eq 27) {
                Clear-Host
                return
            }

            # Navigation
            if ($key.VirtualKeyCode -eq 38 -and $editIndex -gt 0) { $editIndex--; continue }
            if ($key.VirtualKeyCode -eq 40 -and $editIndex -lt ($propKeys.Count - 1)) { $editIndex++; continue }

            # Edit Selected Property
            if ($key.VirtualKeyCode -eq 13 -and $propKeys.Count -gt 0) {
                $selectedKey = $propKeys[$editIndex]
                Clear-Host
                [Console]::CursorVisible = $true
                Write-Host "`n   EDIT PROPERTY: $selectedKey" -ForegroundColor Cyan
                Write-Host "   Current Value: $($properties[$selectedKey])" -ForegroundColor Gray
                $newVal = Read-Host "   Enter New Value (Press ENTER to leave unchanged)"
                
                if (-not [string]::IsNullOrWhiteSpace($newVal)) {
                    $properties[$selectedKey] = $newVal.Trim()
                }
                [Console]::CursorVisible = $false
                Clear-Host
                continue
            }

            # Add New Property
            if ($key.Character -eq 'a' -or $key.Character -eq 'A') {
                Clear-Host
                [Console]::CursorVisible = $true
                Write-Host "`n   ADD CUSTOM PROPERTY" -ForegroundColor Cyan
                $newKey = Read-Host "   Property Key Name"
                if (-not [string]::IsNullOrWhiteSpace($newKey)) {
                    $newVal = Read-Host "   Property Value"
                    $properties[$newKey.Trim()] = $newVal.Trim()
                }
                [Console]::CursorVisible = $false
                Clear-Host
                continue
            }

            # Delete Property
            if (($key.VirtualKeyCode -eq 46 -or $key.Character -eq 'x' -or $key.Character -eq 'X') -and $propKeys.Count -gt 0) {
                $keyToRemove = $propKeys[$editIndex]
                $properties.Remove($keyToRemove)
                if ($editIndex -ge $properties.Count -and $editIndex -gt 0) { $editIndex-- }
                Clear-Host
                continue
            }

            # Save Changes back to Target Object
            if ($key.Character -eq 's' -or $key.Character -eq 'S') {
                Clear-Host
                [Console]::CursorVisible = $true
                Write-Host "`n   [ SAVING CHANGES ] Updating item state..." -ForegroundColor Cyan

                foreach ($k in $properties.Keys) {
                    if ($Item.PSObject.Properties[$k]) {
                        $Item.$k = $properties[$k]
                    } else {
                        $Item | Add-Member -NotePropertyName $k -NotePropertyValue $properties[$k] -Force
                    }
                }

                Start-Sleep -Milliseconds 600
                Write-Host "   [ SUCCESS ] Changes saved!" -ForegroundColor Green
                Start-Sleep -Milliseconds 600
                Clear-Host
                return
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}