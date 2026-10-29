param(
    [Parameter(Mandatory = $true)] [string] $VivadoBin,
    [string] $OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$repositoryDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot "../build/sim_ddr_direct125"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$simulationDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$globalModule = Join-Path (Split-Path $VivadoBin -Parent) "data/verilog/src/glbl.v"
$parallelRtl = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/parallel.v"
$testbench = Join-Path $PSScriptRoot "tb_ddr_phased.v"
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib $parallelRtl $testbench $globalModule
    if ($LASTEXITCODE -ne 0) { throw "DDR xvlog failed ($LASTEXITCODE)." }
    & (Join-Path $VivadoBin "xelab.bat") --debug typical -L unisims_ver -L unimacro_ver xil_defaultlib.tb_ddr_phased xil_defaultlib.glbl -s ddr_phased_sim
    if ($LASTEXITCODE -ne 0) { throw "DDR xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run.tcl").Replace('\', '/')
    & (Join-Path $VivadoBin "xsim.bat") ddr_phased_sim -tclbatch $batchTcl -log simulate.log
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath "simulate.log" -SimpleMatch "DDR PHASED CLOCK PASS" -Quiet)) {
        throw "DDR simulation failed; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
