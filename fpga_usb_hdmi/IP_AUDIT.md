# Kiểm tra usb_hdmi_system — 31/10/2026

**Báo cáo trước khi sửa.** Sau báo cáo này, người dùng đã cập nhật một phần BD,
và các kết nối còn thiếu đã được sửa. Trạng thái hiện tại xem [REPAIR_RESULT.md](REPAIR_RESULT.md).

Đối tượng: `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.srcs/sources_1/bd/usb_hdmi_system/usb_hdmi_system.bd`
và các file XCI trong thư mục `ip/` cùng cấp. Kết quả chỉ áp dụng cho bản đã lưu
trên đĩa; các chỉnh sửa chưa Save trong Vivado không có trong lần kiểm tra này.
Không sửa Block Design hoặc project gốc trong quá trình kiểm tra.

## Kết luận từ file đã lưu

Chưa đủ điều kiện build/chạy USB camera–HDMI. BD mới có các component;
không có mục `nets`, `interface_nets`, `ports`, `interface_ports` hoặc `addressing`.
Chưa lưu các đường nối scalar, AXI, cổng DDR/FIXED_IO/HDMI và vùng địa chỉ.

| Mức | Khối | Hiện tại | Cần sửa cho cấu hình 640×480 đã thống nhất |
| --- | --- | --- | --- |
| Chặn | control_bus, memory_bus | `xilinx.com:ip:axis_interconnect:2.1` | Dùng AXI Interconnect cho memory-mapped AXI; control 1 SI/3 MI, memory 1 SI/1 MI |
| Chặn | Toàn BD | Chưa có nets/interface nets/cổng ngoài | Nối AXI, clock, reset, video; xuất DDR, FIXED_IO và HDMI; Assign Address |
| Chặn | clk_wiz_0 | Một đầu ra 100 MHz; clk_out2 tắt; input single-ended pin; reset active-high | Input FCLK0 100 MHz/No buffer; output 25,2 và 126 MHz; reset active-low; locked bật |
| Chặn | invert_hsync, invert_vsync | AND, 8 bit | NOT, 1 bit |
| Chặn | reset_axi, reset_pixel | External reset active-high (`C_EXT_RESET_HIGH=1`) | Active-low khi nhận FCLK_RESET0_N; aux active-high và nối 0; debug reset nối 0 |
| Sai cấu hình | rgb2dvi_0 | Tự tạo serial clock; reset active-high | Nếu cấp hai clock từ Wizard: tắt tự tạo serial clock, chọn reset active-low/aRst_n |
| Sai cấu hình | display_vdma | Read+write bật, stream 32 bit, memory 64 bit | Chỉ MM2S cho display; stream 24 bit khớp Video Out; memory 64 bit; free-run đã đúng |
| Sai cấu hình | video_out | Independent clock tắt (`C_HAS_ASYNC_CLK=0`) | Bật nếu AXIS dùng 100 MHz và video output dùng 25,2 MHz |
| Sai cấu hình | video_timing1 | 720p; detector và generator đều bật | Progressive 640×480; generator bật, detector tắt; timing nội bộ theo yêu cầu Video Out |
| Sai cấu hình | hdmi_hpd | GPIO 32 bit, không cấu hình all-inputs | GPIO 1 bit input |
| Sai cấu hình | xlconstant_0, xlconstant_1 | Cả hai đều có giá trị 1 | Cần một constant width=1/value=0 cho các reset phụ và fid; constant 1 dùng cho enable |
| Cần kiểm tra board | Zynq PS | Reference clock 33,333333 MHz; DDR mặc định MT41J128M8 JP-125; SD0/UART0/UART1 đều tắt | Áp dụng đầy đủ preset PYNQ-Z2 và cấu hình boot Linux/console phù hợp; USB-only không thay thế board preset |
| Tích hợp | Project top | `soc_top`; chưa dùng shell USB/HDMI | Sau khi BD hoàn chỉnh, đăng ký top USB/HDMI và dùng constraint set phù hợp các cổng mới |

## Các giá trị đã đúng trong PS/XCI

- M_AXI_GP0 bật.
- S_AXI_HP0 bật, 64 bit.
- FCLK_CLK0 100 MHz và cổng FCLK_RESET0_N bật.
- USB0 bật, ULPI MIO 28–39, PHY reset MIO 46 active-low.
- Bank MIO 1 cấu hình 1,8 V.

Các giá trị này chưa chứng minh camera hoạt động: còn cần export FIXED_IO,
đúng cấu hình PS/DDR/boot và Linux nhận được khung hình webcam.

## Validate Design

Chạy trên bản sao BD trong `build_check/usb_hdmi_audit/`, không trên project gốc.
Script: `build_check/audit_usb_hdmi.tcl`; log: `build_check/audit_usb_hdmi.log`.
Kết quả cuối cùng xem các dòng `AUDIT_*` và lỗi của `validate_bd_design` trong log.

Kết quả thực tế: **FAIL**, Vivado 2025.2.

- `AUDIT_CELLS=15`
- `AUDIT_NETS=0`, `AUDIT_INTERFACE_NETS=0`
- `AUDIT_PORTS=0`, `AUDIT_INTERFACE_PORTS=0`
- `[BD 41-758]`: 23 chân clock chưa nối nguồn clock hợp lệ.
- `[BD 41-2670]`: đường địa chỉ GP0 và VDMA MM2S/S2MM chưa hoàn chỉnh.
- `AUDIT_VALIDATION_FAILED=1`.
- SHA-256 BD gốc lúc kiểm tra:
  `71d5b26bb62b4a4cd1c4990425fe52faf820802e624d6e6caaa97adb6c613191`.

Nếu GUI đã được chỉnh khác: Ctrl+S trong Diagram, sau đó Validate Design.
