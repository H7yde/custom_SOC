# Ghi chú chỉnh sửa RTL và timing 100 MHz

Ngày lập ghi chú: **19/10/2026** (Asia/Saigon).

Project: `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr`.

Phạm vi: tổng hợp đợt chỉnh sửa timing 100 MHz đã trao đổi, gồm RTL, constraint, cấu hình project và các bài kiểm tra đi kèm. Mốc so sánh là bản sao lưu trước khi sửa pipeline; mốc này đã có firmware BRAM CPU và giao tiếp AXI của BRAM, không phải bản upstream ban đầu.

## Bảng so sánh trước và sau chỉnh sửa

| Hạng mục | Trước sửa timing | Sau sửa, cấu hình hiện tại | Ảnh hưởng |
| --- | --- | --- | --- |
| `CLK_FREQ` dùng khi tổng hợp | Theo mặc định RTL: 50 MHz | Project ghi đè: **100 MHz** | Tăng clock cấu hình của CPU, CNN và ngoại vi; clock vật lý còn phụ thuộc board |
| XDC 100 MHz | Đã có chu kỳ **10 ns** trong bản sao trước sửa pipeline | Giữ **10 ns**, thêm `SLEW FAST` và cập nhật chú thích | Không hạ yêu cầu setup/hold ngoài để làm timing dương |
| Cách CNN thực hiện phép tính | Nhiều bước tính địa chỉ, đọc và tính toán nằm trên cùng đường tổ hợp | Chia thành nhiều pha, có thanh ghi trung gian và bộ đếm địa chỉ | Giảm độ dài đường tổ hợp; thay đổi phần cứng và thời gian xử lý |
| Số chu kỳ CNN ở trường hợp đối chiếu không khoảng nghỉ | **129.121 chu kỳ** | **765.461 chu kỳ** | Tăng khoảng **5,9 lần**; không phải tăng tốc độ xử lý ảnh |
| Kết quả CNN | RTL trước sửa làm mẫu đối chiếu | Khớp phân loại và **32.400 activation** ở 6 trường hợp đã thử | Đã kiểm tra tương đương trên các trường hợp này |
| Trọng số và định dạng CNN | Bộ trọng số và định dạng hiện có | Giữ nguyên | Không đổi mô hình/trọng số trong đợt timing |
| File bao ngoài `CNN.v` | Bản đã sao lưu | Giống hệt theo SHA-256 | Module con `cnn_docx_reference.v` vẫn đã thay đổi |
| Clock đưa vào ODDR xuất DDR | Trực tiếp từ clock hệ thống | Qua MMCM, pha thêm **115,071429°**, khoảng **3,196 ns** ở 100 MHz | Dịch thời điểm phát clock để cân bằng setup/hold DDR |
| Clock của serializer và ODDR dữ liệu | Clock hệ thống | Vẫn clock hệ thống | Nhánh MMCM mới chỉ cấp clock cho ODDR xuất clock DDR |
| Nhả reset serializer | Theo reset hệ thống | Chờ MMCM `LOCKED` qua hai thanh ghi khi bật nhánh pha | Thêm thời gian chờ clock ổn định lúc khởi động/reset |
| ODDR xuất clock | Đã có, `D1=0`, `D2=1` | Giữ `D1=0`, `D2=1` | MMCM là phần thêm mới; ODDR đã có trước |
| SLEW ngõ ra DDR | Chưa ép FAST trong file timing | **FAST** cho data, clock, valid và done | Đổi đặc tính cạnh và độ trễ bộ đệm ngõ ra |
| Setup / hold thiết bị nhận DDR trong XDC | **2 ns / 1 ns** | **2 ns / 1 ns** | Giữ giả định của file cũ; cần đối chiếu datasheet thực |
| Output delay max / min | **+2,5 ns / −1,1 ns** | **+2,5 ns / −1,1 ns** | Giữ yêu cầu I/O cũ |
| BRAM CPU | **4 KB**, vùng byte **0x00000000–0x00000FFF** | Giữ dung lượng và vùng địa chỉ | Không mở rộng hoặc chuyển BRAM CPU sang CNN |
| Nội dung firmware BRAM | Ảnh firmware BRAM test hiện có | Giữ nguyên nội dung | Đợt timing không sửa chương trình CPU |
| Cách tìm ảnh firmware | `$readmemh` dùng đường dẫn tuyệt đối | `$readmemh("firmware.hex", bram)` | Cho phép thư mục mô phỏng/Vivado chọn ảnh firmware phù hợp |
| Bộ nhớ CNN | Bộ nhớ/subsystem riêng | Vẫn riêng biệt | Không dùng BRAM firmware CPU làm bộ nhớ ảnh CNN |
| UART | Mục tiêu **115200 baud** | Mục tiêu **115200 baud**, bộ chia tính theo `CLK_FREQ` | Giữ tham số baud; bài tích hợp UART đã ghi nhận chạy ở 50 MHz |
| SPI / I2C | Bộ đếm cố định, hoạt động theo clock hệ thống cũ | Giữ bộ đếm, clock hệ thống cấu hình tăng gấp đôi | Tốc độ tăng khoảng **2 lần khi clock vật lý thực sự tăng từ 50 lên 100 MHz**; chưa bù để giữ tốc độ cũ |
| Implementation | Các run cũ của project | Thêm `synth_100MHz` / `impl_100MHz`; Explore và ExploreWithHoldFix | Giữ run cũ, có thể thay đổi placement/routing và tài nguyên |
| Xác nhận trên board | Chưa có đầy đủ thông tin board/thiết bị ngoài | Vẫn chưa đủ pin, I/O standard và timing thực của thiết bị ngoài | Kết quả hiện tại xác nhận theo constraint đã khai báo, chưa xác nhận trên board |

