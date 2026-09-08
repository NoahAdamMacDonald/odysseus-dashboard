# ==============================================================================
# CREATE DASHBOARD DESKTOP SHORTCUT
# ==============================================================================

# Dynamically resolve root project folder
$projectRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($projectRoot)) {
    $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$targetPath   = Join-Path -Path $projectRoot -ChildPath "run-dashboard.bat"
$iconPath     = Join-Path -Path $projectRoot -ChildPath "dashboard-dependencies\icons\start-icon.ico"
$workingDir   = $projectRoot
$shortcutName = "Odysseus Dashboard.lnk"

# Resolve user's Desktop directory
$desktopFolder = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$shortcutPath  = Join-Path -Path $desktopFolder -ChildPath $shortcutName

# Verify target script exists
if (-not (Test-Path $targetPath)) {
    Write-Warning "Target batch file not found at: $targetPath"
}

try {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath       = $targetPath
    $shortcut.WorkingDirectory = $workingDir
    $shortcut.Description      = "Launch Odysseus Service Dashboard"

    if (Test-Path $iconPath) {
        $shortcut.IconLocation = $iconPath
    } else {
        Write-Warning "Icon file not found at $iconPath. Falling back to default executable icon."
    }

    $shortcut.Save()

    Write-Host "Successfully created desktop shortcut:" -ForegroundColor Green
    Write-Host " $shortcutPath" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to create desktop shortcut: $_"
}