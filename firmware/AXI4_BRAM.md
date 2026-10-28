# BRAM qua AXI4 Full

Đường bộ nhớ chương trình/dữ liệu trong `soc_top` được nối như sau:

```text
PicoRV32 native memory
        -> picorv32_axi4_bram_adapter
        -> AXI4 AW / W / B / AR / R
        -> axi4_bram_slave
        -> bram[0:1023], 4 KiB
```

Mảng `dut.bram`, file khởi tạo `firmware.hex`, reset PC = 0, SP = `0xff0`, vùng
test `0x400..0x7ff` và vùng kết quả `0x800..0x823` được giữ nguyên. Mỗi lần CPU
lấy lệnh hoặc đọc/ghi dữ liệu BRAM đều đi qua giao tiếp AXI4 mới. Ngoại vi UART,
SPI, I2C, CNN và vùng DMA tiếp tục dùng đường MMIO riêng đang có.

## Đối chiếu tài liệu AXI4_Full_Signals.docx

| Nhóm | Tín hiệu và độ rộng áp dụng |
|---|---|
| Clock/reset | `ACLK`, `ARESETn`, 1 bit |
| AW/AR | `ID[3:0]`, `ADDR[31:0]`, `LEN[7:0]`, `SIZE[2:0]`, `BURST[1:0]`, `LOCK`, `CACHE[3:0]`, `PROT[2:0]`, `QOS[3:0]`, `REGION[3:0]`, `USER`, `VALID`, `READY` |
| W | `DATA[31:0]`, `STRB[3:0]`, `LAST`, `USER`, `VALID`, `READY` |
| B | `ID[3:0]`, `RESP[1:0]`, `USER`, `VALID`, `READY` |
| R | `ID[3:0]`, `DATA[31:0]`, `RESP[1:0]`, `LAST`, `USER`, `VALID`, `READY` |

Độ rộng 32 bit dữ liệu/địa chỉ, 4 bit ID và 1 bit USER là cấu hình của bản triển
khai này; tài liệu người dùng cung cấp chỉ liệt kê các tín hiệu.

## Giao dịch do CPU phát

PicoRV32 phát yêu cầu native từng word; bridge chuyển mỗi yêu cầu thành một giao
dịch AXI4 một beat:

- `AWLEN = ARLEN = 0`: một beat.
- `AWSIZE = ARSIZE = 2`: 4 byte trên bus 32 bit.
- `AWBURST = ARBURST = 01`: INCR.
- `AWID = ARID = 0`; `WLAST = 1`; slave trả ID tương ứng và `RLAST = 1`.
- Ghi byte/halfword vẫn là một beat 32 bit, với `WSTRB` chọn các byte hợp lệ.
- `PROT[2]` phản ánh đọc lệnh hay dữ liệu; `PROT[1:0] = 00`.
- `LOCK`, `CACHE`, `QOS`, `REGION`, `USER` của master bằng 0.

Bridge giữ từng `VALID` và payload cho tới khi có handshake; AW và W hoàn thành
độc lập. CPU chỉ nhận `mem_ready` sau phản hồi B/R. `bram_axi_fault` được giữ ở 1
nếu gặp phản hồi lỗi, ID sai hoặc thiếu RLAST; reset xóa cờ này. Lỗi đọc trả về 0
cho CPU. Đây là cờ chẩn đoán RTL, chưa ánh xạ thành thanh ghi firmware hoặc ngắt.

Một chuỗi lệnh store trong C vẫn tạo nhiều giao dịch một beat. Burst nhiều beat
được kiểm tra bằng master trong `tb_axi4_bram`, không được tự gom từ các lệnh CPU.

## Khả năng và giới hạn của slave BRAM

- Một giao dịch đọc và một giao dịch ghi có thể hoạt động đồng thời; mỗi kênh
  chỉ có một giao dịch outstanding, ID phản hồi giữ nguyên ID yêu cầu.
- Hỗ trợ truy cập **đúng alignment** 1, 2 hoặc 4 byte.
- FIXED: 1–16 beat; INCR: 1–256 beat; WRAP: 2, 4, 8 hoặc 16 beat.
- `LEN = số beat - 1`, `SIZE = log2(số byte/beat)`; burst không vượt biên 4 KiB.
- Địa chỉ hợp lệ nằm trong `0x00000000..0x00000fff`. Yêu cầu ngoài vùng trả DECERR.
- Burst/size/alignment không hỗ trợ, AxLOCK=1, WLAST/WSTRB sai trả SLVERR. Không
  triển khai bộ theo dõi exclusive; không phát EXOKAY.
- Thuộc tính CACHE/PROT/QOS/REGION/USER được nhận nhưng không thay đổi hành vi
  bộ nhớ; BUSER/RUSER bằng 0.
- Yêu cầu lỗi vẫn được nhận đủ số beat theo LEN. Ghi lỗi không được rollback các
  beat đã ghi hợp lệ trước lỗi; không ghi các beat lỗi hoặc các beat sau đó.
- BRAM đọc đồng bộ, read-first nếu một địa chỉ được đọc và ghi cùng cạnh clock.
- Reset xóa trạng thái giao dịch và VALID, giữ nội dung BRAM.

