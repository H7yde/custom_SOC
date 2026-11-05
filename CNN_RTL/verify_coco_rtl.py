"""Compare exported COCO weights against the actual Vivado RTL, layer by layer."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import numpy as np

from cnn_model import integer_reference, read_mem_weights, WEIGHT_FILES

HERE = Path(__file__).resolve().parent
from project_paths import design_directory
RTL = design_directory() / "cnn_docx_reference.v"

TESTBENCH = r'''
`timescale 1ns/1ps
module tb_coco_rtl;
  reg clk=0, rst=1, pixel_valid=0;
  reg [23:0] pixel_data=0;
  wire pixel_ready, result_valid, classification;
  reg [23:0] frame[0:1023];
  reg [7:0] c1[0:3599], p1[0:899], c2[0:675], p2[0:143], c3[0:63], p3[0:15];
  integer checks=0, cases_passed=0;
  always #4 clk=~clk;
  cnn_docx_reference dut(.clk(clk),.rst(rst),.pixel_data(pixel_data),
    .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
    .result_valid(result_valid),.classification(classification));
  task run_case(input string filename, input integer index,
                input integer expected_class, input integer expected_score);
    integer i, cycles;
    begin
      @(negedge clk); rst=1; pixel_valid=0;
      repeat(4) @(negedge clk);
      rst=0;
      repeat(2) @(negedge clk);
      $readmemh(filename,frame);
      $readmemh($sformatf("gold_%0d_c1.mem",index),c1);
      $readmemh($sformatf("gold_%0d_p1.mem",index),p1);
      $readmemh($sformatf("gold_%0d_c2.mem",index),c2);
      $readmemh($sformatf("gold_%0d_p2.mem",index),p2);
      $readmemh($sformatf("gold_%0d_c3.mem",index),c3);
      $readmemh($sformatf("gold_%0d_p3.mem",index),p3);
      for(i=0;i<1024;i=i+1) begin
        @(negedge clk);
        pixel_valid=0;
        if ((i % 31)==0) @(negedge clk);
        pixel_data=frame[i]; pixel_valid=1;
        @(posedge clk);
        while(pixel_ready!==1'b1) @(posedge clk);
      end
      @(negedge clk); pixel_valid=0;
      cycles=0;
      while(result_valid!==1'b1 && cycles<1000000) begin
        @(negedge clk); cycles=cycles+1;
      end
      if(result_valid!==1'b1) $fatal(1,"CNN timeout: %s",filename);
      if(classification!==expected_class[0]) $fatal(1,"Class mismatch: %s",filename);
      if($signed(dut.total)!==expected_score) $fatal(1,"FC score mismatch %s got=%0d expected=%0d",filename,$signed(dut.total),expected_score);
      for(i=0;i<3600;i=i+1) begin
        if(dut.c1[i]!==c1[i]) $fatal(1,"c1 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      for(i=0;i<900;i=i+1) begin
        if(dut.p1[i]!==p1[i]) $fatal(1,"p1 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      for(i=0;i<676;i=i+1) begin
        if(dut.c2[i]!==c2[i]) $fatal(1,"c2 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      for(i=0;i<144;i=i+1) begin
        if(dut.p2[i]!==p2[i]) $fatal(1,"p2 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      for(i=0;i<64;i=i+1) begin
        if(dut.c3[i]!==c3[i]) $fatal(1,"c3 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      for(i=0;i<16;i=i+1) begin
        if(dut.p3[i]!==p3[i]) $fatal(1,"p3 mismatch %s index=%0d",filename,i);
        checks=checks+1;
      end
      cases_passed=cases_passed+1;
      $display("COCO CASE PASS: %s class=%0d score=%0d cycles=%0d",filename,classification,$signed(dut.total),cycles);
    end
  endtask
  initial begin
    // CASES
    $display("COCO RTL PARITY PASS: cases=%0d activation_checks=%0d",cases_passed,checks);
    $finish;
  end
endmodule
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(run_directory, vivado_bin):
    run_directory = Path(run_directory).resolve()
    examples = json.loads((run_directory / "examples.json").read_text())
    weights = read_mem_weights(run_directory)
    output = run_directory / "rtl_sim"
    output.mkdir(exist_ok=True)
    for filename in WEIGHT_FILES.values():
        shutil.copy2(run_directory / filename, output / filename)
    calls = []
    for index, example in enumerate(examples):
        filename = example["file"]
        shutil.copy2(run_directory / filename, output / filename)
        tokens = (run_directory / filename).read_text().split()
        if len(tokens) != 1024:
            raise ValueError(f"Wrong RGB frame length: {filename}")
        pixels = np.array([[(int(v, 16) >> 16) & 255, (int(v, 16) >> 8) & 255,
                            int(v, 16) & 255] for v in tokens], dtype=np.uint8).reshape(32, 32, 3)
        reference = integer_reference(pixels, weights)
        if reference["score"] != example["integer_score"] or reference["classification"] != example["rtl_expected"]:
            raise AssertionError(f"Stale examples/weights for {filename}")
        for layer in ("c1", "p1", "c2", "p2", "c3", "p3"):
            (output / f"gold_{index}_{layer}.mem").write_text(
                "".join(f"{int(value):02X}\n" for value in reference[layer].flat), encoding="ascii")
        calls.append(f'    run_case("{filename}",{index},{reference["classification"]},{reference["score"]});')
    testbench = output / "tb_coco_rtl.sv"
    testbench.write_text(TESTBENCH.replace("    // CASES", "\n".join(calls)), encoding="ascii")
    (output / "run.tcl").write_text("run all\nquit\n", encoding="ascii")
    suffix = ".bat" if os.name == "nt" else ""
    commands = [
        [str(vivado_bin / ("xvlog" + suffix)), "--sv", "--work", "xil_defaultlib", str(RTL), str(testbench)],
        [str(vivado_bin / ("xelab" + suffix)), "xil_defaultlib.tb_coco_rtl", "-s", "coco_rtl_sim"],
        [str(vivado_bin / ("xsim" + suffix)), "coco_rtl_sim", "-tclbatch", "run.tcl", "-log", "simulate.log"],
    ]
    for command in commands:
        print("Running:", subprocess.list2cmdline(command), flush=True)
        subprocess.run(command, cwd=output, check=True)
    log = (output / "simulate.log").read_text(encoding="utf-8", errors="replace")
    marker = f"COCO RTL PARITY PASS: cases={len(examples)} activation_checks={len(examples) * 5400}"
    if marker not in log or "Fatal:" in log or "FATAL" in log:
        raise RuntimeError(f"RTL validation failed; inspect {output / 'simulate.log'}")
    report = {"passed": True, "cases": len(examples), "activation_checks": len(examples) * 5400,
              "rtl": str(RTL), "rtl_sha256": sha(RTL),
              "weights": {name: sha(run_directory / name) for name in WEIGHT_FILES.values()},
              "examples_sha256": sha(run_directory / "examples.json"),
              "log": str(output / "simulate.log")}
    (run_directory / "rtl_verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(marker, flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("--vivado-bin", type=Path,
                        default=Path(os.environ.get("XILINX_VIVADO", "D:/Vivado_data/2025.2/Vivado")) / "bin")
    args = parser.parse_args()
    verify(args.run_directory, args.vivado_bin)


if __name__ == "__main__":
    main()
