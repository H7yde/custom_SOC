# Vivado project HUFLIT SoC

Cập nhật: **28/10/2026**. Tài liệu chính nằm tại [README của repository](../README.md).

Mở `SOC_HUFLIT_2026.xpr` trong thư mục này. Tên thư mục giữ hậu tố `50MHz`, nhưng
project hiện cấu hình clock **100 MHz**.

| Hạng mục | Cấu hình hiện tại |
|---|---|
| Device | `xc7z020iclg400-1L` |
| Board preset | Chưa chọn |
| Top tổng hợp / mô phỏng | `soc_top` / `tb_CNN` |
| Tham số | `CLK_FREQ=100000000`, `DDR_TX_PHASED_CLOCK=1` |
| Synthesis / implementation | `synth_100MHz` / `impl_100MHz` |
| Constraint set | `constrs_1`, file `soc_top.xdc` |

**XDC hiện vẫn gán chân HuMANDATA XCM-208A Artix-7 FBG676.** Cần sửa pinout và
điện áp I/O theo schematic board Zynq CLG400 thực tế trước khi implementation/nạp
board. Việc đổi device trong Vivado không tự chuyển sơ đồ chân sang board mới.

RTL đang biên dịch nằm trong `SOC_HUFLIT_2026.srcs/sources_1/new/`; không nhầm
với các bản sao RTL cũ trong thư mục con `source/`. Bốn lệnh đọc weight của core
hiện trỏ tuyệt đối đến các file `.mem` trong `new/source/` dưới workspace
`D:/LAB/custom_SOC-main`. Khi chuyển máy cần sửa đường dẫn tương ứng.

CNN đã có clock gating bằng `BUFGCE` và frame buffer đọc đồng bộ dùng BRAM.
AXI/status vẫn chạy khi CNN nghỉ. Để chạy bài kiểm tra, đứng tại thư mục gốc repo:

```powershell
powershell -ExecutionPolicy Bypass -File firmware/sim/run_cnn_clock_gating.ps1 -VivadoBin D:/Vivado_data/2025.2/Vivado/bin
```

Chỉnh `-VivadoBin` theo máy. Bài test đã ghi nhận PASS năm lượt ảnh, kiểm tra cả
baseline/DMA, reset và dữ liệu pixel. Các số liệu LUT/power trên Artix trong tài
liệu là kết quả các lần chạy trước, không phải kết quả của target Zynq hiện tại.

Xem thêm [firmware](../firmware/README.md), [CNN](../CNN_documentation_optimization.md)
và [các vấn đề SoC còn tồn tại](../SOC_REVIEW_2026-10-27.md).

Repository: [H7yde/custom_SOC](https://github.com/H7yde/custom_SOC).

