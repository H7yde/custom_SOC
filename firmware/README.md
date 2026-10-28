# Firmware BRAM cho HUFLIT SoC

Nếu chỉ cần kiểm tra đọc/ghi BRAM, dùng bản tối giản trong
[BRAM_ONLY.md](BRAM_ONLY.md): `py firmware/build.py --app bram --no-deploy`.
Bản này lưu PASS/FAIL trong BRAM và không dùng UART/CNN.
Giao tiếp CPU–BRAM đã chuyển sang AXI4; xem [AXI4_BRAM.md](AXI4_BRAM.md).

Firmware bare-metal C + assembly dành cho `soc_top` đang có trong project:

- CPU PicoRV32, ISA **RV32I**, ABI **ILP32**, không cần bộ nhân/chia hoặc lệnh nén.
- BRAM 4 KiB tại `0x00000000..0x00000fff`; reset PC = `0`; stack bắt đầu tại `0x00000ff0`.
- Clock mặc định 100 MHz, UART **115200 baud, 8N1**.
- Firmware boot, tự kiểm tra dữ liệu/BRAM và thanh ghi CNN, rồi chờ lệnh UART.
- Nhận ảnh RGB888 32×32 từ PC và chạy CNN qua AXI-Lite, DMA buffer 0/1 hoặc ping-pong.

`firmware.hex` là **mã máy RISC-V để CPU thực thi**, được `soc_top.v` nạp bằng
`$readmemh("firmware.hex", bram)`. Các file weight `.mem` của CNN vẫn được dùng riêng.
Hai ảnh chiếm 6144 byte, nên ảnh được truyền trực tiếp vào bộ nhớ CNN thay vì nhúng
vào BRAM 4096 byte chứa chương trình và stack.

## Các file

| File | Chức năng |
|---|---|
| `main.c` | Chương trình chính, UART, kiểm tra BRAM và điều khiển CNN |
| `soc.h` | Địa chỉ MMIO và bit điều khiển đúng với RTL hiện tại |
| `start.S` | Điểm reset, khởi tạo stack/global pointer và xóa BSS |
| `linker.ld` | Đặt chương trình tại địa chỉ 0, dành ít nhất 512 byte stack |
| `build.py` | Biên dịch và đổi ELF sang 1024 word hex 32 bit |
| `firmware.hex` | Ảnh BRAM đã build, có thể dùng ngay |
| `host.py` | Công cụ PC gửi hai file ảnh `.mem` hiện có qua UART |
| `add_to_vivado.tcl` | Đăng ký ảnh firmware trong project đang mở |
| `sim/run.ps1` | Mô phỏng toàn bộ CPU/BRAM/UART/CNN bằng XSim |

## Build trên Windows

Chạy từ thư mục gốc repository:

```powershell
py firmware/build.py
```

Script tìm RISC-V GCC trong `PATH`, `RISCV_GCC`, hoặc bộ công cụ AMD/Xilinx đã cài.
Máy hiện tại có compiler ở:

```text
C:/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-gcc.exe
```

Có thể chọn compiler khác:

```powershell
py firmware/build.py --gcc "C:/path/to/riscv32-unknown-elf-gcc.exe"
```

Script dùng `-march=rv32i -mabi=ilp32 -Os -nostdlib`, xuất ELF, map và disassembly
trong `firmware/build/`, đồng thời cập nhật hai file giống nhau:

```text
firmware/firmware.hex
SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/firmware.hex
```

Hex có đủ **1024 dòng**, mỗi dòng 8 chữ số hex. Bốn byte liên tiếp từ ELF được
đóng gói little-endian thành một word BRAM. Linker báo lỗi nếu code/data/BSS lấn
vào phần stack đã dành. Không cần chạy `objcopy` hoặc cài thư viện Python để build.

## Dùng trong Vivado

