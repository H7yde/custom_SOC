#!/usr/bin/env python3
"""Send RGB888 frames to the SoC BRAM firmware over a serial connection."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys
import time


REPO_ROOT = Path(__file__).resolve().parent.parent
PIXEL_COUNT = 32 * 32
FRAME_BYTES = PIXEL_COUNT * 3
RESULT_PATTERN = re.compile(
    r"RESULT ([01]) STATUS ([0-9a-fA-F]{8}) "
    r"CYCLES ([0-9a-fA-F]{8}) READS ([0-9a-fA-F]{8})"
)


class ProtocolError(RuntimeError):
    """The firmware did not complete the requested UART operation."""


@dataclass(frozen=True)
class Result:
    classification: int
    status: int
    cycles: int
    reads: int


def load_frame(path: Path) -> bytes:
    """Read 1024 RGB24 hexadecimal words, allowing whitespace and // comments."""
    tokens = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        tokens.extend(line.split("//", 1)[0].split())
    if len(tokens) != PIXEL_COUNT:
        raise ValueError(f"{path}: expected {PIXEL_COUNT} RGB24 words, got {len(tokens)}")
    pixels = []
    for index, token in enumerate(tokens):
        if not re.fullmatch(r"[0-9a-fA-F]{1,6}", token):
            raise ValueError(f"{path}: invalid RGB24 word {index}: {token!r}")
        pixels.append(int(token, 16).to_bytes(3, "big"))
    return b"".join(pixels)


