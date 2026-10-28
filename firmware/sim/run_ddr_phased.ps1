param([string] $VivadoBin="C:/AMDDesignTools/2025.2/Vivado/bin")
$ErrorActionPreference="Stop"
$ddrRepo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ddrOutput=Join-Path $ddrRepo "firmware/build/sim_ddr_phased"
New-Item -ItemType Directory -Force -Path $ddrOutput | Out-Null
Push-Location $ddrOutput
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib (Join-Path $ddrRepo "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/parallel.v") (Join-Path $PSScriptRoot "tb_ddr_phased.v") (Join-Path (Split-Path $VivadoBin -Parent) "data/verilog/src/glbl.v")
    if($LASTEXITCODE -ne 0){throw "DDR compile failed"}
    & (Join-Path $VivadoBin "xelab.bat") --debug typical -L unisims_ver xil_defaultlib.tb_ddr_phased xil_defaultlib.glbl -s ddr_phased_sim
    if($LASTEXITCODE -ne 0){throw "DDR elaboration failed"}
    & (Join-Path $VivadoBin "xsim.bat") ddr_phased_sim -runall -log simulate.log
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath simulate.log -SimpleMatch "DDR PHASED CLOCK PASS" -Quiet)){throw "DDR test failed"}
} finally {Pop-Location}
