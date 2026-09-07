# ==============================================================================
# TITLE: PURGE TEMPORARY FILES
# ==============================================================================

$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$rootDir = $Global:DashboardConfig.RootDir

$totalCount = 0
$totalBytes = 0

# Collect target directories and files
$targets = @()
$targets += Get-ChildItem -Path $rootDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path $env:TEMP -Filter "odysseus*" -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path $env:TEMP -Filter "pip-*" -ErrorAction SilentlyContinue

# Calculate file metrics and purge items
foreach ($item in $targets) {
    if (Test-Path $item.FullName) {
        if ($item.PSIsContainer) {
            $files = Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue
            if ($files) {
                $fileStats = $files | Measure-Object -Property Length -Sum
                $totalCount += $fileStats.Count
                if ($fileStats.Sum) {
                    $totalBytes += $fileStats.Sum
                }
            }
        } else {
            $totalCount += 1
            $totalBytes += $item.Length
        }
        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Format byte size to human-readable string
$formattedSize = if ($totalBytes -ge 1GB) {
    "{0:N2} GB" -f ($totalBytes / 1GB)
} elseif ($totalBytes -ge 1MB) {
    "{0:N2} MB" -f ($totalBytes / 1MB)
} elseif ($totalBytes -ge 1KB) {
    "{0:N2} KB" -f ($totalBytes / 1KB)
} else {
    "$totalBytes Bytes"
}

# Output result summary
if ($totalCount -gt 0) {
    Write-Host "`n  -> Purged $totalCount files ($formattedSize freed)." -ForegroundColor Green
} else {
    Write-Host "`n  -> No temporary files to purge." -ForegroundColor DarkGray
}