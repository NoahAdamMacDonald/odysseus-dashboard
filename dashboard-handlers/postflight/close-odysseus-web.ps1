# ==============================================================================
# TITLE: Close Odysseus Web UI
# ==============================================================================

if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Odysseus
$targetPort = if ($svc) { $svc.Port } else { 7000 }

# Only target web browser processes to protect the terminal console running the dashboard
$browserNames = @("msedge", "chrome", "firefox", "brave", "opera", "vivaldi")

Get-Process -Name $browserNames -ErrorAction SilentlyContinue | Where-Object { 
    $_.MainWindowTitle -like "*Odysseus*" -or $_.MainWindowTitle -like "*$targetPort*"
} | ForEach-Object {
    [void]$_.CloseMainWindow()
}