# Bản thử nghiệm pipeline CNN ở 100 MHz

Các đường dẫn dưới đây tính từ thư mục gốc repository. Đây là bản sửa RTL để kiểm tra timing; firmware BRAM của CPU và vùng nhớ riêng của CNN vẫn độc lập.

## Thay đổi

- `cnn_docx_reference.v`: tách các bước tính địa chỉ, đọc bộ nhớ, chuẩn hóa pixel, nhân, cộng và ghi kết quả thành nhiều chu kỳ. Dùng bộ đếm theo hàng/kênh để giảm logic trên đường địa chỉ. Giữ nguyên định dạng dữ liệu, trọng số và kết quả tính toán.
- `parallel.v`: thêm tùy chọn `DDR_TX_PHASED_CLOCK=1`. Serializer và ODDR dữ liệu dùng `sys_clk`; `MMCME2_ADV` tạo clock DDR chuyển tiếp với pha cố định 115,071429°, tương đương 3,196429 ns ở 100 MHz. Bật `CLKOUT0_USE_FINE_PS`, nối `PSCLK=clk`, giữ `PSEN=0` và `PSINCDEC=0`. Fine phase có bước 1/56 chu kỳ VCO; VCO ở đây là 1 GHz. Cấu hình này dùng khả năng fixed fine phase của [MMCM 7 Series, UG472](https://docs.amd.com/api/khub/documents/1kFbRqzm2fhwGy~cLQG2yA/content). Giá trị mặc định `0` giữ cách phát clock cũ.
- `soc_top.v`: truyền tham số clock tới khối parallel; đọc ảnh firmware bằng tên `firmware.hex` để từng thư mục mô phỏng nạp đúng chương trình.
- Giá trị mặc định trong RTL là `CLK_FREQ=100000000`, `DDR_TX_PHASED_CLOCK=1`. Profile 100 MHz đặt các giá trị tương ứng, chu kỳ clock 10 ns và `SLEW FAST` cho các ngõ ra DDR. Các giả thiết I/O giữ từ constraint cũ: setup 2 ns, hold 1 ns, lệch dây −0,1 đến +0,5 ns; tương ứng output delay max 2,5 ns và min −1,1 ns.

**Đổi lại, CNN cần nhiều chu kỳ hơn:** bài đối chiếu tăng từ 129.121 lên 765.461 chu kỳ, khoảng 5,9 lần. Trong mô phỏng SoC, một lần tính khoảng 768.278 chu kỳ, tương đương 7,68 ms ở 100 MHz. Tăng tần số clock không đồng nghĩa tăng tốc xử lý ảnh sau thay đổi này.

## Kết quả kiểm tra chức năng

| Kiểm tra | Kết quả |
| --- | --- |
| CNN mới so với RTL trước sửa | PASS: 6 trường hợp, đối chiếu chính xác 32.400 giá trị activation và kết quả phân loại; có human, non-human, pixel biên, dữ liệu ngẫu nhiên và reset |
| Firmware BRAM CPU ở 50/100 MHz | PASS: 1.792 phép kiểm tra, 0 lỗi; bao gồm bản 100 MHz bật tùy chọn clock DDR |
| Firmware SoC qua UART/CNN ở 50 MHz | PASS: ảnh đen, chạy thường, DMA buffer 0 và DMA buffer 1; ảnh human/non-human được đối chiếu riêng ở bài CNN |
| Serializer DDR với MMCM | PASS: 16 từ dữ liệu, kiểm tra ổn định dữ liệu trước/sau cạnh clock, reset và khóa lại MMCM |
| Tích hợp parallel AXI–IDDR–ODDR với clock mới | PASS: 24/24 phép đối chiếu |

## Timing sau route

**Project gốc đã hoàn tất `synth_100MHz` / `impl_100MHz` lúc 19:59:31 ngày 18/10/2026: WNS +0,038 ns, WHS +0,049 ns, TNS = THS = 0; không có endpoint vi phạm setup/hold. Tất cả đường được constraint hiện tại đều đạt; biên timing DDR còn nhỏ.** Kết quả đọc trực tiếp từ `firmware/build/project_100MHz/impl_100MHz/timing_routed.rpt`, khớp lượt độc lập `trial4`. Có 6.250/6.250 net cần route đã nối hoàn chỉnh, không có lỗi routing.

Ở lượt độc lập `trial4`, nội bộ `sys_clk` có WNS +0,218 ns và WHS +0,060 ns; RTL, XDC và firmware đã được đối chiếu SHA-256 với bản chụp đầu vào của lượt chạy đó.

| Lượt thử | WNS setup | WHS hold | Trạng thái |
| --- | ---: | ---: | --- |
| `impl100_pipeline_trial1` — pipeline CNN, clock DDR cũ | +0,617 ns | −1,384 ns | Còn lỗi hold DDR |
| `impl100_pipeline_trial2_phased` — chỉ clock DDR qua MMCM | −0,195 ns | +0,058 ns | Còn lỗi setup DDR |
| `impl100_pipeline_trial3_shared_clock` — dữ liệu và clock DDR cùng MMCM | −0,301 ns | +0,064 ns | Không chọn; còn lỗi setup DDR, timing nội bộ `sys_clk` đạt +0,872 ns |
| `impl100_pipeline_trial4_fine_phase` — fine phase, dữ liệu dùng `sys_clk`, `SLEW FAST` | +0,038 ns | +0,049 ns | Đạt các constraint hiện tại sau route; bản được chọn |
| Project gốc: `impl_100MHz` | +0,038 ns | +0,049 ns | Đã hoàn tất; TNS = THS = 0, không lỗi routing |

Thử cấu hình trên DCP cũ dùng để chọn pha; kết luận đạt ở trên dựa trên lượt synthesis/place/route mới `trial4`. Mô phỏng UNISIM kiểm tra chức năng và cửa sổ dữ liệu lý tưởng; phép kiểm cạnh clock chấp nhận khoảng 3,18–3,40 ns sau cạnh lên `sys_clk`, có tính đến trễ ODDR của mô hình. Giá trị `phase=3.196429ns` trong log là pha được cấu hình, không phải kết quả đo chính xác fine phase. STA sau route nhận đúng pha MMCM; DRC không báo lỗi cấu hình MMCM. DRC vẫn còn cảnh báo thiếu constraint board và điều khiển bất đồng bộ BRAM, nên chưa tạo bitstream hoặc xác nhận chạy trên board.

Các báo cáo nằm trong `firmware/build/<tên_lượt_thử>/`. Kết quả cần đọc là `timing_routed.rpt` và dòng `FULL_IMPLEMENTATION_RESULT` trong `timing100.log`.

## Chạy lại

Mở PowerShell tại thư mục gốc repository:

```powershell
powershell -ExecutionPolicy Bypass -File firmware/run_timing_100MHz.ps1
powershell -ExecutionPolicy Bypass -File firmware/sim/run_cnn_pipeline.ps1
powershell -ExecutionPolicy Bypass -File firmware/sim/run_bram.ps1 -ClockFrequency 100000000 -PhasedDdrClock
powershell -ExecutionPolicy Bypass -File firmware/sim/run_ddr_phased.ps1
```

Lệnh `run_timing_100MHz.ps1` tạo thư mục kết quả mới, lưu bản chụp đầu vào và mã SHA-256, rồi chạy synthesis/place/route độc lập với các chỉ thị `Explore` và `ExploreWithHoldFix` trong script. Đây là cách chạy lại đúng quy trình của `trial4`. Riêng script độc lập này không sửa project `.xpr` gốc và không tạo bitstream.

## Chạy trực tiếp project gốc trong Vivado GUI

Project gốc đã được lưu với generic và constraint 100 MHz, đồng thời tạo cặp run mới `synth_100MHz` / `impl_100MHz` làm current run. Synthesis bắt đầu lúc 19:51:04 ngày 18/10/2026; route hoàn tất và báo cáo được ghi xong lúc 19:59:31 cùng ngày. **Kết quả project: WNS +0,038 ns, WHS +0,049 ns, TNS = THS = 0.**

Lượt chạy lại trong GUI hoàn tất lúc 20:04:56 cùng ngày cho cùng kết quả; Timing Summary của `impl_100MHz` đã được mở và kiểm tra trong GUI, không còn thông báo kết quả cũ.

Để **mở kết quả `impl_100MHz` đã có**, chạy trong Tcl Console:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/show_project_100MHz_results.tcl}
```

Lệnh này chỉ mở routed design và tạo/hiển thị báo cáo timing từ kết quả hiện có; không launch hoặc reset run. Nếu implementation đang chạy lại, chờ route hoàn tất rồi mới dùng lệnh. Báo cáo được cập nhật trong `firmware/build/project_100MHz/impl_100MHz/`; `show_results.log` ghi thời điểm mở và WNS/WHS của kết quả vừa đọc.

Để chạy toàn bộ quy trình trong project gốc đang mở, dùng Tcl Console:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/run_project_100MHz.tcl}
```

