# Tài liệu CNN: kiến trúc, địa chỉ và tối ưu hiện tại

Cập nhật: **28/10/2026**, đối chiếu RTL trong
`SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/`.
Cấu hình board/device hiện tại xem [README](README.md).

## 1. Kiến trúc và luồng dữ liệu

```text
PicoRV32 -> AXI4-Lite CNN -> frame_mem BRAM 768 x 32 bit --+
                                                        |
PicoRV32 -> bộ nhớ hai buffer -> CNN DMA đọc từng word ---+
                                                        v
                                    dma32_to_rgb24 -> CNN FSM -> RESULT
```

Một frame RGB888 gồm 32 x 32 pixel, 3072 byte, tương đương 768 word 32 bit.
Packer dùng `MSB_FIRST=1`, ghép liên tục byte R/G/B kể cả pixel nằm qua ranh giới
hai word. Hai buffer DMA là bộ nhớ on-chip trong `cnn_memory_subsystem.v`, chưa
phải controller DDR ngoài của board.

| Tầng | Tensor đầu ra |
|---|---|
| Input | 32 x 32 x 3 |
| Conv1, kernel 3 x 3 | 30 x 30 x 4 |
| MaxPool 2 x 2 | 15 x 15 x 4 |
| Conv2, kernel 3 x 3 | 13 x 13 x 4 |
| MaxPool 2 x 2 | 6 x 6 x 4 |
| Conv3, kernel 3 x 3 | 4 x 4 x 4 |
| MaxPool 2 x 2 | 2 x 2 x 4 |
| FC | 16 giá trị -> 1 bit phân loại |

Core hiện dùng **một MAC dùng chung**, tách các pha địa chỉ, đọc RAM, chuẩn hóa,
nhân, cộng và ghi kết quả. Không phải bản 4 MAC song song được mô tả trong tài
liệu trước đây. Trọng số/activation signed 8 bit, tích 16 bit, accumulator 32 bit.
QReLU dịch phải 4 bit rồi giới hạn về 0..127. Kết quả 1 = human, 0 = non-human;
chỉ đọc kết quả khi STATUS.done đã lên.

## 2. Các file chính

| File | Chức năng |
|---|---|
| `CNN.v` | AXI4-Lite, BRAM frame, DMA control, clock gating và status |
| `cnn_docx_reference.v` | Core CNN tuần tự dùng một MAC |
| `dma32_to_rgb24.v` | Ghép word 32 bit thành pixel RGB24 |
| `cnn_memory_subsystem.v` | Hai buffer on-chip cho DMA |
| `Tb_CNN.v` | Module `tb_CNN`, test baseline/DMA/ping-pong trong Vivado |
| `firmware/sim/tb_cnn_clock_gating.v` | Regression clock gating và frame BRAM |

Bốn weight đang được core đọc bằng đường dẫn tuyệt đối tới `new/source/` dưới
`D:/LAB/custom_SOC-main`. Khi clone sang máy/thư mục khác phải cập nhật đường dẫn.
Firmware CPU là file `firmware.hex` riêng, không phải weight của CNN.

## 3. Địa chỉ CPU

| Địa chỉ | Chức năng |
|---|---|
| `0x40004000..0x40004BFF` | Baseline frame, 768 word; word cuối tại `0x40004BFC` |
| `0x40004FE0` | DMA base, mặc định `0x40006000` |
| `0x40004FE4` | CONFIG: số word [9:0], DMA [16], ping-pong [17], buffer [18] |
| `0x40004FE8` | Số chu kỳ của lượt chạy cuối |
| `0x40004FEC` | Số DMA read-address handshake |
| `0x40004FF0` | Bộ đếm giao dịch ghi baseline frame |
| `0x40004FF4` | RESULT, classification bit 0 |
| `0x40004FF8` | STATUS: busy [0], done [1], DMA [2], buffer [3], ping-pong [4] |
| `0x40004FFC` | CONTROL: ghi bit 0 để START |
| `0x40006000..0x40006BFF` | DMA buffer 0 |
| `0x40006C00..0x400077FF` | DMA buffer 1 |

Số word cấu hình bằng 0 hoặc lớn hơn 768 được quy về 768. Trong DMA, nếu số
word nguồn nhỏ hơn 768, phần còn lại được đệm zero để core vẫn nhận đủ frame.

**Không thay CONFIG trong lúc BUSY.** RTL chốt địa chỉ DMA và buffer đang dùng
khi START, nhưng `dma_enable_reg`, `frame_words_reg`, `pingpong_enable_reg` vẫn
là cấu hình sống. Chưa có snapshot đầy đủ hoặc khóa ghi CONFIG khi đang chạy;
nhận định ngược lại trong tài liệu trước đây đã được sửa.

