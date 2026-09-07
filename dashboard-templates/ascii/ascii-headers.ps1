# ==============================================================================
# REUSABLE ASCII HEADER TEMPLATE MODULE
# ==============================================================================

# ==============================================================================
# ADD PATH : $asciiModule = Join-Path -Path $PSScriptRoot -ChildPath "dashboard-templates\ascii\ascii-headers.ps1"
# TEST PATH: 	if (Test-Path $asciiModule) {
#					. $asciiModule
#				} else {
#					Write-Warning "ASCII Header module not found at: $asciiModule"
#				}
# WRITE HEADER: Write-AsciiHeader -Name "<name>" -ForegroundColor <Colour>
# ==============================================================================

function global:Get-AsciiArtData {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    $cleanName = $Name.ToLower().Trim()

    # Map aliases to primary target filenames
    $aliases = @{
        "chroma"  = "chromadb"
        "sd"      = "stablediffusion"
        "dash"    = "dashboard"
        "db"      = "database"
        "net"     = "network"
        "config"  = "settings"
        "log"     = "logs"
        "cli"     = "terminal"
        "stats"   = "analytics"
        "system"  = "status"
    }

    if ($aliases.ContainsKey($cleanName)) {
        $cleanName = $aliases[$cleanName]
    }

    $headersDir = Join-Path -Path $PSScriptRoot -ChildPath "headers"
    $targetFile = Join-Path -Path $headersDir -ChildPath "$cleanName.txt"

    if (Test-Path -Path $targetFile) {
        return Get-Content -Path $targetFile
    }

    return @()
}

function global:Write-AsciiHeader {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Yellow,
        [ScriptBlock]$WriterScriptBlock = $null,
        [int]$Width = 0
    )

    $lines = Get-AsciiArtData -Name $Name
    if ($null -eq $lines -or $lines.Count -eq 0) { return }

    foreach ($line in $lines) {
        if ($null -ne $WriterScriptBlock) {
            & $WriterScriptBlock $line
        } else {
            if ($Width -gt 0) {
                Write-Host $line.PadRight($Width) -ForegroundColor $ForegroundColor
            } else {
                Write-Host $line -ForegroundColor $ForegroundColor
            }
        }
    }
}