**Kết quả hiện tại ở 100 MHz sau route:** setup WNS **+0,038 ns**, hold WHS **+0,049 ns**, TNS/THS **0 ns**, không có endpoint vi phạm setup/hold trong các đường đã kiểm tra. Hai giá trị nhỏ nhất thuộc nhóm `sys_clk` → `ddr_clk_out`.

**Cách đọc bảng:** kiến trúc kết nối tổng thể và bộ nhớ CPU/CNN được giữ; phần thực hiện CNN và mạch clock xuất DDR đã đổi đáng kể. Chỉ đổi tần số về 50 MHz không khôi phục CNN trước sửa. Bảng so sánh với bản sao trước đợt timing nêu trên, không phải một bản upstream sạch; profile 50 MHz có chu kỳ 20 ns, còn file XDC 100 MHz đã có chu kỳ 10 ns từ trước đợt pipeline.

## 1. Mốc sao lưu và cấu hình đang dùng

- Bản sao trước sửa RTL: `firmware/backups/before_pipeline_20261018_102557/`.
- Trong bản sao có: `cnn_docx_reference.v`, `CNN.v`, `parallel.v`, `soc_top.v`, `soc_top_100MHz.xdc`, project `.xpr` và `sha256.json`.
- Bản sao trước khi chạy trực tiếp project: `firmware/backups/before_project_run_20261018_194958/`.
- Run hiện tại được lưu trong project: `synth_100MHz` và `impl_100MHz`.
- Constraint set của run 100 MHz: `constrs_100MHz`.
- Generic trong project: `CLK_FREQ=100000000 DDR_TX_PHASED_CLOCK=1`.

Tên thư mục và module có thể vẫn chứa `50MHz`; cấu hình clock thực tế dùng để tổng hợp được quyết định bởi generic và constraint đang chọn.

## 2. Những file RTL đã sửa

Thư mục RTL: `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/`.

### `cnn_docx_reference.v`

