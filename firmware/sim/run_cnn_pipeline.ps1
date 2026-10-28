param(
    [string] $VivadoBin = "",
    [string] $BaselineRtl = "",
    [string] $OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$firmwareDirectory = Split-Path $PSScriptRoot -Parent
$repositoryDirectory = Split-Path $firmwareDirectory -Parent
$rtlDirectory = Join-Path $repositoryDirectory "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"
$simulationDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $firmwareDirectory "build/sim_cnn_pipeline" }
if (-not $BaselineRtl) {
    $BaselineRtl = Join-Path $firmwareDirectory "backups/before_pipeline_20261018_102557/cnn_docx_reference.v"
}
$BaselineRtl = (Resolve-Path -LiteralPath $BaselineRtl).Path
if (-not $VivadoBin) {
    if ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO "bin" }
    elseif (Get-Command xvlog.bat -ErrorAction SilentlyContinue) {
        $VivadoBin = Split-Path (Get-Command xvlog.bat).Source -Parent
    } else { $VivadoBin = "C:/AMDDesignTools/2025.2/Vivado/bin" }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
New-Item -ItemType Directory -Force -Path $simulationDirectory | Out-Null
$simulationDirectory = (Resolve-Path -LiteralPath $simulationDirectory).Path
$baselineSource = Get-Content -LiteralPath $BaselineRtl -Raw
if ([regex]::Matches($baselineSource, 'module\s+cnn_docx_reference\s*\(').Count -ne 1) {
    throw "Baseline must contain exactly one cnn_docx_reference module."
}
$baselineSource = [regex]::Replace($baselineSource, 'module\s+cnn_docx_reference\s*\(', 'module cnn_docx_reference_baseline(')
$baselineCopy = Join-Path $simulationDirectory "cnn_docx_reference_baseline.v"
[System.IO.File]::WriteAllText($baselineCopy, $baselineSource, [System.Text.UTF8Encoding]::new($false))
foreach ($name in @("human_frames.mem", "nonhuman_frame.mem")) {
    Copy-Item -LiteralPath (Join-Path $repositoryDirectory "CNN_RTL/$name") -Destination (Join-Path $simulationDirectory $name)
}
foreach ($name in @("conv1_rgb_weight.mem", "conv2_weight.mem", "conv3_weight.mem", "fc_weight.mem")) {
    Copy-Item -LiteralPath (Join-Path $rtlDirectory $name) -Destination (Join-Path $simulationDirectory $name)
}
Push-Location $simulationDirectory
try {
    & (Join-Path $VivadoBin "xvlog.bat") --sv --work xil_defaultlib `
        $baselineCopy (Join-Path $rtlDirectory "cnn_docx_reference.v") (Join-Path $PSScriptRoot "tb_cnn_pipeline_equivalence.v")
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)." }
    & (Join-Path $VivadoBin "xelab.bat") --debug typical xil_defaultlib.tb_cnn_pipeline_equivalence -s cnn_pipeline_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)." }
    $batchTcl = (Join-Path $PSScriptRoot "run_cnn_pipeline.tcl").Replace('\', '/')
    & (Join-Path $VivadoBin "xsim.bat") cnn_pipeline_sim -tclbatch $batchTcl -wdb cnn_pipeline.wdb -log simulate.log
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)." }
    if (-not (Select-String -LiteralPath "simulate.log" -SimpleMatch "CNN PIPELINE EQUIVALENCE PASS" -Quiet)) {
        throw "CNN equivalence simulation failed; inspect $simulationDirectory/simulate.log."
    }
} finally { Pop-Location }
