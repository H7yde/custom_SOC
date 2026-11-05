"""Simulate competing ARM/Pico AXI clients against the actual CNN RTL."""
from pathlib import Path
import argparse
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vivado-bin", type=Path, default=Path("D:/Vivado_data/2025.2/Vivado/bin"))
    parser.add_argument("--firmware-boot", action="store_true")
    parser.add_argument("--recovery", action="store_true")
    parser.add_argument("--memory-recovery", action="store_true")
    args = parser.parse_args()
    if sum((args.recovery, args.firmware_boot, args.memory_recovery)) > 1:
        parser.error("Choose only one test mode")
    projects = list(ROOT.glob("SOC_HUFLIT_2026_parallel_*/SOC_HUFLIT_2026.xpr"))
    if len(projects) != 1:
        raise RuntimeError("Expected one SoC project")
    rtl = projects[0].parent / "SOC_HUFLIT_2026.srcs/sources_1/new"
    work = ROOT / "fpga_usb_hdmi/build_check" / ("cnn_dma_recovery" if args.memory_recovery else "arm_cnn_firmware_boot" if args.firmware_boot else "arm_cnn_recovery" if args.recovery else "arm_cnn_sim")
    work.mkdir(parents=True, exist_ok=True)
    for name in ("conv1_rgb_weight.mem", "conv2_weight.mem", "conv3_weight.mem", "fc_weight.mem"):
        shutil.copyfile(rtl / name, work / name)
    words = []
    for name in ("human_frames.mem", "nonhuman_frame.mem"):
        pixels = [int(v, 16) for v in (ROOT / "CNN_RTL" / name).read_text().split()][:1024]
        if len(pixels) != 1024:
            raise RuntimeError("Expected a complete RGB frame")
        rgb = b"".join(v.to_bytes(3, "big") for v in pixels)
        words.extend(int.from_bytes(rgb[i:i+4], "big") for i in range(0, len(rgb), 4))
    (work / "bridge_images.mem").write_text("".join(f"{v:08X}\n" for v in words))
    sources = [rtl / name for name in ("cnn_axi_bridge.v", "CNN.v", "cnn_docx_reference.v", "dma32_to_rgb24.v")]
    cdc = projects[0].parent / "SOC_HUFLIT_2026.gen/sources_1/bd/usb_hdmi_system/ip/usb_hdmi_system_arm_cnn_cdc_0/sim/usb_hdmi_system_arm_cnn_cdc_0.v"
    sources.append(cdc)
    sources.append(args.vivado_bin.parent / "data/verilog/src/glbl.v")
    top = "tb_arm_cnn_bridge"
    snapshot = "arm_cnn_bridge_sim"
    passed = "ARM_CNN_BRIDGE_TEST_PASS"
    if args.firmware_boot:
        shutil.copyfile(ROOT / "firmware/firmware.hex", work / "firmware.hex")
        sources = [rtl / name for name in (
            "picorv32.v", "parallel.v", "soc_axi_top.v", "axi_uart_slave.v",
            "axi_spi_slave.v", "axi_i2c_slave.v", "CNN.v", "cnn_memory_subsystem.v",
            "cnn_docx_reference.v", "dma32_to_rgb24.v", "picorv32_axi4_bram_adapter.v",
            "axi4_bram_slave.v", "cnn_axi_bridge.v", "soc_top.v")]
        sources.append(args.vivado_bin.parent / "data/verilog/src/glbl.v")
        top = "tb_arm_cnn_firmware_boot"
        snapshot = "arm_cnn_firmware_boot"
        passed = "ARM_CNN_FIRMWARE_BOOT_PASS"
    if args.recovery:
        passed = "ARM_CNN_RECOVERY_TEST_PASS"
    if args.memory_recovery:
        sources = [rtl / "cnn_memory_subsystem.v", args.vivado_bin.parent / "data/verilog/src/glbl.v"]
        top = snapshot = "tb_cnn_dma_recovery"
        passed = "CNN_DMA_RECOVERY_PASS"
    defines = ["-d", "RECOVERY_TEST"] if args.recovery else []
    commands = [
        [args.vivado_bin / "xvlog.bat", "--sv", "-i", Path(__file__).parent, *defines, *sources, Path(__file__).with_name(top + ".sv")],
        [args.vivado_bin / "xelab.bat", top, "glbl", "-s", snapshot, "-L", "axi_clock_converter_v2_1_35", "-L", "axi_infrastructure_v1_1_0", "-L", "xpm", "-L", "unisims_ver"],
        [args.vivado_bin / "xsim.bat", snapshot, "-runall", "-log", "simulate.log"],
    ]
    for number, command in enumerate(commands):
        with (work / f"stage_{number}.log").open("w") as log:
            subprocess.run([str(a) for a in command], cwd=work, stdout=log, stderr=subprocess.STDOUT, check=True)
    output = (work / "simulate.log").read_text()
    if passed not in output or "Fatal:" in output:
        raise RuntimeError(f"Simulation failed; inspect {work / 'simulate.log'}")
    print(passed)
    print(work / "simulate.log")


if __name__ == "__main__":
    main()