- Chia các bước tính địa chỉ, đọc bộ nhớ, chuẩn hóa pixel, nhân, cộng, cập nhật bộ tích lũy và ghi kết quả thành nhiều chu kỳ.
- Thêm bộ đếm pha `phase[2:0]` và các thanh ghi trung gian cho địa chỉ, dữ liệu, trọng số, tích và tổng.
- Dùng các bộ đếm hàng/cột/kênh/kernel để tạo địa chỉ, thay các phép chia và lấy dư trên đường tính địa chỉ cũ.
- Viết lại chuẩn hóa pixel và lượng tử hóa bằng biểu thức tương đương để giảm logic tổ hợp.
- Giữ định dạng dữ liệu, các tầng CNN, trọng số và giao diện module. Các trường hợp đối chiếu đã chạy cho kết quả khớp từng giá trị activation và phân loại.
- Số chu kỳ ở trường hợp đối chiếu không có khoảng nghỉ: **129.121 → 765.461**, tăng khoảng **5,9 lần**. Đây là thay đổi đáng kể về thời gian xử lý.
- Đây là cách thực hiện một phép tính qua nhiều pha với MAC dùng chung; không phải pipeline chồng lấp nhận một phép MAC mới mỗi chu kỳ.

### `parallel.v`

- Thêm `CLK_FREQ` và tùy chọn `PHASED_CLOCK` cho `ddr_result_serializer`.
- Thêm `CLK_FREQ`, `DDR_TX_PHASED_CLOCK` cho `parallel_axi`, truyền xuống serializer.
- Thêm primitive phần cứng `MMCME2_ADV` và các `BUFG` để dịch pha nhánh clock xuất DDR.
- Serializer và ODDR dữ liệu vẫn dùng clock hệ thống. Chỉ clock cấp cho ODDR xuất `ddr_clk_out` dùng nhánh dịch pha.
- Giữ ODDR xuất clock kiểu đảo: `D1=0`, `D2=1`; ODDR này đã có trước khi thêm MMCM.
- Thêm mạch chờ MMCM `LOCKED`, qua hai thanh ghi đồng bộ trước khi nhả reset serializer. `ddr_ready` chỉ cho nhận dữ liệu khi serializer sẵn sàng.
- Khi tùy chọn pha bằng `0`, nhánh MMCM được bỏ qua và dùng cách cấp clock cũ.

### `soc_top.v`

- Thêm parameter `DDR_TX_PHASED_CLOCK=0` ở cuối danh sách parameter.
- Truyền `CLK_FREQ` và `DDR_TX_PHASED_CLOCK` tới `u_parallel_axi`.
- Đổi `$readmemh` từ đường dẫn tuyệt đối thành tên `"firmware.hex"`, để Vivado hoặc thư mục mô phỏng chọn đúng ảnh firmware.
- Không đổi dung lượng, vùng địa chỉ hoặc nội dung ảnh firmware BRAM CPU trong đợt sửa timing.
- Giá trị mặc định trong RTL vẫn là `CLK_FREQ=50000000`, `DDR_TX_PHASED_CLOCK=0`; project ghi đè thành cấu hình 100 MHz.

## 3. Thông số đã đặt hoặc đổi

| Hạng mục | Trước đợt sửa / profile cũ | Cấu hình hiện tại |
| --- | --- | --- |
| Generic clock hệ thống | Mặc định 50.000.000 Hz | Project đặt `CLK_FREQ=100000000` |
| Clock constraint | Profile 50 MHz: chu kỳ 20 ns | Profile 100 MHz: chu kỳ 10 ns, waveform `{0 5}` |
| Bật nhánh dịch pha DDR | Chưa có parameter này | Project đặt `DDR_TX_PHASED_CLOCK=1` |
| `CLKIN1_PERIOD` của MMCM | Chưa có MMCM | 10 ns tại 100 MHz |
| `CLKFBOUT_MULT_F` / `DIVCLK_DIVIDE` / `CLKOUT0_DIVIDE_F` | Chưa có MMCM | 10 / 1 / 10 tại 100 MHz |
| Tần số VCO nội bộ MMCM | Chưa có MMCM | 1 GHz; CPU/CNN không chạy ở tần số này |
| Tần số clock ra MMCM | Chưa có MMCM | 100 MHz, bằng tần số vào |
| `CLKOUT0_PHASE` | Chưa có MMCM | `115.071429` độ, tương đương khoảng 3,196429 ns ở 100 MHz |
| `CLKOUT0_USE_FINE_PS` | Chưa có MMCM | `TRUE` |
| `COMPENSATION` / `STARTUP_WAIT` | Chưa có MMCM | `BUF_IN` / `FALSE` |
| Điều khiển chỉnh pha động | Chưa có MMCM | `PSCLK=clk`, `PSEN=0`, `PSINCDEC=0`; dùng pha cố định |
| SLEW ngõ ra DDR | Chưa ép FAST trong file timing | `FAST` cho `ddr_data[*]`, `ddr_clk_out`, `ddr_valid`, `ddr_done` |

