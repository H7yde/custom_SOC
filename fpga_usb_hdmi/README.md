# USB webcam + HDMI cho PYNQ-Z2

Cầu nối ARM–CNN đã được thêm vào `soc_top`: AXI4-Lite tại `0x40004000`,
chuyển clock 100/125 MHz, phân xử và khóa quyền sử dụng giữa ARM/PicoRV32.
Xem [ARM_CNN_BRIDGE.md](ARM_CNN_BRIDGE.md) để build và dùng driver ARM.
Các phần mô tả “chưa có cầu nối” bên dưới là ghi chú từ giai đoạn trước.

`usb_hdmi_system` hiện được ghép trực tiếp vào `soc_top` cùng PicoRV32/CNN.
Xem [SOC_TOP_INTEGRATION.md](SOC_TOP_INTEGRATION.md) và dùng
`integrate_soc_top.tcl` cho thiết kế ghép. Hướng dẫn `soc_usb_hdmi_top` bên dưới
là lựa chọn top chỉ chứa PS/video.

Block Design `usb_hdmi_system` trong project `SOC_HUFLIT_2026_parallel_125MHz`
đã được sửa các kết nối và đạt Validate Design. Xem [REPAIR_RESULT.md](REPAIR_RESULT.md)
để biết kiểm tra, địa chỉ IP và backup. Chưa có bitstream mới hoặc thử trên board;
cầu nối ARM–PicoRV32/CNN và ứng dụng camera Linux vẫn chưa tích hợp.

## Các file

- ../SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.srcs/sources_1/new/soc_usb_hdmi_top.v:
  top-level nối DDR, FIXED_IO của PS và HDMI OUT vào Block Design.
- Cùng thư mục nguồn: pynq_z2_usb_ps.tcl bật USB0 ULPI MIO 28–39,
  reset PHY MIO 46. Script add_integration_sources.tcl tự gọi cấu hình này.
- pynq_z2_hdmi_out.xdc: ánh xạ chân HDMI OUT theo master XDC trong workspace.
- add_integration_sources.tcl: thêm nguồn vào project tích hợp riêng; dừng nếu thiếu BD.
- repair_usb_hdmi.tcl: sửa cấu hình/kết nối BD trong project đang mở; sao lưu trước khi chạy.
- Không có chân usb_dp/usb_dm ở top: webcam nối USB host của PS qua PHY trên board.
  Cổng micro-USB PROG/UART không thay thế cổng USB host nhận webcam.

## Luồng dữ liệu

USB webcam → ARM/Linux → khung ảnh trong DDR.
Một bản ảnh RGB resize 32×32 → giao tiếp AXI → CNN → nhãn có/không.
ARM vẽ nhãn lên khung hình hiển thị → DDR framebuffer → VDMA
→ AXI4-Stream to Video Out → RGB2DVI → HDMI OUT.

Ảnh đưa CNN và ảnh hiển thị là hai kích thước độc lập.
Có thể bắt đầu với HDMI 640×480; clock phải theo video mode đã chọn.
Không dùng trực tiếp clock CNN 125 MHz làm pixel clock HDMI.

## Tạo project và Block Design

1. Tạo project riêng cho xc7z020clg400-1, dùng board preset PYNQ-Z2 phù hợp.
   Có thể tham khảo PYNQ-Z2 base overlay để lấy cấu hình PS/video đã có.
2. Tạo Block Design tên chính xác usb_hdmi_system.
3. Thêm Zynq7 Processing System; cấu hình DDR, USB ULPI/MIO, SD và UART
   đúng board và hệ Linux dự kiến boot. Export DDR và FIXED_IO.
   Có thể cấu hình USB riêng trong BD đang mở bằng:
   source <thu_muc_nguon>/pynq_z2_usb_ps.tcl
   configure_pynq_z2_usb processing_system7_0
   Thay processing_system7_0 bằng tên cell PS thực tế.
4. Bật M_AXI_GP0 cho điều khiển; bật S_AXI_HP0 cho VDMA truy cập DDR.
   Nối AXI Interconnect/SmartConnect, Processor System Reset và clock.
5. Thêm VDMA đường đọc MM2S, Video Timing Controller,
   AXI4-Stream to Video Out, RGB2DVI và bộ tạo pixel/serializer clock.
   Nối các tín hiệu stream, sync, DE, RGB và clock theo tài liệu của IP.
   Thêm bộ chuyển định dạng stream nếu độ rộng pixel/stream không khớp.
   Tên cổng ngoài phải khớp chính xác soc_usb_hdmi_top.v.
