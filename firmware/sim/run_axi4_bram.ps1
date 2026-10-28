param(
    [string] $VivadoBin = "",
    [string] $OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$firmwareDirectory = Split-Path $PSScriptRoot -Parent
$repositoryDirectory = Split-Path $firmwareDirectory -Parent
$rtlDirectory = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
$simulationDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $firmwareDirectory "build/sim_axi4" }
if (-not $VivadoBin) {
    if ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO "bin" }
    elseif (Get-Command xvlog.bat -ErrorAction SilentlyContinue) {
        $VivadoBin = Split-Path (Get-Command xvlog.bat).Source -Parent
    } else { $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin" }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
New-Item -ItemType Directory -Force -Path $simulationDirectory | Out-Null
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib `
        (Join-Path $rtlDirectory "axi4_bram_slave.v") (Join-Path $PSScriptRoot "tb_axi4_bram.v")
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)." }
    & (Join-Path $VivadoBin "xelab.bat") --debug typical xil_defaultlib.tb_axi4_bram -s axi4_bram_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run_axi4_bram.tcl").Replace('\', '/')
    & (Join-Path $VivadoBin "xsim.bat") axi4_bram_sim -tclbatch $batchTcl -wdb axi4_bram.wdb -log simulate.log
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)." }
    if (-not (Select-String -LiteralPath "simulate.log" -SimpleMatch "AXI4 BRAM PROTOCOL PASS" -Quiet)) {
        throw "AXI4 BRAM simulation failed; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
