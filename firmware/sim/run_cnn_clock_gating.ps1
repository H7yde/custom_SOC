param(
    [string] $VivadoBin = "",
    [string] $OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$firmwareDirectory = Split-Path $PSScriptRoot -Parent
$repositoryDirectory = Split-Path $firmwareDirectory -Parent
$rtlDirectory = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
if (-not $VivadoBin) {
    if ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO "bin" }
    elseif (Get-Command xvlog.bat -ErrorAction SilentlyContinue) {
        $VivadoBin = Split-Path (Get-Command xvlog.bat).Source -Parent
    } else { $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin" }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$globalModule = Join-Path (Split-Path $VivadoBin -Parent) "data/verilog/src/glbl.v"
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $firmwareDirectory "build/sim_cnn_clock_gating" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$simulationDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
foreach ($name in @("human_frames.mem", "nonhuman_frame.mem")) {
    Copy-Item -LiteralPath (Join-Path $repositoryDirectory "CNN_RTL/$name") -Destination $simulationDirectory
}
# Localize existing absolute weight paths in a simulation-only copy.
# The design sources and the selected CPU firmware are not modified.
$coreSource = Get-Content -LiteralPath (Join-Path $rtlDirectory "cnn_docx_reference.v") -Raw
foreach ($name in @("conv1_rgb_weight.mem", "conv2_weight.mem", "conv3_weight.mem", "fc_weight.mem")) {
    Copy-Item -LiteralPath (Join-Path $rtlDirectory $name) -Destination $simulationDirectory
    $pattern = '"[^"\r\n]*[/\\]' + [regex]::Escape($name) + '"'
    $coreSource = [regex]::Replace($coreSource, $pattern, ('"' + $name + '"'))
}
$coreCopy = Join-Path $simulationDirectory "cnn_docx_reference.v"
[System.IO.File]::WriteAllText($coreCopy, $coreSource, [System.Text.UTF8Encoding]::new($false))
$rtlFiles = @("CNN.v", "dma32_to_rgb24.v", "cnn_memory_subsystem.v") |
    ForEach-Object { Join-Path $rtlDirectory $_ }
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib @rtlFiles $coreCopy `
        (Join-Path $PSScriptRoot "tb_cnn_clock_gating.v") $globalModule
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)." }
    & (Join-Path $VivadoBin "xelab.bat") --debug typical -L unisims_ver `
        xil_defaultlib.tb_cnn_clock_gating xil_defaultlib.glbl -s cnn_clock_gating_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run.tcl").Replace('\', '/')
    & (Join-Path $VivadoBin "xsim.bat") cnn_clock_gating_sim `
        -tclbatch $batchTcl -log simulate.log
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)." }
    if (-not (Select-String -LiteralPath "simulate.log" -SimpleMatch "CNN CLOCK GATING PASS" -Quiet)) {
        throw "Clock gating test failed; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
