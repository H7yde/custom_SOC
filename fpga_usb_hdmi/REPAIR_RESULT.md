# Kết quả sửa usb_hdmi_system — 31/10/2026

Đã sửa trực tiếp BD trong project `SOC_HUFLIT_2026_parallel_125MHz`.
Đã giữ các kết nối đúng của người dùng và bổ sung phần còn thiếu.

## Đã hoàn thành

- PS GP0 → control_bus → VDMA/VTC/GPIO; VDMA → memory_bus → PS HP0.
- VDMA stream RGB24 → Video Out; VTC timing và gen_clken nối đúng.
- Clock AXI 100 MHz; pixel 25,2 MHz; serial 126 MHz; metadata HDMI clock 25,2 MHz.
- Reset AXI/pixel đúng miền clock; cực tính external reset suy ra từ FCLK_RESET0_N.
- Đầu ra NOT 1 bit HSYNC/VSYNC nối RGB2DVI; DE và data đã nối.
- Xuất DDR, FIXED_IO, 4 cổng TMDS (9 chân tính cả HPDN) và HPDN vào GPIO input 1 bit.
- Cấp đủ các tín hiệu enable, fid, reset phụ.
- Bổ sung cấu hình board PS theo dữ liệu tham khảo chính thức PYNQ v2.7.0:
  PS crystal 50 MHz, DDR controller x16/512 MiB, SD0/UART0, USB0 MIO 28–39/reset 46.
- Chuẩn hóa các skew của byte lane DDR 2/3 không dùng về 0.
- Script tích hợp tự tìm thư mục SoC hiện tại thay vì cố định tên cũ 50MHz.

Lưu ý DDR: `PCW_UIPARAM_DDR_BUS_WIDTH=16 Bit` là cấu hình controller.
Giao diện hard PS7 mà Vivado sinh vẫn có `DDR_dq[31:0]`, `DDR_dm[3:0]`,
`DDR_dqs_[pn][3:0]`. Top được giữ đúng độ rộng giao diện HDL này; không cắt
độ rộng cổng chỉ dựa vào mode x16 của controller.

## Kiểm tra

- `USB_HDMI_REPAIR_VALIDATE_PASS`: Validate Design đạt.
- Mở lại BD đã lưu, kiểm tra các giá trị PS/reset và Validate Design đạt.
- `USB_HDMI_REOPEN_VALIDATE_PASS`: đạt.
- 23 scalar nets, 10 interface nets; đã có cổng ngoài và address segments.
- Sinh wrapper thật và đối chiếu tên, chiều, độ rộng: **26 cổng khớp** với soc_usb_hdmi_top.v.

Log: `build_check/repair_usb_hdmi_retry.log` và
`build_check/verify_repaired_usb_hdmi_final.log`.
Tcl xuất đầy đủ BD: `build_check/usb_hdmi_system_repaired_export.tcl`.

| IP | Địa chỉ ARM | Kích thước |
| --- | --- | --- |
| display_vdma | 0x43000000 | 64 KiB |
| video_timing1 | 0x43C00000 | 64 KiB |
| hdmi_hpd | 0x41200000 | 64 KiB |
| VDMA MM2S → PS DDR | 0x00000000 | 512 MiB |

## Phạm vi và bước chạy

Chưa synthesis/implementation hoặc tạo bitstream mới; chưa đo trên board.
Top synthesis của project vẫn là `soc_top` để giữ SoC PicoRV32 hiện tại.
BD USB/HDMI này chưa chứa cầu nối ARM–PicoRV32/CNN. Muốn build riêng top
USB/HDMI phải đăng ký shell, chọn top và constraint set tương ứng; không dùng
nguyên các ràng buộc chân của soc_top cho shell khác cổng.

Phần mềm ARM/Linux còn phải nhận webcam, quản lý framebuffer và khởi động VDMA/VTC.
Validate Design đạt không thay thế thử camera/màn hình hoặc kiểm tra timing sau route.

Trong Vivado GUI đang mở bản cũ, đóng rồi mở lại project để đọc bản đã sửa;
tránh lưu bản cũ đang nằm trong bộ nhớ đè lên BD trên đĩa.

Backup đầy đủ trước khi sửa:
`backups/before_wiring_20261031_143609/`.

Nguồn tham số board:
https://raw.githubusercontent.com/Xilinx/PYNQ/v2.7.0/boards/Pynq-Z2/petalinux_bsp/hardware_project/pynqz2.tcl
File tham khảo chỉ được đọc các giá trị CONFIG, không thực thi toàn bộ script cũ.
