**Rà soát SoC — 27/10/2026**

**Cập nhật trạng thái ngày 28/10/2026:** nội dung bên dưới giữ bằng chứng của
lần review 27/10. Lỗi đường dẫn weight ở mục 1 đã được sửa cho workspace
`D:/LAB/custom_SOC-main`: core đọc bốn file trong `new/source/`. Đường dẫn vẫn
là tuyệt đối nên cần cập nhật nếu chuyển máy. Frame memory của `CNN.v` đã đổi
sang BRAM, regression clock gating/BRAM đã PASS năm lượt ảnh. Các lỗi tranh
chấp CPU/DMA, địa chỉ AW, parallel và I2C trong review chưa được sửa.

Project hiện chọn `xc7z020iclg400-1L`, trong khi XDC vẫn gán chân Artix-7
XCM-208A; các report Artix và số dòng dưới đây là dữ liệu lịch sử. Cấu hình
mới nhất xem [README](README.md), chi tiết CNN xem
[tài liệu CNN](CNN_documentation_optimization.md). Các log trong `firmware/build/`
là artifact cục bộ bị `.gitignore` loại khỏi các bản cập nhật mới, không phải
file bắt buộc có sẵn khi clone repository.

Đã rà soát 13 file RTL trong cây `soc_top`, ba file phụ/legacy cùng thư mục,
cấu hình project Vivado, XDC 100 MHz, báo cáo synthesis/implementation gần nhất
và firmware điều khiển CNN. Trong lượt rà soát này không sửa RTL, firmware hay
project gốc. Các phép thử dùng bản sao trong `firmware/build/soc_review_20261027/`.
Đây là review có các trường hợp mô phỏng tái hiện; không phải formal verification
hoặc xác nhận toàn bộ giao thức/board.

**Các vấn đề cần sửa trước khi tối ưu**

1. **P1 — Bốn file weight không được nạp trong build project hiện tại.**

   Vị trí: `SOC_HUFLIT_2026.srcs/sources_1/new/cnn_docx_reference.v:37`.
   Bốn lệnh `$readmemh` vẫn chứa đường dẫn tuyệt đối `D:/SoC/...`, trong khi
   workspace hiện tại ở `D:/LAB/custom_SOC-main`.
   `SOC_HUFLIT_2026.runs/synth_100MHz/runme.log:124` báo bốn `Synth 8-4445`.
   Bộ nhớ weight không có nội dung khởi tạo hợp lệ, nên chức năng phân loại
   không được bảo đảm và synthesis có thể loại bỏ logic phụ thuộc dữ liệu này.
   Không dùng mức LUT thấp của build đó làm chuẩn so sánh tối ưu CNN.

   Sửa: dùng tên file tương đối, đăng ký các file memory trong project và kiểm
   tra log đọc thành công đủ bốn file. Sau đó synthesis/implementation lại.
   Bản sao thử nghiệm đã thực hiện bước này và nạp thành công cả firmware lẫn
   bốn weight; không sửa đường dẫn trong RTL gốc.

2. **P1 — CPU và DMA có thể khóa nhau khi cùng đọc bộ nhớ CNN.**

   Vị trí: `cnn_memory_subsystem.v:83` và `:84`.
   `DMA_ARREADY` chỉ lên khi CPU không có `ARVALID`, còn `S_AXI_ARREADY` chỉ
   lên khi DMA không có `ARVALID`. Khi cả hai yêu cầu cùng tồn tại, cả hai
   READY đều bằng 0. Hai master giữ VALID chờ handshake, nên không bên nào tiến.
   Điều này xảy ra khi CPU đọc cửa sổ frame buffer đúng lúc CNN DMA đọc;
   CPU chỉ polling STATUS của CNN thì không tranh chấp cổng này.

   Mô phỏng đã giữ hai yêu cầu trong 20 clock: không có handshake hay response.
   Sửa: arbiter có một bên thắng khi đồng thời yêu cầu, ví dụ ưu tiên DMA,
   hoặc round-robin nếu phải bảo đảm CPU không bị chờ lâu. Giữ grant/response
   nhất quán khi có backpressure.

