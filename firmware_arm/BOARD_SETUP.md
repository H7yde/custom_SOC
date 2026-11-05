# Nạp và chạy HUFLIT SoC trên board Zynq PYNQ-Z2

Hướng dẫn này dùng thiết kế hiện tại trên **PYNQ-Z2, Zynq-7000
`xc7z020clg400-1`**. Project được lưu bằng Vivado 2025.2; dùng Vivado/Vitis
cùng phiên bản khi build lại. Nếu dùng ZedBoard, Zybo hoặc board Zynq khác,
cần thay cấu hình DDR/MIO, XDC và Linux image theo board đó trước khi nạp.

## 1. Chọn cách chạy và chuẩn bị

| Bạn muốn chạy gì? | Làm theo | Sau khi tắt nguồn |
| --- | --- | --- |
| Kiểm tra HDMI bằng thanh màu, debug ARM | Mục 2 → 3: JTAG/Vitis | Cần nạp lại |
| Webcam USB, HDMI và CNN trong FPGA | Mục 2 → 4: SD PYNQ/Linux + overlay | Boot Linux rồi chạy lại launcher |
| ARM tự chạy thanh màu khi bật nguồn | Mục 2 → 3 để kiểm tra, rồi mục 5: SD `BOOT.BIN` | Tự boot từ SD |
| Gửi ảnh từ PC qua UART cho PicoRV32 | Mục 2 → 6 | Cần nạp lại `.bit` nếu chỉ dùng JTAG |

Chuẩn bị:

- Board PYNQ-Z2 và cáp **micro-USB có truyền dữ liệu** cho cổng PROG/UART.
- Nguồn phù hợp với board; chọn jumper nguồn USB/REG theo nguồn đang dùng.
  Với webcam, dùng nguồn đủ dòng để tránh board hoặc camera khởi động lại.
- Màn hình và cáp cắm vào **HDMI OUT**; webcam UVC cắm vào **USB HOST**.
- Vivado/Vitis 2025.2 có hỗ trợ Zynq-7000 và driver cable/JTAG trên Windows.
- Python 3 trên Windows để đóng gói overlay. Linux flow cần thêm thẻ microSD,
  đầu đọc thẻ và Ethernet để vào SSH/Jupyter.

