# Tài liệu block CNN – kiến trúc, địa chỉ CPU và các tối ưu

## 1. Tổng quan

Thiết kế CNN gồm các khối chính:

```text
CPU/PicoRV32
    |
    +-- AXI4-Lite --> CNN register + baseline frame memory
    |
    +-- AXI4-Lite --> CNN memory subsystem
                              ^
                              |
                         CNN DMA read

CNN frame stream --> DMA32-to-RGB24 --> CNN sequential core --> classification
```

CNN nhận một frame RGB kích thước 32x32, tương đương 1024 pixel hoặc 3072 byte.
Dữ liệu được truyền theo word 32-bit; bộ chuyển đổi `dma32_to_rgb24` ghép các byte thành pixel RGB888.

## 2. Các file chính

| File | Chức năng |
|---|---|
| `CNN.v` | AXI4-Lite slave, frame memory, DMA control, status và START |
| `cnn_docx_reference.v` | Core CNN tuần tự: Conv, Pooling, FC và phân loại |
| `dma32_to_rgb24.v` | Đổi stream word 32-bit thành pixel RGB24 |
| `cnn_memory_subsystem.v` | Bộ nhớ hai buffer cho đường DMA |
| `Tb_CNN.v` | Test baseline, DMA và ping-pong |
| `tb_soc.v` | Kiểm tra tích hợp AXI/peripheral |

## 3. Địa chỉ CPU

### CNN peripheral

Base address: `0x40004000`

| Địa chỉ | Chức năng |
|---|---|
| `0x40004000 – 0x40004BFF` | Baseline frame memory, 768 word 32-bit |
| `0x40004FE0` | DMA base address |
| `0x40004FE4` | CONFIG |
| `0x40004FE8` | Số chu kỳ compute của frame cuối |
| `0x40004FEC` | Số DMA read-address handshake |
| `0x40004FF0` | Số lần CPU ghi frame baseline |
| `0x40004FF4` | Kết quả classification, bit 0 |
| `0x40004FF8` | STATUS: busy, done, DMA, buffer, ping-pong |
| `0x40004FFC` | CONTROL: ghi bit 0 để START |

### CNN DMA memory

| Địa chỉ | Chức năng |
|---|---|
| `0x40006000 – 0x40006BFF` | Buffer 0 |
| `0x40006C00 – 0x400077FF` | Buffer 1 |

## 4. Luồng xử lý CNN

Core thực hiện:

1. Capture 1024 pixel RGB.
2. Conv1: 4 output channels, kernel 3x3, output 30x30.
3. Max-pooling 2x2.
4. Conv2 và pooling.
5. Conv3 và pooling.
6. Fully-connected 16 weight.
7. Classification dựa trên dấu của tổng FC.

Các tensor trung gian đang dùng signed 8-bit; accumulator dùng signed 32-bit.
Hàm QReLU dịch phải 4 bit và giới hạn kết quả trong khoảng 0 đến 127.

## 5. Tối ưu đã thực hiện

### 5.1. Song song hóa 4 MAC mỗi clock

File: `cnn_docx_reference.v`

Trước tối ưu, mỗi clock chỉ tính:

```text
acc = acc + input * weight
```

Sau tối ưu, mỗi clock tính tối đa 4 tích rồi cộng dồn:

```text
acc = acc + product0 + product1 + product2 + product3
```

Tác dụng:

- Giảm số clock của các lớp convolution và FC.
- Tăng throughput của CNN.
- Giảm thời gian chờ CPU khi polling DONE.

Đánh đổi:

- Tăng số multiplier/DSP hoặc LUT sử dụng.
- Tăng độ rộng và độ dài của mạch cộng.
- Cần kiểm tra lại timing sau synthesis/implementation.

### 5.2. Snapshot cấu hình DMA tại START

File: `CNN.v`

Các cấu hình `frame_words`, `dma_enable`, `pingpong_enable` được chụp vào thanh ghi active khi START.
Trong lúc `busy`, CPU không thể thay đổi cấu hình đang chạy.

Tác dụng:

- Tránh đổi nguồn dữ liệu giữa chừng.
- Tránh đổi buffer hoặc số word khi DMA đang đọc.
- Làm ping-pong ổn định hơn.

### 5.3. Tính tổng MAC bằng wire `total_next`

Tổng MAC được biểu diễn trực tiếp bằng:

```verilog
wire signed [31:0] total_next = acc + mac_sum;
```

Tác dụng:

- Loại bỏ thanh ghi trung gian không cần thiết.
- Giảm cảnh báo tổng hợp về `total_reg` bị loại bỏ.
- Làm datapath dễ đọc và dễ kiểm tra hơn.

## 6. Kết quả mô phỏng

| Chỉ số | Trước tối ưu | Sau tối ưu |
|---|---:|---:|
| Human frame | PASS | PASS |
| Non-human frame | PASS | PASS |
| Chu kỳ baseline/frame | khoảng 136557 | khoảng 44565 |
| Tốc độ cải thiện | 1x | khoảng 3x |

Kết quả sau tối ưu:

```text
[TB][SUMMARY] passed=2 failed=0
[TB][SUMMARY] CNN AXI TEST PASS
```

## 7. Các tối ưu nên thực hiện tiếp

1. Thay AXI-Lite DMA bằng AXI4 burst để đọc nhiều word mỗi lần.
2. Thêm FIFO prefetch giữa DMA và RGB unpacker.
3. Đưa feature map vào BRAM thay vì chỉ dùng mảng register.
4. Thay phép chia/modulo địa chỉ bằng counter.
5. Bật đầy đủ các test DMA buffer 0, buffer 1 và ping-pong trong `Tb_CNN.v`.
6. Chạy synthesis để kiểm tra LUT, DSP, BRAM và timing.
7. Đưa các file weight `.mem` vào project thay vì dùng đường dẫn tuyệt đối.

## 8. Kết luận

Tối ưu quan trọng nhất là xử lý 4 MAC song song, giúp giảm thời gian xử lý frame khoảng 3 lần trong mô phỏng.
Snapshot cấu hình DMA không trực tiếp tăng tốc nhưng loại bỏ lỗi cấu hình giữa frame và làm hệ thống đáng tin cậy hơn.
Nếu cần tăng tốc tiếp, hướng ưu tiên là AXI4 burst, FIFO prefetch và BRAM/line buffer.
