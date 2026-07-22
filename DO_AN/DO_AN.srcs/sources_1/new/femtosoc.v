// RAM block extracted from the original FemtoSOC design by Bruno Levy.
// Adapted as a standalone, synthesizable memory for FemtoRV32 Quark.
//
// Quark uses a unified 32-bit instruction/data bus. Reads are synchronous
// (one clock latency), and writes support one byte-enable per data byte.

`default_nettype none

module femto_ram #(
   parameter integer RAM_BYTES = 32 * 1024,
   parameter         INIT_FILE = ""
) (
   input  wire        clk,
   input  wire        ram_sel,

   input  wire [31:0] mem_addr,
   input  wire [31:0] mem_wdata,
   input  wire  [3:0] mem_wmask,
   input  wire        mem_rstrb,

   output reg  [31:0] mem_rdata,
   output wire        mem_rbusy,
   output wire        mem_wbusy
);

   localparam integer RAM_WORDS      = RAM_BYTES / 4;
   localparam integer RAM_ADDR_WIDTH = $clog2(RAM_WORDS);

   wire [RAM_ADDR_WIDTH-1:0] ram_word_addr =
      mem_addr[RAM_ADDR_WIDTH+1:2];

   // Vivado maps this array to 7-series block RAM. The four conditional
   // assignments infer the BRAM byte-write enables used by Quark stores.
   (* ram_style = "block" *)
   reg [31:0] ram [0:RAM_WORDS-1];

   // A synchronous BRAM read already matches Quark's FETCH/WAIT sequencing,
   // so RAM itself does not need to insert additional wait states.
   assign mem_rbusy = 1'b0;
   assign mem_wbusy = 1'b0;

   // Leave INIT_FILE empty when firmware will be loaded by another method.
   // Otherwise pass a Vivado-compatible hexadecimal word file.
   initial begin
      if (INIT_FILE != "") begin
         $readmemh(INIT_FILE, ram);
      end
   end

   always @(posedge clk) begin
      if (ram_sel && mem_rstrb) begin
         mem_rdata <= ram[ram_word_addr];
      end

      if (ram_sel) begin
         if (mem_wmask[0])
            ram[ram_word_addr][7:0]   <= mem_wdata[7:0];
         if (mem_wmask[1])
            ram[ram_word_addr][15:8]  <= mem_wdata[15:8];
         if (mem_wmask[2])
            ram[ram_word_addr][23:16] <= mem_wdata[23:16];
         if (mem_wmask[3])
            ram[ram_word_addr][31:24] <= mem_wdata[31:24];
      end
   end

endmodule

`default_nettype wire
