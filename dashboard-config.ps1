# ==============================================================================
# CENTRAL SYSTEM CONFIGURATION
# ==============================================================================

$RootDir = $PSScriptRoot

$Global:DashboardConfig = @{
    RootDir    = $RootDir
    VenvPython = Join-Path $RootDir "venv\Scripts\python.exe"
    
    Services   = @{
        Odysseus        = @{ Name = "Odysseus App";        Port = 7000;  Host = "127.0.0.1"; NamedProcesses = @() }
        StableDiffusion = @{ Name = "Stable Diffusion";    Port = 8000;  Host = "127.0.0.1"; NamedProcesses = @() }
        ChromaDB        = @{ 
            Name        = "ChromaDB Service"
            Port        = 8100
            Host        = "127.0.0.1"
            ExePath     = Join-Path $RootDir "venv\Scripts\chroma.exe"
            DataPath    = Join-Path $RootDir "chroma_data"
            NamedProcesses = @()
        }
        Ollama          = @{ Name = "Ollama";              Port = 11434; Host = "127.0.0.1"; NamedProcesses = @("ollama", "ollama_llama_server") }
        ProtonBridge    = @{ Name = "Proton Mail Bridge";  Port = 1143;  Host = "127.0.0.1"; NamedProcesses = @("proton-bridge", "bridge") }
    }
}

# Helper to import config across nested directories
function Import-DashboardConfig {
    if (-not $Global:DashboardConfig) {
        $configPath = Get-ChildItem -Path $PSScriptRoot -Filter "dashboard-config.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($configPath) { . $configPath.FullName }
    }
}