Đây là implementation có phạm vi hỗ trợ nêu trên, chưa có chứng nhận/formal proof
cho toàn bộ các tùy chọn AXI4. Các quy tắc encoding/handshake được đối chiếu với
[Arm AXI4 introduction](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf?revision=369ad681-f926-47b0-81be-42813d39e132)
và [AMD AXI Protocol Checker](https://docs.amd.com/r/en-US/pg101-axi-protocol-checker/AXI-Protocol-Checks-and-Descriptions).

## Build và chạy

```powershell
py firmware/build.py --app bram --no-deploy
powershell -NoProfile -ExecutionPolicy Bypass -File firmware/sim/run_bram.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File firmware/sim/run_axi4_bram.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File firmware/sim/run_axi4_adapter.ps1
```

- Bài firmware chạy CPU thật, kiểm tra 7 pha/1792 phép so sánh và các handshake
  AXI4, đồng thời xác nhận CPU không truy cập ngoại vi hoặc trap.
- Bài slave phát burst thật, đổi ID, tạo backpressure, đọc/ghi đồng thời và thử
  các yêu cầu lỗi/reset. Đây là bài có `AWLEN/ARLEN = 255` cho burst 256 beat.
- Bài adapter điều khiển phản hồi AXI riêng để kiểm tra AW/W đến độc lập,
  backpressure, báo lỗi và reset.

## Xem trong Vivado

Đóng simulation cũ và chạy trong Tcl Console:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/select_bram_test.tcl}
```

Script đăng ký hai module RTL mới, chọn ảnh firmware BRAM-only, chọn top
`tb_bram_firmware`, đặt testbench là SystemVerilog và runtime là all. Sau đó chạy
**Run Behavioral Simulation > Run All**.

Trong waveform của `tb_bram_firmware`, thêm:

- `report_status`, `report_errors`, `report_checks`, `report_phase`.
- `bram_axi_aw*`, `bram_axi_w*`, `bram_axi_b*`, `bram_axi_ar*`, `bram_axi_r*`.
- `bram_axi_fault`, `cpu_mem_*`, `cpu_trap`.

Kỳ vọng cuối bài firmware: `report_status=1`, `report_errors=0`,
`report_checks=1792`, `bram_axi_fault=0`, `cpu_trap=0`. File WDB nằm tại
`firmware/build/sim_bram/bram_firmware.wdb`.

## Kết quả kiểm tra bản đi kèm

- CPU/firmware BRAM: 1792 phép so sánh, 0 lỗi; AW=W=B=4637,
  AR=R=50554; fault=0; không trap. Khoảng 8,64 ms thời gian mô phỏng.
- Controller AXI4 BRAM: 2969 checks PASS, gồm burst INCR 256 beat và reset
  bất đồng bộ giữa giao dịch.
- Bridge native–AXI4: 12 tình huống, 482 checks PASS, gồm thứ tự AW/W,
  backpressure, phản hồi lỗi và reset.
- Bài UART/CNN smoke ở 115200 baud cũng PASS với đường CPU–BRAM mới.
- Script `select_bram_test.tcl` đã được kiểm tra trong project Vivado 2025.2
  tạo trong bộ nhớ: đúng top, loại SystemVerilog, file khởi tạo và hai module RTL.

Chưa chạy synthesis/implementation hoặc kiểm tra trên board vật lý cho bản AXI4 này.

## Khi Vivado báo Common 17-180 tại update_compile_order

Đây là lỗi khởi chạy tiến trình trong bước quản lý nguồn/hierarchy. Thông báo
`The operation completed successfully` đi kèm không có nghĩa là bước đó thành công,
và chưa đủ để xác định nguyên nhân hệ điều hành. Script chọn firmware hiện không
gọi `update_compile_order`, vì các module đã được thêm tường minh và không có
dependency package cần tự sắp thứ tự.

Giữ chế độ `DisplayOnly` như project gốc để Sources tự cập nhật cây module. Chế độ
`None` tắt tự cập nhật hierarchy nên cây có thể không phản ánh các thay đổi nguồn.
Để khôi phục cây trong phiên Vivado đang mở:

```tcl
source {D:/SoC/custom_SOC-main/custom_SOC-main/firmware/restore_source_tree.tcl}
```

Trong khung Sources chọn tab **Hierarchy**. Tab **Libraries** nhóm file theo
`Verilog/SystemVerilog -> xil_defaultlib`, không hiển thị các instance `dut`.
Mở rộng `Simulation Sources -> tb_bram_firmware -> dut : soc_top` để xem các khối.

Nếu phiên GUI vẫn lỗi spawn, lưu project rồi đóng và mở lại Vivado. Để chạy trực
tiếp mà không thay đổi cách hiển thị Sources, mở PowerShell ở thư mục gốc và dùng
`powershell -NoProfile -ExecutionPolicy Bypass -File firmware/sim/run_bram.ps1`.
Đường này gọi xvlog/xelab/xsim trực tiếp, không dùng helper quét hierarchy của GUI.
