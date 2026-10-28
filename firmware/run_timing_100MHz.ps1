param(
    [string] $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin",
    [string] $OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$timingRepo = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot ("build/impl100_pipeline_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$timingOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$timingRtl = Join-Path $timingRepo "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
$timingSnapshot = Join-Path $timingOutput "inputs"
New-Item -ItemType Directory -Force -Path $timingSnapshot | Out-Null
$timingFiles = @("picorv32.v", "parallel.v", "soc_axi_top.v", "axi_uart_slave.v",
    "axi_spi_slave.v", "axi_i2c_slave.v", "CNN.v", "cnn_memory_subsystem.v",
    "cnn_docx_reference.v", "dma32_to_rgb24.v", "picorv32_axi4_bram_adapter.v",
    "axi4_bram_slave.v", "soc_top.v", "conv1_rgb_weight.mem", "conv2_weight.mem",
    "conv3_weight.mem", "fc_weight.mem", "firmware.hex")
foreach ($timingName in $timingFiles) {
    Copy-Item -LiteralPath (Join-Path $timingRtl $timingName) -Destination $timingSnapshot
}
Copy-Item -LiteralPath (Join-Path $timingRepo "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/constrs_1/new/soc_top_board.xdc") -Destination $timingSnapshot
Copy-Item -LiteralPath (Join-Path $timingRepo "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/constrs_1/new/soc_top_100MHz.xdc") -Destination $timingSnapshot
Copy-Item -LiteralPath (Join-Path $timingSnapshot "firmware.hex") -Destination $timingOutput
Get-ChildItem -LiteralPath $timingSnapshot -File | Get-FileHash | Select-Object Path,Hash |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $timingOutput "inputs_sha256.json")
$timingTcl = Join-Path $PSScriptRoot "run_timing_100MHz.tcl"
Push-Location $timingOutput
try {
    & (Join-Path $VivadoBin "vivado.bat") -mode batch -nojournal -log timing100.log -source $timingTcl
    if ($LASTEXITCODE -ne 0) { throw "Vivado failed ($LASTEXITCODE); inspect $timingOutput/timing100.log" }
    Write-Output "Timing output: $timingOutput"
} finally { Pop-Location }
