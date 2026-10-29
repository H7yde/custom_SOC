param(
    [string] $VivadoBin = "",
    [string] $FirmwareHex = "",
    [string] $OutputDirectory = "",
    [int] $BaudRate = 1000000,
    [switch] $FullImages
)
$ErrorActionPreference = "Stop"
$firmwareDirectory = Split-Path $PSScriptRoot -Parent
$repositoryDirectory = Split-Path $firmwareDirectory -Parent
$rtlDirectory = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
$simulationDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $firmwareDirectory "build/sim" }
if (-not $FirmwareHex) { $FirmwareHex = Join-Path $firmwareDirectory "firmware.hex" }
$FirmwareHex = (Resolve-Path -LiteralPath $FirmwareHex).Path
if (-not $VivadoBin) {
    if ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO "bin" }
    elseif (Get-Command xvlog.bat -ErrorAction SilentlyContinue) {
        $VivadoBin = Split-Path (Get-Command xvlog.bat).Source -Parent
    } else { $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin" }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$globalModule = Join-Path (Split-Path $VivadoBin -Parent) "data/verilog/src/glbl.v"
if ($BaudRate -le 0 -or $BaudRate -gt 1000000) { throw "Use a simulation baud rate between 1 and 1000000." }
New-Item -ItemType Directory -Force -Path $simulationDirectory | Out-Null
Copy-Item -LiteralPath $FirmwareHex -Destination (Join-Path $simulationDirectory "firmware.hex")
foreach ($weightName in @("conv1_rgb_weight.mem", "conv2_weight.mem", "conv3_weight.mem", "fc_weight.mem")) {
    Copy-Item -LiteralPath (Join-Path $rtlDirectory $weightName) -Destination $simulationDirectory
}
if ($FullImages) {
    Copy-Item -LiteralPath (Join-Path $repositoryDirectory "CNN_RTL/human_frames.mem") -Destination $simulationDirectory
    Copy-Item -LiteralPath (Join-Path $repositoryDirectory "CNN_RTL/nonhuman_frame.mem") -Destination $simulationDirectory
}
$rtlNames = @("picorv32.v", "parallel.v", "soc_axi_top.v", "axi_uart_slave.v",
              "axi_spi_slave.v", "axi_i2c_slave.v", "CNN.v", "cnn_memory_subsystem.v",
              "cnn_docx_reference.v", "dma32_to_rgb24.v", "picorv32_axi4_bram_adapter.v",
              "axi4_bram_slave.v", "soc_top.v")
$rtlFiles = @($rtlNames | ForEach-Object { Join-Path $rtlDirectory $_ })
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib @rtlFiles (Join-Path $PSScriptRoot "tb_firmware.v") $globalModule
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)." }
    # Keep the equals sign intact through Vivado's Windows batch wrappers.
    $baudGeneric = '"BAUD_RATE={0}"' -f $BaudRate
    & (Join-Path $VivadoBin "xelab.bat") --debug typical -L unisims_ver -L unimacro_ver `
        --generic_top $baudGeneric xil_defaultlib.tb_firmware xil_defaultlib.glbl -s firmware_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run.tcl").Replace('\', '/')
    $simulationArguments = @("firmware_sim", "-tclbatch", $batchTcl, "-log", "simulate.log")
    if ($FullImages) { $simulationArguments += @("-testplusarg", "FULL_IMAGES") }
    & (Join-Path $VivadoBin "xsim.bat") @simulationArguments
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)." }
    if (-not (Select-String -LiteralPath "simulate.log" -SimpleMatch "FIRMWARE INTEGRATION PASS" -Quiet)) {
        throw "Firmware simulation did not report FIRMWARE INTEGRATION PASS; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
