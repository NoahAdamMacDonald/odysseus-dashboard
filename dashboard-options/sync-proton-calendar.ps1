# ==============================================================================
# TEMPLATE: ONE-OFF TASK / UTILITY SCRIPT
# PURPOSE : Runs the Python calendar sync script and displays last sync status.
# ==============================================================================

# ==============================================================================
# DEPENDENCIES : 
# 	NAME        : Python Virtual Environment Executable
# 	LOCATION    : ..\venv\Scripts\python.exe
# 	PURPOSE     : Provides Python runtime with icalendar and recurring_ical_events packages.
#
# 	NAME        : Proton Calendar Sync Engine
# 	LOCATION    : ..\dashboard-dependencies\sync_proton.py
# 	PURPOSE     : Fetches Proton/Google ICS feeds, parses recurring events, and updates app.db.
#
# 	NAME        : Odysseus Application Database
# 	LOCATION    : ..\data\app.db (or app root directory)
# 	PURPOSE     : Target SQLite database storing calendar_events entries for display.
# ==============================================================================

# ==============================================================================
# Configuration
# ==============================================================================

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$cfg = $Global:DashboardConfig

$OptionId       = "sync-proton-calendar"
$TaskName       = "Sync Proton Calendar"

$SyncScript     = Join-Path $cfg.RootDir "dashboard-dependencies\sync_proton.py"
$SyncStatusFile = Join-Path $cfg.RootDir "proton_sync.status"

# ==============================================================================

@{
    Id        = $OptionId
    Title     = $TaskName
    Order     = $OptionOrder

    GetState  = ({ "RUN" }).GetNewClosure()

    GetStatus = ({
        if (Test-Path $SyncStatusFile) {
            try {
                $raw = Get-Content $SyncStatusFile -Raw
                if ($raw) {
                    $parts = $raw.Trim().Split('|')
                    $state = $parts[0]
                    $time  = if ($parts.Count -ge 2) { $parts[1] } else { "Unknown" }
                    $info  = if ($parts.Count -ge 3) { $parts[2] } else { "" }

                    if ($state -eq "OK" -or $state -eq "SYNCED") {
                        return @{
                            Text  = "  [ SYNCED  ] Proton Calendar           (Last: $time | $info)"
                            Color = "Green"
                        }
                    } elseif ($state -eq "ERROR") {
                        return @{
                            Text  = "  [ FAILED  ] Proton Calendar           (Last: $time | $info)"
                            Color = "Red"
                        }
                    }
                }
            } catch {}
        }

        return @{
            Text  = "  [ UNKNOWN ] Proton Calendar           (No sync history)"
            Color = "DarkGray"
        }
    }).GetNewClosure()

    Execute   = ({
        if (Get-Command "Backup-OdysseusData" -ErrorAction SilentlyContinue) {
            Write-Host "`n  Backing up database and vector store..." -ForegroundColor DarkGray
            Backup-OdysseusData
        }

        if (Test-Path $SyncScript) {
            Write-Host "`n  Executing Proton Calendar Sync..." -ForegroundColor Cyan
            & "$($cfg.VenvPython)" "$SyncScript"
        } else {
            Write-Host "`n  [ ERROR ] sync_proton.py not found at $SyncScript" -ForegroundColor Red
        }

        Write-Host "`n  Press ANY KEY to return to dashboard..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }).GetNewClosure()
}