Tắt nguồn trước khi đổi jumper boot. Manual PYNQ-Z2 v1.1 gọi jumper boot là
**JP1**, jumper nguồn là **J9**; chọn theo chữ **JTAG / SD / QSPI** và
**USB / REG** in trên board, đối chiếu manual đúng revision.
Xem [TUL PYNQ-Z2 Reference Manual, mục 3–4](https://dpoauwgwqsy2x.cloudfront.net/Download/PYNQ_Z2_User_Manual_v1.1.pdf).

Các file sẽ gặp:

| File | Dùng ở đâu? | Cách tạo |
| --- | --- | --- |
| `soc_top.bit` | Cấu hình phần FPGA/PL | Vivado Generate Bitstream |
| `soc_top.xsa` | Mô tả phần cứng cho Vitis và đóng gói overlay | Vivado Export Hardware, Include bitstream |
| `ps7_init.tcl` | Khởi tạo PS/DDR/FCLK khi debug JTAG | Sinh từ đúng XSA/platform trong Vitis |
| `arm_test.elf` | Chương trình ARM standalone hiển thị thanh màu | Build application `arm_test` |
| `fsbl.elf` | First Stage Boot Loader để boot standalone từ SD | Build boot domain Zynq FSBL của platform |
| `soc_camera_hdmi.bit` + `.hwh` | Cặp overlay cho PYNQ | `prepare_package.py` lấy cùng một XSA |
| `camera_hdmi_pynq.zip` | Gói copy sang Linux trên board | `prepare_package.py` |
| `BOOT.BIN` | Boot ARM standalone từ SD | Bootgen ghép FSBL + BIT + ELF |
| `firmware.hex` và các weight `.mem` | Firmware PicoRV32 và trọng số CNN trong PL | Được nhúng khi build bitstream |

`.bit`, `.xsa`, `.bin` và các thư mục build không có trong bản clone do
`.gitignore`. `.elf` và PS7 init phải được build/sinh lại cho phần cứng đang dùng.
Không lấy BIT, XSA, HWH hoặc PS7 init từ các lần build khác nhau để ghép lại.

## 2. Build bitstream và export XSA trên Windows

### Bước 1 — Lấy source

Nếu chưa có repo, mở PowerShell tại thư mục muốn lưu rồi chạy:

```powershell
git clone https://github.com/H7yde/custom_SOC.git
cd custom_SOC
```

Nếu đã có repo, dùng thư mục hiện tại. Các lệnh Windows dưới đây chạy từ
**gốc repo**; ví dụ máy hiện tại là `D:\LAB\custom_SOC-main`.

### Bước 2 — Chuẩn bị IP và mở đúng project

1. Repo đã kèm [Digilent vivado-library](../third_party/vivado-library) trong
   `third_party/vivado-library`, giữ nguyên cấu trúc IP và giấy phép gốc.
   Không cần tải thư viện riêng từ bên ngoài.
2. Mở Vivado → **Open Project** →
   `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr`.
3. Project đã dùng đường dẫn tương đối `../third_party/vivado-library` tính từ
   thư mục chứa `.xpr`. Vào **Settings → IP → Repository** để kiểm tra và
   cập nhật IP catalog. Nếu workspace cũ còn đường dẫn
   `D:/Vivado_IDE/lib/vivado-library-master`, thay bằng thư mục
   `third_party/vivado-library` trong bản clone hiện tại.
4. Mở **Report IP Status**, xử lý IP bị thiếu hoặc bị khóa. Nếu có yêu cầu
   nâng phiên bản IP, lưu bản dự phòng project trước khi nâng và kiểm tra lại BD.
5. Trong Sources, mở block design `usb_hdmi_system`, **Validate Design**,
   rồi **Generate Output Products**. Xác nhận wrapper và các source của BD
   đã được thêm vào project.

Không tạo một PS7 hoặc block design rỗng để thay thế thiết kế hiện tại:
BD này chứa đường ARM/CNN, VDMA, VTC, clock và HDMI.

### Bước 3 — Kiểm tra cấu hình trước khi build

1. Top của Design Sources phải là **`soc_top`**, part là `xc7z020clg400-1`.
2. Giữ `ENABLE_USB_HDMI=1`. Kiểm tra `firmware.hex` và các weight `.mem`
   còn trong Design Sources/Memory Initialization Files.
3. Constraint board dùng
   `SOC_HUFLIT_2026.srcs/constrs_1/new/soc_top.xdc` trong thư mục project:
   clock H16 có period **8 ns = 125 MHz**. PS FCLK0 của video/AXI là 100 MHz.
4. Kiểm tra SW0 nối `resetn` ở mức **1** khi chạy; mức 0 giữ phần SoC
   trong reset. Không để switch reset ở mức 0 khi thử CNN.

Nếu vừa sửa firmware PicoRV32, build trước trên Windows:

```powershell
python firmware/build.py --app cnn
```

Lệnh cần RISC-V GCC; xem [firmware/README.md](../firmware/README.md).
Sau đó trong **Vivado Tcl Console** của project đang mở:

```tcl
set repo_dir [file normalize [file join [get_property DIRECTORY [current_project]] ..]]
source [file join $repo_dir firmware select_cnn_firmware.tcl]
```

Nếu giữ firmware và weight hiện có, có thể dùng các file đã lưu trong source.
Mọi thay đổi firmware/weight trong BRAM/ROM cần build lại bitstream để lên board.

### Bước 4 — Synthesis, implementation và bitstream

1. Chọn synthesis/implementation run của thiết kế tích hợp `soc_top` trong
   **Design Runs**. Project hiện có các run `synth_soc_usb_hdmi` /
   `impl_soc_usb_hdmi`; nếu tạo run mới, dùng cùng source/constraint của thiết kế này.
2. Chạy **Run Synthesis**, xử lý lỗi rồi chạy **Run Implementation**.
3. Mở implemented design, xem Timing Summary và DRC. Kiểm tra setup/hold
   của chính lần build này; không dùng kết quả timing của một lần build cũ.
4. Khi timing và DRC đã được xử lý, chọn **Generate Bitstream** cho run đó.
5. Ghi lại đường dẫn `.bit` vừa tạo. Thông thường nằm ở
   `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.runs/<implementation_run>/soc_top.bit`.

`firmware/run_project_125MHz.tcl` có các kiểm tra topology clock của cấu hình
Pico/DDR cũ; không dùng script này làm bước build cho thiết kế USB/HDMI tích hợp.

### Bước 5 — Export phần cứng có bitstream

Trong Vivado, chọn **File → Export → Export Hardware**, chọn hardware của
implemented design vừa build và bật **Include bitstream**. Lưu thành:

```text
SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa
```

Kiểm tra XSA có đúng một BIT và một HWH bằng PowerShell tại gốc repo:

```powershell
python -c "from zipfile import ZipFile; z=ZipFile('SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa'); print('\n'.join(n for n in z.namelist() if n.endswith(('.bit', '.hwh'))))"
```

Nếu không có `.bit`, export lại với Include bitstream. Dùng XSA này cho các
bước Vitis hoặc PYNQ bên dưới.

## 3. Nạp qua JTAG bằng Vitis để thử HDMI standalone

### Bước 1 — Kết nối board

1. Tắt nguồn, đặt jumper boot về **JTAG** theo nhãn/manual, rồi cấp nguồn lại.
2. Nối cáp micro-USB từ PC vào **PROG/UART**, HDMI từ **HDMI OUT** tới màn hình.
3. Trong Windows Device Manager, xem COM của USB Serial Port.
   Mở PuTTY/Tera Term: **115200 baud, 8 data bits, no parity, 1 stop bit,
   no flow control**.
4. Trong Vivado Hardware Manager, **Open Target → Auto Connect** để kiểm tra
   PC nhận được Zynq. Nếu chưa nhận, kiểm tra driver, cáp dữ liệu và nguồn.

### Bước 2 — Tạo hoặc cập nhật platform Vitis

1. Mở Vitis Unified IDE, chọn workspace cho dự án này.
2. Nếu dùng workspace đang có, cập nhật hardware specification của
   `soc_platform` tới XSA vừa export. File `soc_platform/vitis-comp.json`
   hiện chứa đường dẫn của máy cũ; sau khi clone phải chọn lại đường dẫn local.
3. Nếu tạo workspace mới, tạo **Platform Component** từ `soc_top.xsa`, đặt
   tên `soc_platform`, processor **`ps7_cortexa9_0`**, domain
   **standalone** (`standalone_ps7_cortexa9_0`). Tạo/bật boot domain **Zynq FSBL**
   nếu cần boot SD ở mục 5.
4. **Build platform**. BSP của ứng dụng HDMI phải có `xaxivdma`, `xvtc`
   và các driver PS tương ứng. Không sửa địa chỉ trong C để che việc dùng sai XSA.

### Bước 3 — Build chương trình ARM

1. Mở/import application component `arm_test`, gắn với platform vừa build
   và domain `standalone_ps7_cortexa9_0`.
2. Với workspace mới, có thể tạo application từ template Empty Application
   rồi thêm source trong `arm_test/src`; dùng `main.c` hiện có để thử thanh màu.
3. Chỉ giữ **một `main()`**. `firmware_arm/hdmi_color_bars.c` là bản tái sử dụng,
   không thêm cùng lúc với `arm_test/src/main.c`.
4. Kiểm tra linker script đặt chương trình/framebuffer trong DDR rồi **Build**.
   ELF của workspace hiện tại là `arm_test/build/arm_test.elf`; nếu workspace
   mới tạo đường dẫn khác, chọn đúng ELF từ kết quả build đó.

### Bước 4 — Chọn cấu hình nạp và chạy

Mở **Run/Debug configuration** cho Hardware/JTAG của `arm_test`, kiểm tra:

| Mục | Giá trị cần chọn |
| --- | --- |
| Connection | Local hardware server, board PYNQ-Z2 đã kết nối |
| Processor | `ps7_cortexa9_0` |
| Reset system | Bật khi bắt đầu phiên standalone mới |
| Program device / FPGA | Bật, trỏ tới `soc_top.bit` vừa build |
| Zynq initialization | Chạy `ps7_init` và `ps7_post_config` từ đúng XSA/platform |
| Download application | `arm_test.elf` vừa build |

Repo có cấu hình tham khảo ở `arm_test/_ide/launch.json`. File đó trỏ BIT tới
`arm_test/_ide/bitstream/soc_top.bit`, PS7 init tới
`arm_test/_ide/psinit/ps7_init.tcl`; kiểm tra/sinh lại các file này theo XSA
hiện tại hoặc đổi đường dẫn trong cấu hình launch. Không mặc định các bản copy
cũ đã được cập nhật khi vừa export XSA mới.

Nhấn **Run/Debug**: công cụ reset board, nạp PL, khởi tạo PS/DDR/FCLK và tải
ELF. Nếu dừng ở `main()`, nhấn **Resume/Continue**. Chỉ Program Device trong
Vivado nạp phần PL; chương trình ARM vẫn cần được Vitis tải và chạy.

### Bước 5 — Xác nhận

UART PS phải hiện các dòng tương tự:

```text
HDMI COLOR BARS 640x480 @60Hz
DDR color bars written; cache flushed
VTC enabled; VDMA MM2S started. Check HDMI OUT.
```

Màn hình hiện tám thanh màu, `ERR=00000000`; SR bit HALTED phải bằng 0.
Xem [HDMI_COLOR_BARS.md](HDMI_COLOR_BARS.md) để đọc trạng thái VDMA/VTC.
Đây là test HDMI; webcam USB dùng luồng Linux ở mục 4. Tắt/bật nguồn sẽ
mất cấu hình JTAG và chương trình trong DDR, nên cần launch lại.

## 4. Nạp bằng SD PYNQ/Linux để chạy webcam, HDMI và CNN

### Bước 1 — Ghi hệ điều hành lên thẻ SD

1. Lấy image **dành cho PYNQ-Z2** từ [PYNQ Boards](https://www.pynq.io/boards.html),
   giải nén file image theo hướng dẫn của bản phát hành.
2. Nếu thẻ đã boot PYNQ tốt, dùng tiếp. Với thẻ mới, dùng công cụ ghi image
   theo [hướng dẫn PYNQ](https://pynq.readthedocs.io/en/v2.7.0/appendix/sdcard.html)
   để ghi `.img` lên đúng thẻ và chờ verify xong. Bước ghi image sẽ xóa dữ liệu
   trên thẻ được chọn; sao lưu trước.
3. Eject thẻ, tắt board, đặt jumper boot **SD**, cắm thẻ rồi bật nguồn.
4. Nối Ethernet vào cùng mạng với PC. Mở UART PS 115200 8N1 để xem Linux boot
   và đăng nhập nếu cần kiểm tra địa chỉ IP bằng `hostname -I`.
5. Dùng IP/tài khoản thực tế của image để vào SSH hoặc Jupyter. Nếu không
   biết IP, xem danh sách DHCP của router. Kết nối PC trực tiếp cần cấu hình
   cùng subnet theo [PYNQ-Z2 Setup Guide](https://pynq.readthedocs.io/en/v2.7.0/getting_started/pynq_z2_setup.html).

Không chép `BOOT.BIN` standalone ở mục 5 đè lên thẻ PYNQ. Luồng này giữ
bootloader/kernel của image Linux, rồi nạp phần PL bằng overlay khi chạy ứng dụng.
Không chạy Vitis hardware launch hoặc `ps7_init.tcl` trên board đang chạy Linux.

### Bước 2 — Đóng gói thiết kế trên Windows

Trong PowerShell tại gốc repo, sau khi đã export XSA có bitstream ở mục 2:

```powershell
python firmware_arm/linux_camera_hdmi/prepare_package.py --xsa SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa
```

Kết quả: `firmware_arm/linux_camera_hdmi/camera_hdmi_pynq.zip`. ZIP chứa
`soc_camera_hdmi.bit`, `soc_camera_hdmi.hwh`, `camera_hdmi.py`, `cnn_fpga.py`,
`run_camera_hdmi.sh`, README và `manifest.json`. Script chỉ đóng gói;
không tự synthesis/export hoặc tạo Linux image. Tham số `--xsa` giúp tránh
đóng gói nhầm bản cũ trong thư mục export của Vitis.

### Bước 3 — Chép gói sang board

Cách dễ nhất: upload ZIP qua giao diện Jupyter, mở **Terminal**, chuyển đến
thư mục vừa upload, rồi chạy trên board:

```bash
unzip camera_hdmi_pynq.zip -d camera_hdmi
cd camera_hdmi
ls
```

Nếu cập nhật, upload ZIP mới vào thư mục riêng và giải nén vào thư mục mới
để tránh trộn file của hai lần build. Có thể dùng SCP nếu máy có SSH client:

```powershell
$boardAddress = 'DIA_CHI_IP_THUC_TE'
$boardAccount = 'TAI_KHOAN_TREN_BOARD'
scp firmware_arm/linux_camera_hdmi/camera_hdmi_pynq.zip "${boardAccount}@${boardAddress}:~/"
ssh "${boardAccount}@${boardAddress}"
```

Đổi hai giá trị ví dụ trước khi chạy. Nếu SCP chép vào home, chạy
`cd ~` trong SSH rồi giải nén như trên.

### Bước 4 — Kiểm tra file và webcam

Từ thư mục đã giải nén trên **Linux của board**:

```bash
python3 - <<'PY'
import hashlib, json
from pathlib import Path
manifest = json.loads(Path('manifest.json').read_text())
for name, expected in manifest['files'].items():
    actual = hashlib.sha256(Path(name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('Hash mismatch: ' + name)
    print('OK', name)
PY
lsusb
ls /dev/video*
```

Cắm webcam vào USB HOST. Nếu có `v4l2-ctl`, dùng
`v4l2-ctl --list-devices` để chọn đúng capture node, không mặc định mọi
`/dev/video*` đều đọc được hình.

### Bước 5 — Nạp overlay và thử thanh màu

```bash
sudo bash run_camera_hdmi.sh --bars --frames 180
```

Launcher thiết lập môi trường PYNQ/XRT, ứng dụng kiểm tra cặp BIT/HWH,
nạp overlay vào PL, cấp buffer DDR và khởi động HDMI. Không cần Program Device
qua JTAG trong luồng này. Kết quả mong đợi là thanh màu 640×480; hết 180 frame
ứng dụng dừng và màn hình có thể trở về đen.

Nếu báo `No Devices Found`, xem mục 7 và
[Linux README](linux_camera_hdmi/README.md#run-hdmi-first-then-camera).
Không thay overlay bằng `base.bit`, vì sẽ thay thế phần cứng SoC/CNN hiện tại.

### Bước 6 — Chạy webcam, rồi bật CNN

Thử webcam trước:

```bash
sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15
```

Khi hình camera đã ổn, nhấn Ctrl+C rồi chạy CNN:

```bash
sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15 --cnn --cnn-every 5
```

Nếu webcam chỉ hỗ trợ YUYV, thay `--fourcc MJPG` bằng `--fourcc YUYV`.
HDMI hiển thị camera và nhãn `LAST CNN: CO NGUOI` / `KHONG CO NGUOI`,
terminal in `CNN class=... cycles=... core_ms=...`. CNN phân loại toàn ảnh,
không vẽ bounding box. Chạy một client ARM/CNN tại một thời điểm.

Nhấn Ctrl+C để dừng, chờ chương trình giải phóng DMA rồi mới chạy ứng dụng khác.
Sau khi reboot Linux, vào lại thư mục đã giải nén và chạy launcher. Gói hiện
tại chưa cài dịch vụ tự chạy camera khi bật nguồn.

## 5. Tạo BOOT.BIN để ARM standalone tự chạy từ SD

Dùng mục này cho `arm_test` thanh màu đã chạy tốt qua JTAG. Webcam Python
cần Linux ở mục 4; đóng gói ELF thanh màu không tạo ra hệ điều hành Linux.

1. Build platform boot domain **Zynq FSBL** và application `arm_test` từ cùng
   XSA. Với workspace hiện tại, FSBL nằm ở
   `soc_platform/export/soc_platform/sw/boot/fsbl.elf`.
2. Tạo thư mục đóng gói, ví dụ `firmware_arm/boot_sd`, rồi chép ba file vào:

   ```text
   boot_sd/
     fsbl.elf
     soc_top.bit
     arm_test.elf
   ```

3. Trong thư mục đó, tạo `boot.bif` chứa:

   ```text
   the_ROM_image:
   {
       [bootloader] fsbl.elf
       soc_top.bit
       arm_test.elf
   }
   ```

4. Mở command prompt/terminal đã nạp môi trường AMD Vivado/Vitis để có
   `bootgen` trong PATH, chuyển tới `boot_sd`, chạy:

   ```text
   bootgen -arch zynq -image boot.bif -o BOOT.BIN -w on
   ```

5. Dùng **thẻ SD riêng cho standalone**, có phân vùng FAT32 đọc được bởi
   BootROM Zynq-7000. Chép `BOOT.BIN` vào gốc phân vùng FAT32; không chỉ chép
   riêng ELF/BIT. Eject thẻ sau khi ghi xong.
6. Tắt board, đặt boot mode **SD**, cắm thẻ, nối UART/HDMI rồi bật nguồn.
   BootROM tải FSBL; FSBL khởi tạo PS/DDR, nạp PL và chuyển tới `arm_test`.
7. Kiểm tra thông báo UART và tám thanh màu giống mục 3. Khi bật nguồn lại,
   board tự chạy từ `BOOT.BIN`, không cần Vitis nạp ELF.

Thứ tự partition và định dạng BIF tham khảo
[AMD Bootgen UG1283](https://docs.amd.com/r/2025.2-English/ug1283-bootgen-user-guide/image).
Luồng SD standalone này cần được xác nhận trên board sau khi tạo image.

## 6. Thử PicoRV32/CNN bằng UART từ PC

1. Build/nhúng firmware CNN UART và nạp `.bit` theo mục 2–3. PicoRV32 dùng
   `firmware.hex` trong BRAM; không tải `arm_test.elf` để thay cho firmware này.
2. Dùng USB–TTL logic **3,3 V** nối với UART **PL trên RPi header**:
   board TX pin FPGA **Y9** → RX adapter; board RX pin FPGA **A20** ← TX adapter;
   nối chung GND. Tra sơ đồ/header đúng revision để tìm chân vật lý.
3. Đặt SW0 để `resetn=1`, đóng phần mềm terminal khác đang giữ COM của adapter.
4. Trong PowerShell ở gốc repo, thay `COM5` bằng COM của **USB–TTL**:

   ```powershell
   python -m pip install -r firmware/requirements.txt
   python firmware/host.py --port COM5 --mode smoke
   python firmware/host.py --port COM5 --mode baseline --expect 1
   python firmware/host.py --port COM5 --mode pingpong --check-labels
   ```

`baseline` mặc định gửi ảnh mẫu `CNN_RTL/human_frames.mem`; kiểm tra nhãn có
thể thất bại nếu thay weight/model. Chạy riêng test UART này, không đồng thời
với client CNN ARM. UART PL trên header khác UART PS qua PROG/UART micro-USB.
Xem [firmware/README.md](../firmware/README.md) để biết giao thức và toolchain.

## 7. Lỗi thường gặp khi nạp

| Hiện tượng | Kiểm tra / cách xử lý |
| --- | --- |
| Vivado không thấy target | Nguồn, cáp micro-USB có data, đúng cổng PROG/UART, driver cable và hardware server |
| File `.xsa` / `.bit` không tồn tại sau clone | Build lại Vivado và export Include bitstream; các file này bị Git bỏ qua |
| Vitis báo đường dẫn phần cứng không tồn tại | Chọn lại XSA local, build lại platform/BSP và application, cập nhật launch BIT/PS7 init |
| Nạp BIT thành công nhưng HDMI không có hình | Chạy ELF ARM hoặc Linux launcher để khởi tạo PS/DDR/FCLK, VDMA/VTC; kiểm tra HDMI OUT và input của màn hình |
| Vitis không tải được ELF / lỗi DDR | Kiểm tra initialization dùng đúng XSA, PS7 init/post-config, nguồn và trạng thái reset |
| CNN không phản hồi | Kiểm tra SW0 để `resetn=1`, đúng bitstream/bridge, không có client khác giữ CNN |
| Linux không boot SD | Kiểm tra image đúng PYNQ-Z2, ghi image hoàn chỉnh, boot mode SD và log UART PS |
| Không có `/dev/video*` | Xem `lsusb`, `dmesg`, cáp/nguồn USB HOST và hỗ trợ UVC trong kernel |
| `No Devices Found` | Dùng `sudo bash run_camera_hdmi.sh ...`; kiểm tra script thiết lập PYNQ/XRT và image/kernel đúng board, rồi chạy Python process mới |
| Thiếu `pynq`, `cv2` hoặc `PIL` | Dùng môi trường PYNQ của image; kiểm tra import `pynq`, `cv2`, `numpy`, `PIL` trong môi trường đó trước khi thay package |
| Lỗi thiếu HWH / sai hash | Tạo lại ZIP từ một XSA, giải nén vào thư mục mới; giữ BIT/HWH cùng basename |
| VDMA timeout/error hoặc màn hình No Signal | Thử bars trước, lưu log SR/ERR; kiểm tra BIT/HWH khớp, DDR/HP0, pixel clock và không có notebook/driver khác dùng video IP |

Các bước trên mô tả quy trình nạp theo source và cấu hình launch trong repo.
Kết quả webcam/HDMI/CNN thực tế cần kiểm tra trên board; sửa tài liệu không
thay thế việc đo timing hoặc xác nhận phần cứng của lần build đang dùng.
