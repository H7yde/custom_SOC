#!/usr/bin/env python3
"""Build RV32I firmware and emit the exact 1024 words expected by soc_top BRAM."""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PROJECT = ROOT / "SOC_HUFLIT_2026_parallel_50MHz"
BRAM_BYTES = 4096


def find_gcc(explicit=None):
    requested = explicit or os.environ.get("RISCV_GCC")
    if requested:
        candidate = shutil.which(requested) or requested
        if Path(candidate).is_file():
            return Path(candidate).resolve()
        raise ValueError(f"RISC-V compiler not found: {requested}")
    for name in ("riscv32-unknown-elf-gcc", "riscv64-unknown-elf-gcc",
                 "riscv-none-elf-gcc", "riscv32-xilinx-elf-gcc"):
        candidate = shutil.which(name)
        if candidate:
            return Path(candidate)
    installations = []
    for name in ("XILINX_VITIS", "XILINX_VIVADO"):
        if os.environ.get(name):
            installations.append(Path(os.environ[name]).parent)
    for base in (Path("C:/AMDDesignTools"), Path("D:/AMDDesignTools"),
                 Path("C:/Xilinx"), Path("D:/Xilinx")):
        if base.is_dir():
            installations.extend(sorted(base.iterdir(), reverse=True))
    for installation in installations:
        for relative in ("gnu/riscv/nt/bin/riscv64-unknown-elf-gcc.exe",
                         "gnu/riscv/nt/x86_64-w64-mingw32/usr/bin/"
                         "riscv32-xilinx-elf/riscv32-xilinx-elf-gcc.exe"):
            candidate = installation / relative
            if candidate.is_file():
                return candidate
    raise ValueError("Install a RISC-V GCC toolchain or pass --gcc PATH. "
                     "AMD tools' bundled RISC-V GCC is also supported.")


def elf_to_image(path):
    elf = path.read_bytes()
    if elf[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("Expected a 32-bit, little-endian ELF file")
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", elf)
    if header[2] != 243 or header[4] != 0:
        raise ValueError("Firmware must be RISC-V with entry point 0x00000000")
    phoff, phentsize, phnum = header[5], header[9], header[10]
    image = bytearray(BRAM_BYTES)
    occupied_end = 0
    loaded = False
    for index in range(phnum):
        kind, offset, vaddr, paddr, filesz, memsz, _, _ = struct.unpack_from(
            "<IIIIIIII", elf, phoff + index * phentsize)
        if kind != 1 or memsz == 0:
            continue
        if filesz > memsz or paddr != vaddr or paddr + memsz > BRAM_BYTES:
            raise ValueError("ELF load segment does not fit the 4 KiB BRAM")
        if offset + filesz > len(elf):
            raise ValueError("Truncated ELF load segment")
        image[paddr:paddr + filesz] = elf[offset:offset + filesz]
        occupied_end = max(occupied_end, paddr + memsz)
        loaded = True
    if not loaded:
        raise ValueError("ELF has no loadable segments")
    return image, occupied_end


def build(args):
    gcc = find_gcc(args.gcc)
    output = HERE / "build"
    output.mkdir(exist_ok=True)
    app_name = "bram_test" if args.app == "bram" else "firmware"
    source = "bram_test.c" if args.app == "bram" else "main.c"
    linker = "bram_linker.ld" if args.app == "bram" else "linker.ld"
    elf = output / f"{app_name}.elf"
    flags = ["-march=rv32i", "-mabi=ilp32", "-Os", "-g", "-std=c11",
             "-Wall", "-Wextra", "-Werror", "-ffreestanding", "-fno-builtin",
             "-fno-pic", "-fno-pie", "-fno-stack-protector", "-mno-relax",
             "-msmall-data-limit=0", "-ffunction-sections", "-fdata-sections",
             "-fno-asynchronous-unwind-tables", "-nostdlib", "-nostartfiles"]
    command = [str(gcc), *flags, "-T", str(HERE / linker),
               "-Wl,--build-id=none,--gc-sections,--no-relax",
               f"-Wl,-Map,{output / (app_name + '.map')}",
               str(HERE / "start.S"), str(HERE / source), "-o", str(elf)]
    print(f"Compiler: {gcc}", flush=True)
    subprocess.run(command, check=True)
    image, occupied_end = elf_to_image(elf)
    (output / f"{app_name}.bin").write_bytes(image)
    hex_path = HERE / f"{app_name}.hex"
    hex_path.write_text("".join(f"{word:08x}\n" for (word,) in
                                struct.iter_unpack("<I", image)), encoding="ascii")
    prefix = gcc.name.removesuffix("gcc.exe").removesuffix("gcc")
    suffix = ".exe" if gcc.suffix.lower() == ".exe" else ""
    objdump = gcc.with_name(prefix + "objdump" + suffix)
    if objdump.is_file():
        with (output / f"{app_name}.dis").open("w", encoding="utf-8") as stream:
            subprocess.run([str(objdump), "-d", str(elf)], check=True, stdout=stream)
    if not args.no_deploy:
        destination = PROJECT / "SOC_HUFLIT_2026.srcs/sources_1/new/firmware.hex"
        shutil.copyfile(hex_path, destination)
        print(f"Vivado image: {destination}")
    print(f"BRAM image: {hex_path} (1024 x 32-bit words, little-endian ELF)")
    if args.app == "bram":
        print(f"Code/data/BSS end: 0x{occupied_end:03x}; "
              "scratch: 0x400..0x7ff; report: 0x800; stack top: 0xff0")
    else:
        print(f"Code/data/BSS end: 0x{occupied_end:03x}; stack top: 0xff0; "
              f"space before stack: {0xdf0 - occupied_end} bytes")
    print(f"ELF/map/disassembly: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", choices=("cnn", "bram"), default="cnn",
                        help="cnn: UART/CNN controller (default); bram: memory test only")
    parser.add_argument("--gcc", help="RISC-V GCC executable (or RISCV_GCC env)")
    parser.add_argument("--no-deploy", action="store_true",
                        help="Do not copy firmware.hex to the Vivado design sources")
    try:
        build(parser.parse_args())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Build failed: {error}", file=sys.stderr)
        sys.exit(1)
