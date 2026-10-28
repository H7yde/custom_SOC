param(
    [string] $VivadoBin = "",
    [string] $FirmwareHex = "",
    [string] $OutputDirectory = "",
    [int] $ClockFrequency = 50000000,
    [switch] $PhasedDdrClock
)
$ErrorActionPreference = "Stop"
if ($ClockFrequency -le 0) { throw "ClockFrequency must be positive." }
$firmwareDirectory = Split-Path $PSScriptRoot -Parent
$repositoryDirectory = Split-Path $firmwareDirectory -Parent
$rtlDirectory = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
$simulationDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $firmwareDirectory "build/sim_bram" }
if (-not $FirmwareHex) { $FirmwareHex = Join-Path $firmwareDirectory "bram_test.hex" }
$FirmwareHex = (Resolve-Path -LiteralPath $FirmwareHex).Path
if (-not $VivadoBin) {
    if ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO "bin" }
    elseif (Get-Command xvlog.bat -ErrorAction SilentlyContinue) {
        $VivadoBin = Split-Path (Get-Command xvlog.bat).Source -Parent
    } else { $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin" }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$globalModule = Join-Path (Split-Path $VivadoBin -Parent) "data/verilog/src/glbl.v"
New-Item -ItemType Directory -Force -Path $simulationDirectory | Out-Null
Copy-Item -LiteralPath $FirmwareHex -Destination (Join-Path $simulationDirectory "firmware.hex")
$rtlNames = @("picorv32.v", "parallel.v", "soc_axi_top.v", "axi_uart_slave.v",
              "axi_spi_slave.v", "axi_i2c_slave.v", "CNN.v", "cnn_memory_subsystem.v",
              "cnn_docx_reference.v", "dma32_to_rgb24.v", "picorv32_axi4_bram_adapter.v",
              "axi4_bram_slave.v", "soc_top.v")
$rtlFiles = @($rtlNames | ForEach-Object { Join-Path $rtlDirectory $_ })
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib @rtlFiles (Join-Path $PSScriptRoot "tb_bram_firmware.v") $globalModule
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)." }
    $elaborationArguments = @("--debug", "typical", "-L", "unisims_ver", "-L", "unimacro_ver")
    if ($ClockFrequency -ne 50000000) {
        $clockGeneric = '"CLK_FREQ={0}"' -f $ClockFrequency
        $elaborationArguments += @("--generic_top", $clockGeneric)
    }
    if ($PhasedDdrClock) {
        $elaborationArguments += @("--generic_top", '"DDR_TX_PHASED_CLOCK=1"')
    }
    $elaborationArguments += @("xil_defaultlib.tb_bram_firmware", "xil_defaultlib.glbl", "-s", "bram_firmware_sim")
    & (Join-Path $VivadoBin "xelab.bat") @elaborationArguments
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run_bram.tcl").Replace('\', '/')
    & (Join-Path $VivadoBin "xsim.bat") bram_firmware_sim -tclbatch $batchTcl -wdb bram_firmware.wdb -log simulate.log
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)." }
    if (-not (Select-String -LiteralPath "simulate.log" -SimpleMatch "BRAM FIRMWARE PASS" -Quiet)) {
        throw "BRAM firmware simulation did not report BRAM FIRMWARE PASS; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
