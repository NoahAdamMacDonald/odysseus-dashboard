# ==============================================================================
# TEMPLATE: ONE-OFF TASK / UTILITY SCRIPT
# PURPOSE : Runs the Python portable generator and displays build status.
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME        : Create Portable
# 	LOCATION    : ..\dashboard-dependencies\create_portable.py
# 	PURPOSE     : Creates a portable odysseus launcher with the host machine IP autoset.
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

$OptionId       = "create-portable"
$TaskName       = "Create Portable Launcher"

$CreateScript   = Join-Path $cfg.RootDir "dashboard-dependencies\create_portable.py"
$StatusFile     = Join-Path $cfg.RootDir "portable.status"

# ==============================================================================

@{
    Id        = $OptionId
    Title     = $TaskName
    Order     = $OptionOrder

    GetState  = ({ "RUN" }).GetNewClosure()

    GetStatus = ({
        if (Test-Path $StatusFile) {
            try {
                $raw = Get-Content $StatusFile -Raw
                if ($raw) {
                    $parts = $raw.Trim().Split('|')
                    $state = $parts[0]
                    $time  = if ($parts.Count -ge 2) { $parts[1] } else { "Unknown" }
                    $info  = if ($parts.Count -ge 3) { $parts[2] } else { "" }

                    if ($state -eq "OK" -or $state -eq "SUCCESS" -or $state -eq "SYNCED") {
                        return @{
                            Text  = "  [ READY   ] Create Portable Launcher   (Last: $time | $info)"
                            Color = "Green"
                        }
                    } elseif ($state -eq "ERROR") {
                        return @{
                            Text  = "  [ FAILED  ] Create Portable Launcher   (Last: $time | $info)"
                            Color = "Red"
                        }
                    }
                }
            } catch {}
        }

        return @{
            Text  = "  [ READY   ] Create Portable Launcher   (Action Ready)"
            Color = "Cyan"
        }
    }).GetNewClosure()

    Execute   = ({
        if (Get-Command "Backup-OdysseusData" -ErrorAction SilentlyContinue) {
            Write-Host "`n  Backing up database and vector store..." -ForegroundColor DarkGray
            Backup-OdysseusData
        }

        if (Test-Path $CreateScript) {
            Write-Host "`n  Generating Portable Remote Package..." -ForegroundColor Cyan
            $pyExe = if ($cfg.VenvPython -and (Test-Path $cfg.VenvPython)) { $cfg.VenvPython } else { "python" }
            & "$pyExe" "$CreateScript"
        } else {
            Write-Host "`n  [ ERROR ] create_portable.py not found at $CreateScript" -ForegroundColor Red
        }

        Write-Host "`n  Press ANY KEY to return to dashboard..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }).GetNewClosure()
}