## 4. Clock gating CNN

```verilog
wire cnn_clk_en = rst | start_pending | busy_reg | cnn_result_valid;
BUFGCE #(.SIM_DEVICE("7SERIES")) u_cnn_clock_gate (
    .I(clk), .CE(cnn_clk_en), .O(cnn_clk)
);
```

Clock này chỉ cấp cho packer và core CNN. AXI, frame BRAM và bộ điều khiển DMA
vẫn dùng clock hệ thống. Reset mở clock để reset đồng bộ tới core; giữ clock qua
`cnn_result_valid` giúp core xóa xung kết quả và quay về nhận frame trước khi nghỉ.
Đây là clock gating, không phải ngắt nguồn FPGA.

Đối chứng riêng trên `xc7a200tfbg676-2L`, cùng RTL/weight/cấu hình tổng hợp:
không gating 5115 LUT, có gating 5097 LUT; số clock buffer tăng 3 lên 4. Kết quả
này không xác nhận mức tăng khoảng 2000 LUT là do BUFGCE. Các build cũ thiếu
weight không phải mốc so sánh hợp lệ; cũng chưa phải phép đo tiết kiệm điện.

## 5. Frame memory dùng BRAM

`frame_mem[0:767]` có `ram_style="block"`, cổng ghi theo byte/WSTRB và cổng đọc
đồng bộ. START đọc word 0; mỗi lần packer nhận một word thì đọc trước word kế
tiếp. Thanh ghi dữ liệu giữ nguyên khi packer chờ. RAM không bị xóa bởi reset;
phải nạp đủ frame hợp lệ trước lần sử dụng đầu. Đọc/ghi đồng thời cùng word có
ngữ nghĩa read-first.

Đối chứng Vivado 2025.2, **Artix-7 `xc7a200tfbg676-1`**, 100 MHz,
`DDR_TX_PHASED_CLOCK=1`, không áp XDC:

| Tài nguyên SoC | Trước | Sau |
|---|---:|---:|
| LUT | 5097 | 4235 |
| LUTRAM | 1734 | 966 |
| FF | 2426 | 2398 |
| BRAM tile | 7 | 8 |

Giảm 862 LUT (16,9%); frame RAM ánh xạ vào một RAMB36E1. Đây là kết quả
synthesis cũ trên Artix, không phải kết quả place/route hoặc target Zynq hiện tại.

## 6. Kiểm tra chức năng

Chạy từ thư mục gốc repo, chỉnh đường dẫn Vivado theo máy:

```powershell
powershell -ExecutionPolicy Bypass -File firmware/sim/run_cnn_clock_gating.ps1 -VivadoBin D:/Vivado_data/2025.2/Vivado/bin
```

Regression đã ghi nhận PASS **5 lượt ảnh**, đối chiếu toàn bộ 1024 pixel và kết
quả mỗi frame, baseline/DMA liên tiếp, trở lại baseline sau DMA, ghi từng phần,
zero WSTRB, backpressure, giữ RAM qua reset, AXI khi nghỉ và reset khi idle/busy.
Marker thành công: `CNN CLOCK GATING PASS`.

Runner dùng mô hình BUFGCE của Xilinx, sao chép weight từ `new/` và sửa đường dẫn
trong bản core mô phỏng, không sửa RTL gốc. Giữ các weight này đồng nhất với
`new/source/`. Log mới được tạo trong `firmware/build/sim_cnn_clock_gating/`.
Hướng dẫn test CPU/UART nằm trong [firmware/README.md](firmware/README.md).

## 7. Công suất và công việc còn lại

LUT giảm không bảo đảm tổng power giảm. Các report Artix trước đây có khác
part/MMCM/netlist và dùng hoạt động vectorless; chưa đủ để quy thay đổi công
suất cho BRAM. So sánh điện cần cùng device, clock, constraint và workload,
ưu tiên dữ liệu chuyển mạch thực tế từ mô phỏng.

Các lỗi arbiter CPU/DMA, ghi địa chỉ AW và cấu hình sống vẫn được ghi trong
[review SoC](SOC_REVIEW_2026-10-27.md). Sửa tính đúng trước khi thử AXI burst,
prefetch hoặc đổi activation RAM sang BRAM. Không thể chỉ thêm attribute cho
mọi mảng rồi mặc định sẽ suy ra BRAM đúng hoặc giảm công suất.