6. Export hdmi_tx_clk_p/n, hdmi_tx_d_p/n[2:0], hdmi_tx_hpdn.
   HPDN là tín hiệu active-low: đảo nếu phần điều khiển cần HPD active-high.
   Bộ file chỉ nhắm video cơ bản; chưa triển khai CEC, âm thanh hay đọc EDID.
7. Thêm đường truy cập CNN như mục dưới. Validate BD; sửa mọi lỗi clock,
   reset, address map trước khi chạy Tcl thêm top-level.
8. Trong Tcl Console: source <duong_dan>/fpga_usb_hdmi/add_integration_sources.tcl
9. Build synthesis/implementation, kiểm tra timing/DRC và tài nguyên rồi tạo .bit.
   Export .hwh cùng .bit nếu dùng PYNQ overlay. Boot Linux phù hợp cấu hình PS.

Wrapper này không instantiates soc_top cũ: việc nối SoC phải làm bên trong BD
sau khi xuất được giao tiếp ngoài. Chỉ đặt soc_top hiện tại vào BD chưa đủ.

## Nối với SoC hiện tại

soc_top.v hiện chỉ có PicoRV32 làm chủ đường điều khiển AXI nội bộ.
Muốn ARM truy cập cùng CNN phải bổ sung cổng AXI slave bên ngoài và bộ phân xử
giữa ARM/PicoRV32. Không nối chung trực tiếp hai bộ phát AXI.

Nếu giữ PicoRV32: ARM ghi ảnh, báo FRAME_READY; PicoRV32 chạy CNN và báo RESULT_READY.
Cần handshake và quyền sở hữu buffer rõ ràng, đồng bộ clock nếu khác miền clock.
Phải viết firmware điều khiển thay cho bram_test.c.

Một lựa chọn khác là ARM điều khiển trực tiếp module CNN hiện có trong thiết kế
tích hợp riêng; lúc đó không cần PicoRV32 cho tác vụ camera/CNN.
Đây là thay đổi kiến trúc cần thực hiện, chưa được bộ file này tự động áp dụng.

## Thanh ghi CNN đã kiểm tra trong nguồn hiện tại

CNN.v giải mã offset 12 bit; base hiện dùng trong soc_top là 0x40004000.
Địa chỉ từ ARM phải được cấp trong Address Editor; không mặc định đã truy cập được.

| Offset | Chức năng |
| --- | --- |
| 0x000–0xBFC | 768 từ ảnh 32 bit, tổng 3072 byte |
| 0xFE0 | DMA_BASE |
| 0xFE4 | CONFIG; dùng 768 cho 768 từ, DMA/ping-pong tắt |
| 0xFE8 | Số chu kỳ xử lý lần trước |
| 0xFF4 | RESULT bit 0: có người |
| 0xFF8 | STATUS bit 0 busy, bit 1 done |
| 0xFFC | CONTROL bit 0 start |

Bắt đầu bằng đường frame_mem: ghi đủ 768 từ ảnh, ghi START,
chờ xử lý hoàn tất với timeout, đọc RESULT. Không ghi đè ảnh khi busy.
dma32_to_rgb24 được đặt MSB_FIRST=1: bốn byte liên tiếp b0,b1,b2,b3
phải được đóng thành word (b0<<24)|(b1<<16)|(b2<<8)|b3.
Chuyển ảnh camera sang RGB trước; không đưa BGR mặc định của OpenCV vào CNN.
Resize toàn khung bằng cùng tiền xử lý khi train (Pillow bilinear RGB 32×32).
Không lượng tử hóa hai lần: giữ byte RGB8 ở đầu vào, RTL thực hiện lượng tử hóa.

## Phần mềm và kiểm tra

- ARM/Linux cần USB host và driver UVC cho webcam tương thích.
- Phần mềm nhận ảnh, truyền CNN, quản lý framebuffer và vẽ nhãn.
- Dùng khung mẫu đã biết trước để đối chiếu RTL/Python trước khi bật webcam.
- Thử HDMI test pattern trước khi ghép ảnh camera.
- Sau đó ghép webcam → CNN → chữ CO NGUOI/KHONG CO NGUOI trên HDMI.
- Trọng số COCO hiện tại đã có trong nguồn nhưng .bit cũ chưa chứa chúng.
- Accuracy validation hiện khoảng 65,62%; chưa đo trên camera thực.

## Trạng thái kiểm tra bộ file

Kiểm tra cú pháp Verilog riêng không đồng nghĩa elaborate, synthesis hoặc chạy board.
Không có stub usb_hdmi_system trong bộ file; Vivado phải dùng Block Design thật.
Không thay firmware/bram_test.c, soc_top.v hoặc XDC của project hiện tại.

Tham khảo:
https://pynq.readthedocs.io/en/v2.7.0/pynq_overlays/pynqz2.html

