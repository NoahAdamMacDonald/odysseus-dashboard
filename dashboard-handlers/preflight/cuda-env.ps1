# ==============================================================================
# TITLE: NVIDIA VENV DLL PATH INJECTOR
# Optional: Use if having errors with default odysseus CUDA
# ==============================================================================

# Load central configuration
$ConfigFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "dashboard-config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$rootDir = $Global:DashboardConfig.RootDir
$venvLib = Join-Path $rootDir "venv\Lib\site-packages\nvidia"

# Resolve existing venv CUDA/cuBLAS/cuDNN bin directories
$cudaPaths = @(
    (Join-Path $venvLib "cuda_runtime\bin"),
    (Join-Path $venvLib "cublas\bin"),
    (Join-Path $venvLib "cudnn\bin")
) | Where-Object { Test-Path $_ }

if ($cudaPaths.Count -gt 0) {
    Write-Host "`n  Injecting venv NVIDIA CUDA DLL paths into process PATH..." -ForegroundColor Cyan
    
    # Prepend paths to current process environment
    $prependStr = ($cudaPaths -join ";")
    if ($env:Path -notlike "*$prependStr*") {
        $env:Path = "$prependStr;$env:Path"
    }
}