Lưu ý: chu kỳ 10 ns đã có trong file XDC 100 MHz được sao lưu trước khi sửa pipeline. Khi đối chiếu riêng XDC hiện tại với bản sao đó, lệnh chức năng thêm mới là `set_property SLEW FAST ...`; các phần khác chủ yếu cập nhật chú thích.

Clock 100 MHz là cấu hình mục tiêu. Khai báo XDC và `CLK_FREQ` không tự đổi clock vật lý của board; clock cấp vào SoC phải phù hợp cấu hình.

## 4. Constraint và các thông số giữ nguyên

File timing đang dùng:

`SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/constrs_1/new/soc_top_100MHz.xdc`.

| Thông số I/O được giữ từ constraint cũ | Giá trị |
| --- | ---: |
| `DDR_TSU` — setup của thiết bị nhận | 2,000 ns |
| `DDR_THD` — hold của thiết bị nhận | 1,000 ns |
| `DDR_BOARD_SKEW_MAX` — độ lệch dữ liệu đến muộn | 0,500 ns |
| `DDR_BOARD_SKEW_MIN` — độ lớn độ lệch dữ liệu đến sớm | 0,100 ns |
| Khoảng skew có dấu, dữ liệu trừ clock | −0,100 đến +0,500 ns |
| `OUT_DELAY_MAX = DDR_TSU + DDR_BOARD_SKEW_MAX` | +2,500 ns |
| `OUT_DELAY_MIN = -DDR_THD - DDR_BOARD_SKEW_MIN` | −1,100 ns |

- Giữ generated clock của `ddr_clk_out` với `-divide_by 1 -invert`. Pha MMCM được lấy từ phần cứng RTL, không khai báo pha giả để làm đẹp báo cáo.
- Giữ kiểm tra dữ liệu DDR ở cả cạnh lên và cạnh xuống; `ddr_valid`/`ddr_done` theo giả định lấy mẫu cạnh lên như file cũ.
- Không thêm false path hoặc multicycle để bỏ qua các đường CPU, BRAM, AXI hay CNN.
- File constraint 50 MHz và file constraint cũ được giữ lại trong đợt này.

Các phần giữ nguyên trong đợt timing:

- BRAM CPU: `bram[0:1023]`, mỗi word 32 bit, tổng **4 KB**, vùng byte **0x00000000–0x00000FFF**.
- BRAM CPU phục vụ CPU. CNN tiếp tục có bộ nhớ/subsystem riêng; không dùng BRAM firmware CPU làm bộ nhớ ảnh CNN.
- Nội dung firmware BRAM, trọng số CNN và định dạng dữ liệu.
- File bao ngoài `CNN.v` giống hệt bản sao trước sửa theo SHA-256; module con `cnn_docx_reference.v` bên trong đã thay đổi.
- Giá trị `BAUD_RATE=115200`, `ENABLE_MUL=0`, `ENABLE_DIV=0`, `ENABLE_IRQ=1` của `soc_top`.

## 5. Ảnh hưởng đến thời gian và ngoại vi

- Clock hệ thống được cấu hình tăng từ 50 lên 100 MHz cho CPU, CNN và các ngoại vi cùng dùng clock đó.
- UART nhận `CLK_FREQ` để tính bộ chia, mục tiêu baud vẫn 115200. Bài kiểm tra firmware qua UART được ghi nhận bên dưới chạy ở 50 MHz.
- SPI vẫn dùng bộ đếm cố định `clk_div == 5`; chưa sửa bộ chia theo tần số mới. Clock SPI trong quá trình truyền tăng từ khoảng 4,17 MHz lên 8,33 MHz khi clock hệ thống tăng gấp đôi.
- I2C vẫn dùng các ngưỡng cố định `clk_cnt == 25` và `== 50`; thời gian các pha giảm một nửa khi tăng clock hệ thống từ 50 lên 100 MHz.
- Do CNN cần nhiều chu kỳ hơn, tăng clock lên 100 MHz không đồng nghĩa tăng tốc xử lý ảnh so với bản CNN trước sửa. Với khoảng 768 nghìn chu kỳ trong bài SoC, thời gian tương ứng khoảng 7,68 ms ở 100 MHz.
- Tài nguyên, vị trí đặt logic và đường routing có thể thay đổi sau tổng hợp/implementation.

