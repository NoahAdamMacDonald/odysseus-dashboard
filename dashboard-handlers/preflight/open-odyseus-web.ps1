# ==============================================================================
# TITLE: Open Odysseus Web UI
# ==============================================================================

# ==============================================================================
# ADDING NEW BROWSERS TO ODYSSEUS PREFLIGHT LAUNCHER
# ==============================================================================
# To add support for additional browsers
# update two sections in this script:
# 
# 1. REGISTRY DETECTION ARRAY (Line ~45):
#   Add the executable filename to the appropriate engine check.
#
#   * Chromium Engines (supports isolated --app mode & custom profile):
#     Add to the -in array:
#     if ($exeName -in @("msedge.exe", "chrome.exe", "brave.exe", "vivaldi.exe", "opera.exe", "arc.exe"))
#
#   * Firefox Engines (supports --new-window mode):
#     Convert the single match to an array check:
#     elseif ($exeName -in @("firefox.exe", "librewolf.exe", "floorp.exe", "zen.exe"))
#
# 2. FALLBACK SCAN MATRIX ($candidateBrowsers Array, Line ~58):
#   Add a new hashtable entry with the executable path and launch flags.
#
#   * Chromium-based template:
#     @{ Path = "$env:LOCALAPPDATA\Zen\zen.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" }
#
#  * Firefox-based template:
#     @{ Path = "C:\Program Files\LibreWolf\librewolf.exe"; Args = "--new-window $url" }
#
# 3. COMMON DEFAULT INSTALL PATHS (WINDOWS):
#   - Arc:       "$env:LOCALAPPDATA\Microsoft\WindowsApps\Arc.exe"
#   - LibreWolf: "C:\Program Files\LibreWolf\librewolf.exe"
#   - Floorp:    "$env:LOCALAPPDATA\Ablaze\Floorp\floorp.exe"
#   - Zen:       "$env:LOCALAPPDATA\Zen\zen.exe"
# ==============================================================================


if (-not $Global:DashboardConfig) {
    if (Get-Command Import-DashboardConfig -ErrorAction SilentlyContinue) {
        Import-DashboardConfig
    }
}

$svc = $Global:DashboardConfig.Services.Odysseus
$port = if ($svc) { $svc.Port } else { 7000 }
$rawHost = if ($svc) { $svc.Host } else { "127.0.0.1" }

# Map wildcard listener IP (0.0.0.0) to local loopback for browser routing
$browserHost = if ($rawHost -eq "0.0.0.0") { "127.0.0.1" } else { $rawHost }
$url = "http://${browserHost}:${port}"

# Persistent login session
$profileDir = "$env:LOCALAPPDATA\Odysseus\browser-profile"

# Poll port using loopback address until service accepts connections
$maxRetries = 20
while ($maxRetries -gt 0) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect("127.0.0.1", $port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(300, $false)) {
            $client.EndConnect($async)
            $client.Close()
            break
        }
    } catch {}
    finally { $client.Close() }
    Start-Sleep -Milliseconds 500
    $maxRetries--
}

# Detect Default Windows Browser from Registry
function Get-DefaultBrowserPath {
    try {
        $userChoice = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue
        if ($userChoice.ProgId) {
            $command = Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$($userChoice.ProgId)\shell\open\command" -ErrorAction SilentlyContinue
            if ($command.'(default)' -match '"([^"]+\.exe)"') {
                return $matches[1]
            }
        }
    } catch {}
    return $null
}

$defaultBrowser = Get-DefaultBrowserPath

# Attempt launching using default browser with isolated window parameters
if ($defaultBrowser -and (Test-Path $defaultBrowser)) {
    $exeName = [System.IO.Path]::GetFileName($defaultBrowser).ToLower()

    # Chromium-based default browsers (supports --app mode & process isolation)
    if ($exeName -in @("msedge.exe", "chrome.exe", "brave.exe", "vivaldi.exe", "opera.exe")) {
        Start-Process -FilePath $defaultBrowser -ArgumentList "--app=$url", "--user-data-dir=`"$profileDir`""
        return
    } 
    # Firefox default browser (supports --new-window mode)
    elseif ($exeName -eq "firefox.exe") {
        Start-Process -FilePath $defaultBrowser -ArgumentList "--new-window", $url
        return
    }
}

# Fallback scan for common browser installations
$candidateBrowsers = @(
    @{ Path = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\Program Files\Google\Chrome\Application\chrome.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "$env:LOCALAPPDATA\Programs\Opera\opera.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\Program Files\Mozilla Firefox\firefox.exe"; Args = "--new-window $url" }
)

foreach ($browser in $candidateBrowsers) {
    if (Test-Path $browser.Path) {
        Start-Process -FilePath $browser.Path -ArgumentList $browser.Args
        return
    }
}

# Final fallback to standard OS default launch
Start-Process $url