Script sao lưu `.xpr`, chọn profile/generic 100 MHz, tạo run mới với `flatten_hierarchy none`, tắt incremental, dùng 4 thread và các chỉ thị `Explore` / `ExploreWithHoldFix`. Sau đó chạy synthesis và implementation đến route, mở routed design và báo cáo timing trong GUI. Các run cũ được giữ lại; nếu chạy lại khi tên run đã có kết quả, script thêm hậu tố như `_2`.

Theo dõi tiến độ tại `firmware/build/project_100MHz/impl_100MHz/status.log`. Báo cáo sau khi hoàn tất nằm cùng thư mục, gồm `timing_routed.rpt`, `route_status.rpt`, `clocks.rpt`, `check_timing.rpt` và `drc.rpt`. Log chi tiết của Vivado nằm tại `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.runs/synth_100MHz/runme.log` và `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.runs/impl_100MHz/runme.log`. Với lượt chạy có hậu tố, thay tên run tương ứng trong các đường dẫn.

Nếu chỉ muốn chọn profile/generic để tự chạy các bước trong GUI, dùng lệnh sau **trước khi synthesis**:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/select_timing_constraints_100MHz.tcl}
```

Script chọn constraint 100 MHz và đặt cả hai generic tương ứng trong project đang mở; chỉ thêm file XDC là chưa đủ để bật clock DDR mới. Sau đó chạy lại synthesis và implementation. Project GUI có thể dùng strategy khác script độc lập, nên WNS/WHS có thể khác; cần đọc báo cáo của chính lượt chạy GUI. Clock thực cấp vào SoC phải là **100 MHz**; file XDC chỉ mô tả clock, không tự đổi tần số clock của board.

Bản sao trước khi sửa nằm tại `firmware/backups/before_pipeline_20261018_102557/`. Bộ constraint hiện thiếu gán chân và I/O standard của board; kiểm tra cũng còn 37 input và 8 output chưa có delay. Vì vậy, kể cả khi WNS/WHS không âm, kết quả này chưa xác nhận đầy đủ timing của thiết bị ngoài hoặc khả năng nạp bitstream lên board.