3. **P1 — Bộ nhớ CNN có thể ghi sai địa chỉ sau AW handshake.**

   Vị trí: `cnn_memory_subsystem.v:67`, `:70`, `:114`.
   Module đã chốt `awaddr_reg`, nhưng `cpu_write_offset` và `cpu_write_index`
   lại tính từ `S_AXI_AWADDR` đang chạy trên bus. AWADDR được phép đổi sau khi
   AW đã được nhận; đến khi `write_fire` xảy ra, module có thể dùng địa chỉ khác.

   Đã tái hiện: nhận AW tại `0x40006000`, đổi bus sang `0x40006004`, rồi gửi W.
   Dữ liệu `0xabcd1234` ghi vào word thứ hai thay vì word đầu.
   Adapter CPU hiện tại thường giữ địa chỉ đến khi hoàn tất, nên che được lỗi;
   lỗi xuất hiện khi dùng master khác hoặc bổ sung pipeline.
   Sửa: tính toàn bộ địa chỉ ghi và kiểm tra giới hạn từ `awaddr_reg` đã chốt.

4. **P2 — Kết quả DDR có thể khác kết quả CPU đọc.**

   Vị trí: `parallel.v:392` và `:446`.
   Thanh ghi CPU đọc là `reg_result`, nhưng serializer nhận `result_flat`,
   tức tổng tổ hợp của các toán hạng hiện tại. Một lane hoàn thành sớm, sau đó
   toán hạng của lane ấy đổi trước khi đủ kết quả các lane, thì gói DDR sử dụng
   tổng mới thay cho kết quả đã lưu.

   Đã tái hiện: lane 0 hoàn tất `1 + 10 = 11`; đổi A thành 100 rồi cho các lane
   còn lại hoàn tất. Thanh ghi lane 0 giữ 11, nhưng serializer nạp 110.
   Sửa: serializer lấy một snapshot từ `reg_result`; bảo vệ snapshot cho đến
   khi toàn bộ packet được nhận. Chỉ đổi nguồn dây chưa đủ nếu các lane vẫn
   được phép ghi đè snapshot giữa hai pha gửi.