Project `.xpr` đã được bổ sung `firmware.hex` vào Design Sources với loại
`Memory Initialization Files`. Nếu Vivado đang mở project từ trước, chạy trong
**Tcl Console** để cập nhật phiên đang mở:

```tcl
source D:/SoC/custom_SOC-main/custom_SOC-main/firmware/add_to_vivado.tcl
```

Sau khi thay firmware, chạy lại synthesis/implementation/generate bitstream để
ảnh khởi tạo BRAM mới được đưa vào FPGA. Với mô phỏng, đóng rồi chạy lại simulation.

RTL `soc_top.v` được sửa hai khai báo cần thiết:

```verilog
wire mem_ready;
wire [31:0] mem_rdata;
```

Trước đó `mem_rdata` là implicit net 1 bit, làm mất dữ liệu lệnh của CPU.

**`tb_CNN` chỉ kiểm tra ngoại vi CNN và không chạy CPU.** Dùng testbench
`firmware/sim/tb_firmware.v` để quan sát firmware boot và thực thi. Khi tự chạy
simulator ngoài project, đặt `firmware.hex` vào working directory của simulator.

## Gửi ảnh từ PC

Nạp bitstream mới lên FPGA, kết nối UART TX/RX và GND đúng với board, đóng các
terminal khác đang giữ cổng COM. Chọn clock/baud trùng với cấu hình SoC. Project
hiện chưa có đầy đủ gán chân `PACKAGE_PIN` cho board, cần dùng XDC đúng phần cứng.

Cài thư viện cho công cụ host (chỉ cần khi dùng UART với board):

```powershell
py -m pip install -r firmware/requirements.txt
```

Ví dụ dùng `COM5`, thay bằng cổng thực tế:

```powershell
# Kiểm tra truyền dữ liệu bằng ảnh đen: baseline + DMA0 + DMA1.
py firmware/host.py --port COM5 --mode smoke

# Ảnh human qua AXI-Lite, kiểm tra nhãn mong đợi bằng 1.
py firmware/host.py --port COM5 --mode baseline --expect 1

# Ảnh nonhuman qua DMA buffer 1, mong đợi bằng 0.
py firmware/host.py --port COM5 --mode dma1 --frame CNN_RTL/nonhuman_frame.mem --expect 0

# Nạp human vào buffer 0, nonhuman vào buffer 1, rồi chạy hai lần ping-pong.
py firmware/host.py --port COM5 --mode pingpong --check-labels
```

Mỗi file ảnh chứa 1024 giá trị RGB24 hex. Mặc định host dùng
`CNN_RTL/human_frames.mem` và `CNN_RTL/nonhuman_frame.mem`.
`--check-labels` kiểm tra nhãn 1/0; độ chính xác phân loại phụ thuộc ảnh và trọng số.
Smoke dùng ảnh đen để kiểm tra các đường truyền cho cùng kết quả, không đánh giá
độ chính xác nhận diện người.

Đầu ra boot:

```text
SOC BRAM READY
BOOT PASS
READY
```

Kết quả mỗi lần suy luận có dạng:

```text
RESULT 1 STATUS 00000006 CYCLES 00020000 READS 00000300
READY
```

Các số ở `STATUS`, `CYCLES`, `READS` là hex. Ví dụ trên minh họa định dạng;
`CYCLES` thực tế do RTL đo. `READS=00000300` nghĩa là 768 lần đọc DMA.

## Giao thức UART

| Lệnh một byte | Hành vi |
|---|---|
| `?` | In danh sách lệnh và `READY` |
| `B` | In `SEND`, nhận đúng 3072 byte RGB rồi chạy baseline |
| `0` | In `SEND`, nhận ảnh vào buffer 0 rồi chạy DMA buffer 0 |
| `1` | In `SEND`, nhận ảnh vào buffer 1 rồi chạy DMA buffer 1 |
| `P` | Chạy hai buffer đã nạp, kiểm tra tự đổi buffer sau lần START đầu |
| `z` | Ghi ảnh đen vào ba vùng ảnh, chạy baseline/DMA0/DMA1 và so sánh |

