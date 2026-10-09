import os
import json
import socket
import datetime

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def main():
    dep_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(dep_dir, ".."))
    output_dir = os.path.join(root_dir, "portable-odysseus")
    status_file = os.path.join(root_dir, "portable.status")

    try:
        os.makedirs(output_dir, exist_ok=True)

        ip = get_local_ip()
        port = 7000

        # Write portable-config.json
        config_data = {
            "DefaultHostIP": ip,
            "CurrentHostIP": ip,
            "Port": port
        }
        with open(os.path.join(output_dir, "portable-config.json"), "w", encoding="utf-8") as f:
            json.dump(config_data, f, indent=2)

        # Write run-remote.bat
        bat_content = "@echo off\r\npowershell -ExecutionPolicy Bypass -File \"%~dp0open-remote.ps1\"\r\n"
        with open(os.path.join(output_dir, "run-remote.bat"), "w", encoding="utf-8") as f:
            f.write(bat_content)

        # Write open-remote.ps1
        ps_script = '''# ==============================================================================
# TITLE: PORTABLE ODYSSEUS REMOTE LAUNCHER
# ==============================================================================

$configPath = Join-Path $PSScriptRoot "portable-config.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Config file missing!" -ForegroundColor Red
    pause
    exit
}
function Get-Config { Get-Content $configPath | ConvertFrom-Json }
function Save-Config ($cfg) { $cfg | ConvertTo-Json | Set-Content $configPath -Encoding UTF8 }
$config = Get-Config

function Show-IPMenu {
    param([string]$message = "")
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "         ODYSSEUS REMOTE LAUNCH CONFIG           " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Default Assigned IP : $($config.DefaultHostIP)" -ForegroundColor Gray
    Write-Host " Current Target IP   : $($config.CurrentHostIP)" -ForegroundColor Yellow
    Write-Host " Target Port         : $($config.Port)" -ForegroundColor Gray
    if ($message) { Write-Host "`n $message" -ForegroundColor Red }
    Write-Host "`n [1] Connect using Current IP ($($config.CurrentHostIP))"
    Write-Host " [2] Change Target IP Address"
    Write-Host " [3] Reset Target IP to Original Assigned IP ($($config.DefaultHostIP))"
    Write-Host " [Q] Quit"
    $choice = Read-Host "`n Select an option"
    switch ($choice) {
        "1" { return }
        "2" {
            $newIP = Read-Host "`n Enter new Host IP Address"
            if ($newIP -match "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$") {
                $config.CurrentHostIP = $newIP
                Save-Config $config
                Write-Host " IP updated to $newIP" -ForegroundColor Green
                Start-Sleep -Seconds 1
            } else {
                Show-IPMenu "Invalid IP format provided."
            }
        }
        "3" {
            $config.CurrentHostIP = $config.DefaultHostIP
            Save-Config $config
            Write-Host " IP reset to default ($($config.DefaultHostIP))" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        "Q" { exit }
        "q" { exit }
        default { Show-IPMenu "Invalid selection." }
    }
}

Write-Host "Connecting to Odysseus at http://$($config.CurrentHostIP):$($config.Port)..." -ForegroundColor Cyan
Write-Host "Press [M] within 2 seconds to open IP configuration menu..." -ForegroundColor DarkGray
$timeout = 20
while ($timeout -gt 0) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.Key -eq "M") {
            Show-IPMenu
            break
        }
    }
    Start-Sleep -Milliseconds 100
    $timeout--
}

function Test-ServerConnection ($ip, $port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ip, $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(800, $false)) {
            $client.Close()
            return $false
        }
        $client.EndConnect($async)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-ServerConnection -ip $config.CurrentHostIP -port $config.Port)) {
    Show-IPMenu "Unable to connect to $($config.CurrentHostIP):$($config.Port). Please check IP or host status."
}

$url = "http://$($config.CurrentHostIP):$($config.Port)"
$profileDir = "$env:TEMP\\odysseus-app-profile"

function Get-DefaultBrowserPath {
    try {
        $userChoice = Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\http\\UserChoice" -ErrorAction SilentlyContinue
        if ($userChoice.ProgId) {
            $command = Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\\$($userChoice.ProgId)\\shell\\open\\command" -ErrorAction SilentlyContinue
            if ($command."(default)" -match '"([^"]+\\.exe)"') {
                return $matches[1]
            }
        }
    } catch {}
    return $null
}

$defaultBrowser = Get-DefaultBrowserPath
if ($defaultBrowser -and (Test-Path $defaultBrowser)) {
    $exeName = [System.IO.Path]::GetFileName($defaultBrowser).ToLower()
    if ($exeName -in @("msedge.exe", "chrome.exe", "brave.exe", "vivaldi.exe", "opera.exe")) {
        Start-Process -FilePath $defaultBrowser -ArgumentList "--app=$url", "--user-data-dir=`"$profileDir`""
        exit
    } elseif ($exeName -eq "firefox.exe") {
        Start-Process -FilePath $defaultBrowser -ArgumentList "--new-window", $url
        exit
    }
}

$candidateBrowsers = @(
    @{ Path = "C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "$env:LOCALAPPDATA\\Programs\\Opera\\opera.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "$env:LOCALAPPDATA\\Vivaldi\\Application\\vivaldi.exe"; Args = "--app=$url --user-data-dir=`"$profileDir`"" },
    @{ Path = "C:\\Program Files\\Mozilla Firefox\\firefox.exe"; Args = "--new-window $url" }
)

foreach ($browser in $candidateBrowsers) {
    if (Test-Path $browser.Path) {
        Start-Process -FilePath $browser.Path -ArgumentList $browser.Args
        exit
    }
}

Start-Process $url
'''
        with open(os.path.join(output_dir, "open-remote.ps1"), "w", encoding="utf-8") as f:
            f.write(ps_script)

        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        with open(status_file, "w", encoding="utf-8") as f:
            f.write(f"OK|{now_str}|IP: {ip}")

        print(f"\n  [ SUCCESS ] Portable package created at: {output_dir}")
        print(f"              Assigned Host IP: {ip}:{port}")

    except Exception as e:
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        try:
            with open(status_file, "w", encoding="utf-8") as f:
                f.write(f"ERROR|{now_str}|{str(e)}")
        except Exception:
            pass
        print(f"\n  [ ERROR ] Failed to generate portable package: {e}")

if __name__ == "__main__":
    main()