5. **P2 — I2C không giữ trạng thái bus sau START.**

   Vị trí: `axi_i2c_slave.v:116`, `:125`, `:126`.
   FSM thực hiện START rồi trở về state 0, nơi SCL/SDA đều bị đưa lên 1.
   Mô phỏng chỉ gửi lệnh START nhưng bộ quan sát bus ghi nhận một START và một
   STOP, không có byte dữ liệu. Cần giữ trạng thái bus giữa START, DATA/ACK và
   STOP; không dùng cùng một IDLE để vừa biểu thị bus rảnh vừa chờ lệnh tiếp theo
   trong một giao dịch đang mở.

   Bộ đếm cố định cũng cho khoảng 1,96 MHz ở phần gửi bit khi clk=100 MHz,
   không phải cấu hình Standard/Fast mode 100/400 kHz. Nên thêm tham số tần số
   SCL theo clock hệ thống và kiểm tra START → address → ACK → data → ACK → STOP
   với mô hình slave thực. Open-drain của SDA/SCL phải được kiểm tra ở wrapper
   chân board; hiện top xuất các tín hiệu riêng chứ chưa thể hiện đầy đủ bus I2C.
   Các mode và trình tự bus được mô tả trong [NXP UM10204](https://www.nxp.jp/docs/en/user-guide/UM10204.pdf).

**Các hạn chế giao diện và timing**

- `soc_top.v:88`, `:309` và `soc_axi_top.v:97`: địa chỉ MMIO không được decode
  không có error responder. Master có thể đợi vô hạn. Nên bổ sung phản hồi lỗi
  hoặc timeout chẩn đoán; adapter MMIO hiện không chuyển BRESP/RRESP thành lỗi
  CPU, nên phải thiết kế cả cách phần mềm quan sát lỗi.
- `soc_top.v:382` và `:399`: `axi_m_bresp`/`axi_m_rresp` chưa khai báo, thành
  implicit wire một bit và bị cắt phản hồi hai bit. Sửa khai báo `[1:0]`, bổ sung
  lint/`default_nettype none` có phạm vi phù hợp cho RTL tự viết. Không áp dụng
  mù quáng lên mã vendor.
- UART/SPI/I2C/parallel và các CSR CNN chưa có chính sách WSTRB thống nhất.
  Mô phỏng xác nhận ghi `WSTRB=0000` vẫn đổi thanh ghi UART/SPI/I2C. Đây là
  hạn chế cần ghi rõ hoặc bổ sung xử lý, không mặc định kết luận sai chuẩn:
  AXI4-Lite cho phép một số peripheral bỏ qua strobes và xử lý như ghi full word.
  Bộ nhớ vẫn phải tôn trọng byte enable; phần frame memory hiện có xử lý strobes.
  Xem [Arm AXI specification](https://documentation-service.arm.com/static/64256e84314e245d086bc88f?token=).
- `CNN.v:227`: CONFIG có thể đổi trong lúc BUSY; `dma_enable_reg` được dùng trực
  tiếp để chọn dữ liệu tại `:102`. Nếu phần mềm đổi chế độ giữa frame thì đường
  dữ liệu bị đổi ngay. Nên chốt cấu hình active ở START hoặc từ chối cập nhật
  cấu hình có ảnh hưởng khi BUSY. Firmware hiện chỉ đổi CONFIG giữa các frame.
- Báo cáo routed hiện có: WNS `+0,118 ns`, WHS `+0,005 ns`, nhưng vẫn thiếu
  input delay cho 37 input và output delay cho 8 output, cùng một output clock.
  DDR RX 32 bit/valid chưa có mô tả timing đầu vào. Timing PASS chỉ áp dụng
  các đường đã ràng buộc và build này còn lỗi nạp weight nói trên.
- `parallel.v:163`: reset serializer tạo bởi phép AND được đưa vào nhiều chân
  reset bất đồng bộ. Báo cáo methodology có `LUTAR-1` cho 69 chân.
  Nên tổ chức reset có assert an toàn và release đồng bộ theo clock nhận,
  đặc biệt khi MMCM chưa lock hoặc mất lock. Không che bằng false path rộng.
- `axi_uart_slave.v:139`: đã có hai FF đồng bộ RX nhưng thiếu thuộc tính
  `ASYNC_REG`. Nên đánh dấu chuỗi đồng bộ và xem báo cáo CDC sau khi khai báo
  đúng các nguồn bất đồng bộ. SPI MISO và DDR RX cần timing theo giao thức;
  không thêm hai FF cho cả bus dữ liệu để thay cho thiết kế giao diện.
  Xem [AMD ASYNC_REG](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/ASYNC_REG).
- Báo cáo CDC trong thử nghiệm chỉ có clock nội bộ được khai báo; Vivado ghi
  rõ bỏ qua input không có input delay. Dòng "All paths are Safely Timed"
  trong báo cáo đó không chứng nhận các chân ngoài/board an toàn.

**Số liệu synthesis với đủ weight**

Thiết bị `xc7a200tfbg676-2L`, Vivado 2025.2, `soc_top`, `CLK_FREQ=100000000`,
`DDR_TX_PHASED_CLOCK=1`. Chỉ sửa đường dẫn weight trong bản sao. Synthesis có
0 error, 0 critical warning; chưa place/route bản sao này.

| Hạng mục | Kết quả |
|---|---:|
| Tổng LUT | 5.097 |
| LUT logic | 3.363 |
| LUTRAM | 1.734 |
| FF | 2.426 |
| BRAM tile | 7 = 6 RAMB36 + 2 RAMB18 |
| DSP | 0 |
| CNN LUT, gồm LUTRAM | 2.773 |
| CNN LUTRAM | 1.646 |
| CPU LUT | 1.256 |
| Parallel LUT | 458 |

Synthesis timing với clock 10 ns cho WNS `+0,897 ns`, WHS `+0,015 ns`.
Đây là ước lượng trước route, chưa có đầy đủ I/O constraints, không dùng để
khẳng định board chạy ổn định ở 100 MHz.

**Các tối ưu nên cân nhắc, theo thứ tự thực tế**

| Phần | Đề xuất | Giá trị / điều kiện |
|---|---|---|
| CNN frame buffer | Đổi `frame_mem[768]` sang RAM đọc đồng bộ có prefetch/valid | Đang chiếm 768 LUTRAM vì đọc tổ hợp; có thể chuyển sang BRAM và giảm mux, cần sửa handshake để giữ đúng word đầu và backpressure |
| Activation CNN | Tách RAM và các cổng đọc/ghi rõ ràng cho `c1`, `p1`, sau đó các buffer lớn khác | Nhóm activation dùng 878 LUTRAM; cần viết lại template phù hợp BRAM |
| MAC | Thử dùng DSP48 cho phép nhân 8×8/MAC với pipeline hiện có | Hiện 0 DSP; đo LUT, timing và power thay vì mặc định DSP luôn tốt hơn |
| Accumulator | Xem xét giảm 32 xuống 21 bit signed theo miền dữ liệu hiện tại | C2/C3 có tối đa 36 tích 8-bit; bound bảo thủ 36×128×128=589.824 vừa 21 bit signed; phải giữ đúng sign extension, saturation và chạy equivalence |
| PicoRV32 | Tắt counters 64 bit hoặc counters/IRQ timer nếu phần mềm không dùng | Firmware hiện không dùng rdcycle/rdinstret hay IRQ; giữ tùy chọn nếu cần mở rộng về sau, không bật RV32E vì firmware đang dùng ABI ilp32 đầy đủ |
| UART/SPI/I2C | Thu gọn counter theo `$clog2`, tham số hóa divider | UART 100 MHz/115200 chỉ cần counter bit-period khoảng 10 bit thay vì 16; SPI/I2C hiện dùng divider cố định |
| Nhập frame | Tăng tốc đường truyền, rồi mới tăng số MAC | 3072 byte RGB qua UART 115200 8N1 mất tối thiểu 266,7 ms; 1 Mbaud mất 30,72 ms. CNN pipeline có log khoảng 768.278 cycle ≈7,68 ms tại 100 MHz, nên UART đang là nút thắt khi upload từng frame |
| Ping-pong | Cho phép upload vào buffer không active khi CNN đang tính | Firmware hiện từ chối upload nếu CNN_BUSY; có hai buffer nhưng chưa có luồng upload/compute đồng thời. Lợi ích bị giới hạn nếu UART vẫn chậm |
| DDR parallel | FIFO/snapshot kết quả và quy ước tốc độ đầu vào | Không có backpressure ra ngoài cho DDR RX; stream liên tục cần quy ước throttle hoặc hàng đợi và cờ overflow |
| Điện năng | Dùng SAIF theo chế độ chạy/nghỉ để so sánh trước/sau clock gating | Báo cáo hiện có 0,375 W nhưng Confidence=Low, không có activity file và còn lỗi weight; chưa thể dùng để định lượng phần trăm tiết kiệm |
| Ngoại vi tùy chọn | Generate parameter bỏ parallel/MMCM/SPI/I2C khi ứng dụng không cần | Chỉ bỏ instance thật sự đang trong cây top mới giảm phần cứng; xóa file legacy khỏi Sources không tự giảm tài nguyên |

Đã thử riêng **chỉ thêm `ram_style="block"` cho c1/p1** trong bản sao:
Vivado báo `Synth 8-6849: Infeasible attribute`, vẫn dùng LUTRAM. Kết quả CNN
standalone vẫn 2.786 LUT, 1.646 LUTRAM và 2 BRAM tile, bằng cấu hình standalone
trước thử nghiệm. Vì vậy không nên hứa giảm tài nguyên chỉ bằng thêm attribute;
cần đổi tổ chức cổng đọc/ghi và thanh ghi đầu ra. Cách điều khiển inference và
DSP có trong [AMD RAM_STYLE](https://docs.amd.com/r/2023.2-English/ug912-vivado-properties/RAM_STYLE)
và [AMD USE_DSP](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/USE_DSP).

**Phạm vi từng file**

Các file dưới đây nằm trong
`SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/`.

| File | Kết quả rà soát |
|---|---|
| `soc_top.v` | Decode/error responder, implicit RESP width, cấu hình CPU, đường fetch BRAM |
| `picorv32.v` | Xem cấu hình counters/IRQ và native/AXI adapter; không audit lại từng opcode của CPU vendor |
| `picorv32_axi4_bram_adapter.v` | Giữ VALID khi stall, fault, latency; WAIT_NATIVE không được xóa tùy tiện vì có thể nhận lặp yêu cầu CPU |
| `axi4_bram_slave.v` | Xem request validation, burst, byte lane, synchronous backend và read pipeline; có thể tối ưu latency nếu đo CPI cho thấy cần, phải giữ contract AXI4 Full |
| `soc_axi_top.v` | Decode, chọn đích đến response, thiếu phản hồi cho địa chỉ không hợp lệ |
| `axi_uart_slave.v` | WSTRB policy, RX synchronizer, counter width; có thể thêm buffer RX/overrun nếu tăng baud |
| `axi_spi_slave.v` | WSTRB policy, divider cố định; cần timing MISO theo mode SPI |
| `axi_i2c_slave.v` | START/STOP/state giữ bus, divider, open-drain và ACK |
| `parallel.v` | Snapshot kết quả DDR, lưu lượng/backpressure, MMCM/reset và fixed NUM_LANES=4 thực tế |
| `CNN.v` | Clock gating, frame LUTRAM, cấu hình active, WSTRB CSR, DMA single outstanding |
| `cnn_docx_reference.v` | Nạp weight, pipeline, activation RAM, MAC và miền giá trị accumulator |
| `cnn_memory_subsystem.v` | Hai lỗi arbitration/địa chỉ ghi đã tái hiện; memory đã được inference BRAM |
| `dma32_to_rgb24.v` | Byte packing, valid/ready và giữ dữ liệu khi stall; chưa thấy lý do cần viết lại cho tối ưu hiện tại |
| `input_fifo_rgb.v` | Không được instance bởi `soc_top` hiện tại; không ảnh hưởng utilization hiện tại |
| `soc_apb_top.v` | Legacy, không nằm trong cây top AXI hiện tại; nếu dùng lại cần đăng ký các APB slave phụ thuộc |
| `apb_bridge.v` | Legacy, không nằm trong cây top hiện tại; không nên trộn đường APB cũ vào kết luận timing AXI |

**Bằng chứng và cách xem lại**

- `firmware/build/soc_review_20261027/review_inputs.json`: hash các RTL lúc bắt đầu;
  đã kiểm tra không RTL nào đổi trong lúc rà soát.
- `memory_review.log`, `tb_memory_review.v`: hai trường hợp deadlock và ghi sai địa chỉ.
- `peripheral_review.log`, `tb_peripheral_review.v`: hành vi WSTRB và START I2C.
- `parallel_review.log`, `tb_parallel_review.v`: CPU giữ 11 nhưng DDR nhận 110.
- `review_synth.log`, `utilization.rpt`, `utilization_hier.rpt`, `timing_synth.rpt`,
  `cdc.rpt`, `soc_valid_weights_synth.dcp`: synthesis bản sao với đủ weight.
- `ram_trial/ram_trial.log`, `ram_trial/utilization.rpt`: thử attribute RAM không
  mang lại thay đổi tài nguyên.
- `firmware/build/sim_cnn_clock_gating/simulate.log`: bài clock gating ở lượt trước,
  ba frame baseline/DMA và reset khi idle/busy đã PASS. Không thay cho các phép thử
  tranh chấp CPU/DMA hoặc địa chỉ AW thay đổi trong review này.

Các test tái hiện dùng Icarus Verilog 12; test parallel dùng primitive IDDR/ODDR
do Xilinx cung cấp. Các report synthesis dùng Vivado 2025.2. Các thử nghiệm chỉ
thêm file dưới thư mục build và tài liệu review này; chưa áp dụng tối ưu vào RTL.