class FirmwareClient:
    def __init__(self, port, timeout: float = 10.0, byte_delay: float = 0.0):
        self.port = port
        self.timeout = timeout
        self.byte_delay = byte_delay
        self.pending = bytearray()

    def _write(self, data: bytes) -> None:
        offset = 0
        while offset < len(data):
            count = self.port.write(data[offset:])
            if not count:
                raise ProtocolError("UART write made no progress")
            offset += count

    def _read_line(self, deadline: float) -> str | None:
        while time.monotonic() < deadline:
            if b"\n" in self.pending:
                raw, _, remaining = self.pending.partition(b"\n")
                self.pending = bytearray(remaining)
                return raw.decode("ascii", errors="replace").strip()
            chunk = self.port.read(1)
            if chunk:
                self.pending.extend(chunk)
                if len(self.pending) > 4096:
                    raise ProtocolError("Received an unterminated UART response")
        return None

    def _until_ready(self, show: bool = True) -> list[str]:
        deadline = time.monotonic() + self.timeout
        lines = []
        while True:
            line = self._read_line(deadline)
            if line is None:
                raise ProtocolError("Timed out waiting for READY from firmware")
            if not line:
                continue
            if show:
                print(line, flush=True)
            if line == "READY":
                return lines
            lines.append(line)

    def synchronize(self) -> None:
        # Opening some serial adapters resets the board. The first READY may
        # belong to boot, so drain overlapping boot/help output before a second
        # complete help exchange. No bytes are discarded during a frame upload.
        self._write(b"?")
        self._until_ready(show=False)
        deadline = time.monotonic() + self.timeout
        while True:
            line = self._read_line(min(deadline, time.monotonic() + 0.25))
            if line is None:
                break
            if time.monotonic() >= deadline:
                raise ProtocolError("UART did not become idle after READY")
        if self.pending:
            raise ProtocolError("Incomplete UART response while synchronizing")
        self._write(b"?")
        self._until_ready(show=False)

    @staticmethod
    def _results(lines: list[str], count: int) -> list[Result]:
        results = []
        for line in lines:
            if line.startswith("ERROR") or "FAIL" in line:
                raise ProtocolError(line)
            match = RESULT_PATTERN.fullmatch(line)
            if match:
                values = match.groups()
                results.append(Result(int(values[0]), *(int(v, 16) for v in values[1:])))
            elif line.startswith("RESULT"):
                raise ProtocolError(f"Malformed result: {line}")
        if len(results) != count:
            raise ProtocolError(f"Expected {count} RESULT responses, received {len(results)}")
        return results

    def upload(self, command: bytes, payload: bytes) -> Result:
        if command not in (b"B", b"0", b"1") or len(payload) != FRAME_BYTES:
            raise ValueError("Upload requires B/0/1 and exactly 3072 RGB888 bytes")
        self._write(command)
        deadline = time.monotonic() + self.timeout
        while True:
            line = self._read_line(deadline)
            if line is None:
                raise ProtocolError("Timed out waiting for SEND; frame was not uploaded")
            if line == "SEND":
                break
            if line == "READY" or line.startswith("ERROR") or "FAIL" in line:
                raise ProtocolError(f"Expected SEND before upload, received {line!r}")
        if self.byte_delay:
            for value in payload:
                self._write(bytes((value,)))
                time.sleep(self.byte_delay)
        else:
            self._write(payload)
        self.port.flush()  # Wait for queued bytes to transmit; never clear them.
        return self._results(self._until_ready(), 1)[0]

    def pingpong(self) -> list[Result]:
        self._write(b"P")
        return self._results(self._until_ready(), 2)

    def smoke(self) -> None:
        self._write(b"z")
        lines = self._until_ready()
        if "SMOKE PASS" not in lines or any("FAIL" in line or line.startswith("ERROR") for line in lines):
            raise ProtocolError("Black-frame smoke test did not report SMOKE PASS")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Upload 32x32 RGB888 .mem frames to the SoC UART (8N1).",
        epilog="Example: python firmware/host.py --port COM5 --mode pingpong --check-labels",
    )
    parser.add_argument("--port", required=True, help="Serial device, e.g. COM5 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--mode", choices=("baseline", "dma0", "dma1", "pingpong", "smoke"), default="baseline")
    parser.add_argument("--frame", type=Path, default=REPO_ROOT / "CNN_RTL/human_frames.mem", help="Single-frame .mem input (default: repository human frame)")
    parser.add_argument("--human", type=Path, default=REPO_ROOT / "CNN_RTL/human_frames.mem", help="Ping-pong buffer 0 .mem input")
    parser.add_argument("--nonhuman", type=Path, default=REPO_ROOT / "CNN_RTL/nonhuman_frame.mem", help="Ping-pong buffer 1 .mem input")
    parser.add_argument("--expect", type=int, choices=(0, 1), help="Check classification for baseline/dma0/dma1")
    parser.add_argument("--check-labels", action="store_true", help="For pingpong, check human=1 and nonhuman=0 for uploads and both subsequent runs")
    parser.add_argument("--timeout", type=float, default=10.0, help="Response timeout in seconds (default: 10)")
    parser.add_argument("--byte-delay-ms", type=float, default=0.0, help="Optional delay between payload bytes for a slow receiver")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.baud <= 0 or args.timeout <= 0 or args.byte_delay_ms < 0:
        parser.error("baud and timeout must be positive; byte delay must be nonnegative")
    if args.expect is not None and args.mode in ("pingpong", "smoke"):
        parser.error("--expect is only valid for baseline/dma0/dma1")
    if args.check_labels and args.mode != "pingpong":
        parser.error("--check-labels is only valid for pingpong")

    # Validate every input before importing pyserial or touching a serial port.
    try:
        frames = [] if args.mode == "smoke" else (
            [load_frame(args.human), load_frame(args.nonhuman)]
            if args.mode == "pingpong" else [load_frame(args.frame)]
        )
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    try:
        import serial
    except ImportError:
        print("Install UART support: python -m pip install -r firmware/requirements.txt", file=sys.stderr)
        return 2

    try:
        with serial.Serial(args.port, baudrate=args.baud, bytesize=8, parity="N", stopbits=1,
                           timeout=0.1, write_timeout=args.timeout, xonxoff=False,
                           rtscts=False, dsrdtr=False) as port:
            client = FirmwareClient(port, args.timeout, args.byte_delay_ms / 1000.0)
            client.synchronize()
            print(f"Connected: {args.port} at {args.baud} baud, 8N1", flush=True)
            if args.mode == "smoke":
                client.smoke()
            elif args.mode == "pingpong":
                first = client.upload(b"0", frames[0])
                second = client.upload(b"1", frames[1])
                results = [first, second, *client.pingpong()]
                if args.check_labels and [r.classification for r in results] != [1, 0, 1, 0]:
                    raise ProtocolError("Expected human/nonhuman classifications 1,0 for both preload and ping-pong runs")
            else:
                command = {"baseline": b"B", "dma0": b"0", "dma1": b"1"}[args.mode]
                result = client.upload(command, frames[0])
                if args.expect is not None and result.classification != args.expect:
                    raise ProtocolError(f"Expected classification {args.expect}, received {result.classification}")
        return 0
    except (ProtocolError, OSError, serial.SerialException) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted; reset the SoC before retrying an interrupted frame upload.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