## 6. Script và testbench sửa hoặc thêm

| File | Thay đổi / tác dụng |
| --- | --- |
| `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr` | Lưu generic 100 MHz, constraint set và cặp run mới `synth_100MHz` / `impl_100MHz` làm current run; giữ top `soc_top`, part FPGA và các run cũ |
| `firmware/select_timing_constraints_100MHz.tcl` | Sửa để chọn constraint 100 MHz và đặt generic `CLK_FREQ=100000000`, `DDR_TX_PHASED_CLOCK=1` |
| `firmware/select_timing_constraints.tcl` | Sửa để đặt generic 50 MHz và tắt nhánh MMCM khi chọn profile 50 MHz |
| `firmware/run_timing_100MHz.ps1` và `.tcl` | Thêm quy trình chạy riêng: chụp đầu vào, lưu hash, synthesis/place/route và xuất báo cáo |
| `firmware/run_project_100MHz.tcl` | Thêm quy trình chạy trực tiếp project đang mở, sao lưu project, tạo run mới và giữ các run cũ |
| `firmware/vivado_run_threads.tcl` | Thêm hook đặt `general.maxThreads=4` cho các run mới |
| `firmware/show_project_100MHz_results.tcl` | Thêm script mở kết quả implementation đã hoàn tất và báo cáo timing, không launch/reset run |
| `firmware/sim/tb_bram_firmware.v` | Sửa để tham số hóa tần số clock và tùy chọn nhánh DDR dịch pha |
| `firmware/sim/run_bram.ps1` và `.tcl` | Sửa để hỗ trợ tần số/nhánh DDR mới và lấy đối tượng waveform đúng với top có parameter |
| `firmware/sim/tb_cnn_pipeline_equivalence.v` | Thêm testbench so sánh CNN trước/sau sửa |
| `firmware/sim/run_cnn_pipeline.ps1` và `.tcl` | Thêm runner cho bài đối chiếu CNN |
| `firmware/sim/tb_ddr_phased.v` và `run_ddr_phased.ps1` | Thêm kiểm tra serializer với primitive MMCM/ODDR thực của UNISIM |
| `firmware/PIPELINE_100MHZ_TRIAL.md` | Thêm ghi chú chi tiết các lượt thử, kiểm tra và cách chạy |
| `firmware/NOTE_CHINH_SUA_TIMING_100MHZ.md` | File tổng hợp thay đổi này |

Cấu hình run mới: `flatten_hierarchy=none`, tắt incremental checkpoint, `place=Explore`, bật `phys_opt=ExploreWithHoldFix`, `route=Explore`. Run dừng sau route; không tạo bitstream.

Các thư mục `firmware/build/` và `firmware/backups/` chứa báo cáo, mô phỏng, bản chụp và bản sao lưu; không phải logic phần cứng thêm vào FPGA.

Chọn lại profile 50 MHz không khôi phục CNN cũ. Selector 50 MHz hiện thao tác constraint của `synth_1`/`impl_1` và generic chung; không tự chuyển current run từ `synth_100MHz`/`impl_100MHz`. Muốn phục hồi cấu trúc trước sửa cần dùng đúng bản sao lưu và cấu hình lại run tương ứng.

## 7. Các kiểm tra đã hoàn tất

Các kết quả dưới đây được đọc từ log đã có; việc lập ghi chú ngày 19/10/2026 không chạy lại synthesis hoặc mô phỏng.

