# Phân tích L1 RGB CNN và giao tiếp nạp pixel

## 1. Nội dung có trong tài liệu nguồn

File `_Three-Layer CNN Hardware Design.docx` mô tả giao diện và kiến trúc,
nhưng không chứa thân mã RTL của `window_generator_3ch.v` hoặc
`conv_3x3_mac_3to4.v`. Các kết luận dưới đây là hiện thực tham chiếu dựa
trên giao diện, tên thanh ghi và FSM được mô tả trong tài liệu.

## 2. `window_generator_3ch`: hai line buffer

Với mỗi pixel RGB hợp lệ ở tọa độ `(row, col)`, hai mảng thường được cập nhật
theo thứ tự đọc-cũ rồi ghi-mới:

```verilog
old_row1 = row1_delay[col]; // pixel cùng cột của hàng row-1
old_row2 = row2_delay[col]; // pixel cùng cột của hàng row-2
row2_delay[col] <= old_row1;
row1_delay[col] <= pixel_in_rgb;
```

Ba thanh ghi dịch ngang cho `old_row2`, `old_row1` và `pixel_in_rgb` tạo ra
ba hàng, mỗi hàng rộng ba pixel. Khi `row >= 2` và `col >= 2`, cửa sổ hiện
tại là:

```text
row-2:  (row2, col-2) (row2, col-1) (row2, col)
row-1:  (row1, col-2) (row1, col-1) (row1, col)
row:    (in,   col-2) (in,   col-1) (in,   col)
```

Mỗi pixel RGB được tách thành R/G/B; vì vậy `window_R`, `window_G` và
`window_B` đều chứa 9 phần tử 8-bit, tổng cộng 72 bit. Hai hàng đầu và hai
cột đầu phải bị đánh dấu `valid=0`. Với ảnh 32x32, số cửa sổ 3x3 hợp lệ là
`30x30=900`; con số 225 trong tài liệu là số điểm sau max-pool 2x2, không
phải số cửa sổ convolution thô.

Điểm quan trọng về backpressure: nếu cửa sổ hiện tại đang `valid=1` nhưng
khối sau chưa `ready`, generator không được nhận pixel mới, vì nhận thêm sẽ
thay đổi line buffer và làm mất cửa sổ đang chờ. Cần giữ nguyên cả cửa sổ,
`valid` và các bộ đệm cho đến khi có handshake.

## 3. `conv_3x3_mac_3to4`: ánh xạ 108 weights

Có 4 output channel, 3 input channel và 9 vị trí kernel:

```text
weight_index(out_ch, in_ch, k) = out_ch*27 + in_ch*9 + k
```

Do đó mỗi output channel cộng 27 tích:

```text
sum[out_ch] = sum(k=0..8) (
    R[k] * W[out_ch*27 +  0 + k] +
    G[k] * W[out_ch*27 +  9 + k] +
    B[k] * W[out_ch*27 + 18 + k]
)
```

FSM được tài liệu nêu là:

```text
IDLE -> CALC_CH0 -> CALC_CH1 -> CALC_CH2 -> CALC_CH3 -> DONE -> IDLE
```

Diễn giải tự nhiên của FSM này là mỗi trạng thái `CALC_CHx` thực hiện một
tổng 27 tích (bằng unroll/combinational loop) trong một chu kỳ. Nếu muốn
dùng một multiplier duy nhất theo thời gian, cần thêm bộ đếm `term_idx`
0..26; khi đó FSM trong tài liệu chưa đủ để mô tả toàn bộ latency.

`weights[0:107]` là signed 8-bit và accumulator 20-bit signed theo tài liệu.
Nếu dữ liệu RGB là byte thô 0..255 thì không nên tùy tiện diễn giải byte đó
như signed 8-bit, vì giá trị >=128 sẽ thành âm. Cần thống nhất trước một
trong hai quy ước: chuẩn hóa/center RGB về signed hoặc zero-extend input rồi
dùng phép nhân signed phù hợp.

## 4. Sơ đồ timing L1 đề xuất

```text
cycle       t0       t1       t2       t3       t4       t5       t6
FSM         IDLE     CH0      CH1      CH2      CH3      DONE     IDLE
window      latch    stable   stable   stable   stable   stable   next
valid_in    1        0        0        0        0        0        ...
busy        0        1        1        1        1        1        0
valid_conv  0        0        0        0        0        1        0
```

`valid_conv` là xung báo bốn output channel tương ứng đã có giá trị hợp lệ.
Trong pipeline thực tế, xung này đi vào ReLU; sau đó max-pool chỉ phát ra ở
các vị trí hàng/cột lẻ, nên L1 cho 225 output sau pooling.

## 5. Data converter và FIFO

`dma32_to_rgb24.v` giả sử byte đầu tiên nằm ở `dma_data[31:24]`. Nó giữ một
word DMA, lấy từng byte, ghép ba byte thành một pixel và giữ byte thứ tư để
ghép với word kế tiếp. `MSB_FIRST=0` cho phép đổi sang thứ tự byte ngược.

`input_fifo_rgb.v` là FIFO vòng ready/valid. Khi CNN kéo `pixel_ready` xuống 0,
`pixel_valid/data` vẫn ổn định; khi FIFO đầy, backpressure đi ngược qua
`dma_ready`. Push và pop cùng chu kỳ được hỗ trợ, kể cả khi FIFO đang đầy.

Ảnh RGB 32x32 có 3072 byte, đúng 768 word 32-bit, nên không cần xử lý word
cuối thiếu byte cho kích thước ảnh này. Nếu DMA dùng frame có kích thước
không chia hết cho 4, nên bổ sung `dma_keep[3:0]` và `dma_last` vào converter.

## 6. Các file RTL

- `dma32_to_rgb24.v`: converter 32-bit DMA -> 24-bit RGB.
- `input_fifo_rgb.v`: FIFO chống tràn khi CNN bận.
- `cnn_input_frontend.v`: wrapper nối hai khối.
- `tb_pixel_input_stream.v`: testbench gửi 24 byte qua 6 DMA words, giữ
  `pixel_ready=0` trong giai đoạn đầu để kiểm tra backpressure và thứ tự.