Sau `SEND`, truyền **byte nhị phân R,G,B liên tục**, không truyền chuỗi hex ASCII
hay thêm newline. Firmware đóng gói bốn byte thành `b0<<24 | b1<<16 | b2<<8 | b3`
để khớp `dma32_to_rgb24.MSB_FIRST=1`. Host chờ `SEND` rồi mới gửi ảnh.

Mỗi lệnh kết thúc bằng `READY`. `P` yêu cầu đã nạp đủ hai buffer bằng `0` và `1`;
cấu hình không bị ghi lại giữa hai lần START. Lệnh `z` thay nội dung hai buffer
bằng ảnh đen. Nếu quá trình upload bị ngắt, reset SoC trước khi truyền lại để đồng
bộ biên frame. UART có một thanh ghi RX; có thể dùng `--byte-delay-ms` để giảm tốc
gửi nếu cấu hình clock thấp hơn hoặc kết nối thực tế cần thêm khoảng cách byte.

## Bản đồ bộ nhớ dùng bởi firmware

| Địa chỉ | Chức năng |
|---|---|
| `0x00000000..0x00000fff` | BRAM chương trình, dữ liệu và stack |
| `0x40000000` | UART TX, ghi 8 bit thấp |
| `0x40000004` | UART RX, đọc để xóa cờ RX |
| `0x40000008` | UART status: bit 0 TX ready, bit 1 RX ready |
| `0x40004000..0x40004bff` | 768 word ảnh baseline |
| `0x40004fe0` | DMA base address |
| `0x40004fe4` | CNN CONFIG |
| `0x40004fe8/0x40004fec` | Compute cycles / DMA reads |
| `0x40004ff4/0x40004ff8/0x40004ffc` | Result / Status / Start |
| `0x40006000..0x40006bff` | DMA buffer 0 |
| `0x40006c00..0x400077ff` | DMA buffer 1 |

Global `fw_report` lưu magic `0x534f4346`, giai đoạn, kết quả, status, cycles,
DMA reads và số bài kiểm tra thành công/thất bại. Địa chỉ cụ thể xem
`firmware/build/firmware.map`. `stage=1`: boot; `2`: đang suy luận; `3`: chờ lệnh.

Với bản build hiện tại, `fw_report` bắt đầu tại `0x958`, tương ứng
`tb_firmware.dut.bram[598]`. Các word tiếp theo lần lượt là `stage`,
`classification`, `status`, `cycles`, `dma_reads`, `passes`, `failures`.
Khi quan sát waveform, thêm `dut.u_cpu.reg_pc`, `dut.mem_addr`, `dut.mem_rdata`,
`dut.cpu_trap`, `dut.u_cnn.busy_reg` và các word BRAM này. Sau khi thay chương
trình và build lại, tra file map để lấy địa chỉ mới.

## Kiểm tra mô phỏng

```powershell
py firmware/build.py
powershell -ExecutionPolicy Bypass -File firmware/sim/run.ps1

# Kiểm tra thêm ảnh thật, hai buffer và cơ chế tự đổi ping-pong:
powershell -ExecutionPolicy Bypass -File firmware/sim/run.ps1 -FullImages

# Kiểm tra đúng baud mặc định của phần cứng:
powershell -ExecutionPolicy Bypass -File firmware/sim/run.ps1 -BaudRate 115200
```

Script mặc định tăng baud trong testbench lên 1 Mbaud để rút ngắn thời gian mô
phỏng, clock vẫn 100 MHz; không đổi baud mặc định trong RTL. Mô phỏng sử dụng CPU
PicoRV32 thật, ảnh firmware trong BRAM, tín hiệu UART nối tiếp thật và CNN thật.
Log nằm trong `firmware/build/sim/`; thành công có `FIRMWARE INTEGRATION PASS`.

