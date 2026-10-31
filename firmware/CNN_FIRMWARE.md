# Firmware CNN đang được chọn

Chương trình chạy trên PicoRV32 đã chuyển từ `bram_test.c` sang `main.c`.
`bram_test.c` được giữ để chẩn đoán bộ nhớ khi cần.

Build: `python firmware/build.py --app cnn`.

Bản có cầu nối ARM–CNN dùng thêm khóa tại `0x40004F00` trong `main.c`.
Firmware đã được build lại; xem [ARM_CNN_BRIDGE.md](../fpga_usb_hdmi/ARM_CNN_BRIDGE.md)
cho kiểm tra mới và driver ARM. Các log mô phỏng đầy đủ trước đó ở tài liệu
này thuộc phiên bản trước khi thêm khóa; bản mới đã kiểm tra boot và giao dịch khóa.
Vivado đang mở: `source D:/LAB/custom_SOC-main/firmware/select_cnn_firmware.tcl`.
Sau đó build lại synthesis/implementation/bitstream để firmware mới lên board.

Firmware nhận 3072 byte RGB qua UART, ghi vào bộ nhớ ảnh CNN, phát START,
chờ DONE với timeout, đọc nhãn và số chu kỳ. Kết quả có dạng:

```text
RESULT 1 STATUS 00000002 CYCLES 000BB916 READS 00000000
CLASS CO_NGUOI
READY
```

`CLASS KHONG_CO_NGUOI` ứng với nhãn 0. Đây là nhãn phân loại, không phải xác suất.
UART PicoRV32 dùng TX Y9 / RX A20 ở RPi header, 115200 baud, mức 3,3 V.
Ảnh lấy từ host bằng `firmware/host.py`; phần USB camera và HDMI chưa tích hợp.

## Kiểm tra ngày 31/10/2026

- Biên dịch RV32I đạt; code/data/BSS đến 0x9bc, vừa BRAM 4 KiB và vùng stack.
- `firmware/firmware.hex` và ảnh `firmware.hex` trong nguồn Vivado khớp SHA-256:
  `a01ee13286846ef57b60dce0e32c876f36a7511e3632ac6869c187c6ed7aa4d1`.
- Mô phỏng CPU thật ở 125 MHz, UART mô phỏng 1 Mbaud: BOOT PASS và SMOKE PASS.
- Ba phép suy luận ảnh đen qua baseline, DMA0 và DMA1 trả cùng nhãn;
  số lượt đọc DMA lần lượt 0, 768, 768. Ảnh đen chỉ kiểm tra đường truyền/tính toán.
- Lượt FULL_IMAGES được dừng sau SMOKE PASS trong lúc bắt đầu truyền ảnh COCO;
  không khẳng định FULL_IMAGES đã đạt. Log: `build/sim_cnn_coco_20261031/simulate.log`.
- Lượt tiếp theo đã hoàn tất phần ảnh COCO: **FIRMWARE INTEGRATION PASS**.
  Log: `build/sim_cnn_coco_full_20261031/simulate.log`. Lượt này dùng
  `-FullImages -SkipSmoke` để không lặp lại smoke đã đạt trước đó.
  Kiểm tra 5 suy luận: human qua baseline, human qua DMA0, nonhuman qua DMA1,
  rồi human/nonhuman qua ping-pong. Nhãn lần lượt 1, 1, 0, 1, 0;
  tổng 3072 lượt đọc DMA. Từng pixel sau upload cũng được đối chiếu.
- Chưa build bitstream mới hoặc thử firmware trên board.

Bản trước khi thay: `backups/before_cnn_firmware_20261031/`.