| Kiểm tra | Kết quả | Log |
| --- | --- | --- |
| CNN trước/sau sửa | PASS: 6 trường hợp, 32.400 activation, kết quả phân loại khớp; có 2 bài reset giữa chừng | `firmware/build/sim_cnn_pipeline/simulate.log` |
| Firmware BRAM CPU, bản 100 MHz bật MMCM | PASS: 1.792 kiểm tra, 0 lỗi, AXI fault=0 | `firmware/build/sim_bram_pipeline_100MHz_fine/simulate.log` |
| Firmware BRAM CPU ở 50 MHz và 100 MHz bỏ qua MMCM | Đã PASS ở các lượt mô phỏng trước | Các thư mục mô phỏng BRAM tương ứng trong `firmware/build/` |
| Firmware toàn SoC qua UART/CNN ở 50 MHz | PASS bài smoke: ảnh đen, chạy thường, DMA buffer 0 và 1 | `firmware/build/sim_firmware_pipeline_smoke/simulate.log` |
| Serializer DDR và MMCM | PASS: 4 burst, 16 word, kiểm tra cửa sổ setup/hold lý tưởng và reset/khóa lại | `firmware/build/sim_ddr_phased/simulate.log` |
| Parallel AXI–IDDR–ODDR ở 100 MHz | PASS: 24/24 đối chiếu | `firmware/build/sim_parallel_phased/simulate.log` |

Bài firmware BRAM không truy cập ngoại vi, nên không xác nhận SPI/I2C giữ tốc độ cũ. Bài UART/CNN nêu trên không phải bài tích hợp đầy đủ ở 100 MHz. Giá trị `phase=3.196429ns` trong log DDR là pha cấu hình; không phải phép đo chính xác fine phase trên board.

## 8. Kết quả timing được chọn

Nguồn báo cáo của project:

`SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.runs/impl_100MHz/soc_top_timing_summary_routed.rpt`.

| Chỉ số sau route | Giá trị |
| --- | ---: |
| WNS — khoảng dư setup nhỏ nhất | +0,038 ns |
| WHS — khoảng dư hold nhỏ nhất | +0,049 ns |
| TNS / THS | 0 / 0 ns |
| Endpoint vi phạm setup / hold | 0 / 0 |
| Endpoint được kiểm tra setup / hold | 19.666 |
| WPWS / TPWS | +3,000 / 0 ns |
| Endpoint được kiểm tra pulse width | 4.270 |
| Riêng nội bộ `sys_clk`: setup / hold | +0,218 / +0,060 ns |
| Riêng `sys_clk` → `ddr_clk_out`: setup / hold | +0,038 / +0,049 ns |

Đường DDR quyết định khoảng dư nhỏ nhất toàn thiết kế. Các giá trị này là kết quả Vivado tính, không phải các thông số tự nhập vào constraint. Biên nhỏ nhất còn 38 ps setup và 49 ps hold.

Lượt chạy riêng được chọn: `firmware/build/impl100_pipeline_trial4_fine_phase/`; project gốc `impl_100MHz` cho cùng kết quả. Các thư mục trial1/trial2/trial3 và `impl100_pipeline_final` là những thử nghiệm trước đó; không dùng tên thư mục để suy ra đâu là kết quả cuối.

Bộ constraint còn thiếu một số thông tin I/O, gán chân và I/O standard của board. Kết quả trên xác nhận đạt các ràng buộc đã khai báo; chưa xác nhận chạy thực tế trên board. Chưa tạo hoặc nạp bitstream trong đợt công việc này.

## 9. Dấu vân tay các file quan trọng khi lập ghi chú

| File | SHA-256 |
| --- | --- |
| `firmware/bram_test.hex` | `34E08BF88871F4E64EE95BE99B8220303410C495FA8A763D4EA8A9821D823569` |
| `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/firmware.hex` | `34E08BF88871F4E64EE95BE99B8220303410C495FA8A763D4EA8A9821D823569` |
| `firmware/firmware.hex` — ảnh ứng dụng toàn SoC khác với ảnh BRAM test đang chọn | `FCF77DBA90B0CE0A767720D61D90918286DA0A6B51692F0316B8BEC660807CAB` |
| `CNN.v` hiện tại và bản sao trước sửa | `4C981C6FE48208EE0C8AF369DE7E887EC0546C89819E6BC22EE869E498294877` |

Việc tạo ghi chú này chỉ thêm file tài liệu; không sửa RTL, firmware, constraint hoặc cấu hình project.