Kết quả đã xác nhận với bản firmware đi kèm:

- Smoke ở baud phần cứng **115200**: PASS, CPU không trap.
- Ảnh human qua baseline và DMA buffer 0: phân loại **1**.
- Ảnh nonhuman qua DMA buffer 1: phân loại **0**.
- Ping-pong tự chuyển buffer: human **1**, sau đó nonhuman **0**.
- Cả 1024 pixel nhận được trong mỗi lần chạy ảnh thật khớp hoàn toàn file nguồn.
- Tổng bài full integration: **8 lượt CNN**, **4608 giao dịch đọc DMA**;
  mỗi lượt DMA đọc đúng 768 word.
- Code/data/BSS chiếm **2424 byte**, dành **512 byte** stack và còn **1144 byte**
  trống trước stack; 16 byte trên cùng BRAM không dùng.

Log ảnh thật: `firmware/build/sim/full_images.log`; log baud 115200:
`firmware/build/sim115200/simulate.log`. Bài ảnh thật mô phỏng UART ở 1 Mbaud,
mất khoảng 9 phút trên máy hiện tại. Chưa kiểm tra trên board vật lý.

## Clock gating CNN

`CNN.v` dùng một `BUFGCE` cấp clock riêng cho `dma32_to_rgb24` và
`cnn_docx_reference`. Clock được mở khi reset, có START, đang BUSY hoặc đang
hoàn tất xung kết quả; khi rảnh, hai khối tự ngừng clock. AXI, bộ điều khiển DMA
và các thanh ghi STATUS/RESULT vẫn dùng clock gốc. Không cần đổi firmware.

Kiểm tra bằng mô hình BUFGCE của Xilinx, năm lượt ảnh thật qua baseline/DMA,
ghi từng phần/zero-strobe, giữ nội dung frame RAM qua reset, backpressure,
đọc AXI khi nghỉ và reset khi nghỉ/đang chạy:

```powershell
powershell -ExecutionPolicy Bypass -File firmware/sim/run_cnn_clock_gating.ps1 -VivadoBin D:/Vivado_data/2025.2/Vivado/bin
```

Log tại `firmware/build/sim_cnn_clock_gating/simulate.log`; kết quả thành công
có `CNN CLOCK GATING PASS`. Script chỉ đổi đường dẫn weight tuyệt đối trong
bản sao mô phỏng, không sửa file RTL gốc hoặc ảnh firmware đang chọn.

## Frame buffer CNN dùng BRAM

`CNN.v` khai báo `frame_mem` với `ram_style="block"`, tách cổng ghi theo byte
và cổng đọc đồng bộ. Khi START, cổng đọc lấy word 0; mỗi lần bộ chuyển RGB nhận
một word, RAM đọc trước word kế tiếp. Word đã đọc được giữ nguyên trong lúc
phía nhận chờ, nên không cần thêm khoảng trống giữa các word. RAM và thanh ghi
dữ liệu đọc không bị xóa khi reset; `frame_send_valid` ngăn dùng dữ liệu chưa
hợp lệ. Đọc/ghi đồng thời cùng word có ngữ nghĩa read-first.

Register map AXI, lựa chọn baseline/DMA và firmware giữ nguyên. Chạy bài test
ở trên để kiểm tra cả luồng baseline từ BRAM và đường DMA.

Synthesis đối chứng trên `xc7a200tfbg676-1` bằng Vivado 2025.2: tổng LUT SoC
giảm từ **5097 xuống 4235** (giảm 862 LUT, 16,9%); LUTRAM giảm từ 1734 xuống
966 và BRAM tile tăng từ 7 lên 8. `frame_mem` được ánh xạ vào một RAMB36E1.
Đây là số liệu synthesis, chưa phải sau place/route. Báo cáo và log kiểm tra:
`firmware/build/cnn_frame_bram_20261028/RESULT.md`.
