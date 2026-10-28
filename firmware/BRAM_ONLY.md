# Firmware chỉ kiểm tra BRAM

Đường CPU–BRAM hiện đi qua AXI4: xem [AXI4_BRAM.md](AXI4_BRAM.md) để đối chiếu
từng nhóm tín hiệu, giới hạn hỗ trợ và cách kiểm tra burst. Code C vẫn thực hiện
các phép đọc/ghi bộ nhớ; giao thức AXI4 do RTL xử lý.

`bram_test.c` là chương trình tối giản cho CPU PicoRV32: CPU lấy lệnh từ BRAM,
ghi/đọc vùng dữ liệu BRAM và lưu PASS/FAIL ngay trong BRAM. Chương trình không truy
cập UART, CNN, DMA hoặc các ngoại vi khác. `soc_top` chuyển các yêu cầu bộ nhớ
qua bridge AXI4 và controller BRAM, giữ nguyên địa chỉ chương trình và dữ liệu.

## Chạy thử nhanh

Từ thư mục gốc repository:

```powershell
py firmware/build.py --app bram --no-deploy
powershell -NoProfile -ExecutionPolicy Bypass -File firmware/sim/run_bram.ps1
```

Kết quả cần có `BRAM FIRMWARE PASS`. Log và waveform nằm trong
`firmware/build/sim_bram/`. Đây là testbench riêng `tb_bram_firmware`, dùng CPU và
bộ điều khiển BRAM thực tế của `soc_top`.

`--no-deploy` tạo `firmware/bram_test.hex` mà không đổi ảnh firmware đang chọn
trong project. ELF/map/disassembly được tạo thành `firmware/build/bram_test.*`.
Nếu muốn cập nhật ảnh firmware chính cho SoC, chạy `py firmware/build.py --app bram`
hoặc dùng script chọn chế độ Vivado bên dưới. Cả hai đều chép bản BRAM-only vào
`SOC_HUFLIT_2026.srcs/sources_1/new/firmware.hex`, đúng tên `$readmemh` đang sử dụng.

## Mở waveform bằng Vivado

Đóng simulation cũ, mở project rồi chạy trong Tcl Console:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/select_bram_test.tcl}
```

Script chọn ảnh firmware BRAM-only, thêm testbench với loại SystemVerilog, chọn
top `tb_bram_firmware` và bỏ tùy chọn FULL_IMAGES của bài CNN. Sau đó chọn
**Run Simulation > Run Behavioral Simulation > Run All**.

Trong scope `tb_bram_firmware.dut`, xem các tín hiệu:

- `u_cpu.reg_pc`: CPU bắt đầu lấy lệnh ở địa chỉ 0 rồi thực thi vòng kiểm tra.
- `mem_addr`, `mem_wdata`, `mem_wstrb`, `mem_rdata`, `mem_valid`, `mem_ready`:
  các giao dịch bộ nhớ của CPU.
- `cpu_trap`: phải bằng 0.
- `bram[256]..bram[511]`: vùng dữ liệu được kiểm tra, cuối bài đều `ABCD1234`.
- `bram[512]..bram[520]`: kết quả, trình bày bên dưới.

Ở scope `tb_bram_firmware` đã có sẵn các tín hiệu dễ xem: `report_status`,
`report_errors`, `report_phase`, `report_checks`, `report_heartbeat` và
`cpu_mem_*`. Bản đi kèm đã mô phỏng PASS: **1792 lần so sánh, 0 lỗi**, CPU không
trap và không truy cập ngoại vi. Với đường AXI4, thời gian mô phỏng khoảng **8,64 ms**,
thời gian thực chạy XSim khoảng **37 giây** trên máy hiện tại. Chương trình chiếm
**592 byte**; chưa kiểm tra trên board vật lý.

## Bản đồ bộ nhớ

| Vùng | Mục đích |
|---|---|
| `0x000..0x3ff` | Mã chương trình và dữ liệu tĩnh; linker chặn tràn vùng |
| `0x400..0x7ff` | Vùng test 256 word, tổng 1024 byte |
| `0x800..0x823` | Kết quả kiểm tra |
| `0xdf0..0xfef` | 512 byte dành cho stack, SP ban đầu `0xff0` |

Test không ghi đè mã đang thực thi hoặc stack. Đây là kiểm tra một vùng dữ liệu
1024 byte trong BRAM 4 KiB; không phải phép thử toàn bộ ô nhớ BRAM của FPGA.

| Word waveform | Địa chỉ byte | Nội dung |
|---|---|---|
| `bram[512]` | `0x800` | Magic `4252414D` (`BRAM`) |
| `bram[513]` | `0x804` | Status: `0` đang chạy, `1` PASS, `2` FAIL |
| `bram[514]` | `0x808` | Số lỗi, kỳ vọng `0` |
| `bram[515]` | `0x80c` | Địa chỉ lỗi đầu tiên |
| `bram[516]` | `0x810` | Giá trị mong đợi tại lỗi đầu tiên |
| `bram[517]` | `0x814` | Giá trị đọc được tại lỗi đầu tiên |
| `bram[518]` | `0x818` | Giai đoạn kiểm tra, kết thúc ở `7` |
| `bram[519]` | `0x81c` | Số word đã so sánh, kỳ vọng `1792` = `0x700` |
| `bram[520]` | `0x820` | Heartbeat tăng sau khi kiểm tra xong |

Bảy lượt kiểm tra gồm `00000000`, `FFFFFFFF`, `AAAAAAAA`, `55555555`, mẫu phụ
thuộc địa chỉ, ghi bốn byte và ghi hai halfword. Mỗi lượt ghi toàn bộ vùng trước
khi đọc lại, để kiểm tra cả giải mã địa chỉ. Byte/halfword kiểm tra các write strobe.

Để quay về chương trình UART/CNN, chạy `py firmware/build.py --app cnn`, chọn lại
top `tb_firmware` và cấu hình FULL_IMAGES nếu cần. File nguồn chương trình CNN và
`firmware/firmware.hex` được giữ riêng với bản `bram_test.hex`.
