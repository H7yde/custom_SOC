"""Create the Vietnamese Word change report from verified local results."""
from pathlib import Path
from zipfile import ZipFile
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/BAO_CAO_SUA_LOI_CNN_AXI_2026-11-05.docx"
checks = [
    ("arm_cnn_recovery/simulate.log", "ARM_CNN_RECOVERY_TEST_PASS"),
    ("cnn_dma_recovery/simulate.log", "CNN_DMA_RECOVERY_PASS"),
    ("arm_cnn_sim/simulate.log", "ARM_CNN_BRIDGE_TEST_PASS"),
    ("arm_cnn_firmware_boot/simulate.log", "ARM_CNN_FIRMWARE_RECOVERY_PASS"),
    ("recovery_synthesis.log", "RECOVERY_SOC_SYNTHESIS_PASS"),
]
for relative, marker in checks:
    text = (ROOT / "fpga_usb_hdmi/build_check" / relative).read_text(errors="replace")
    if marker not in text:
        raise RuntimeError(f"Missing verification result: {marker}")

doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21), Cm(29.7)
sec.top_margin = sec.bottom_margin = Cm(1.8)
sec.left_margin = sec.right_margin = Cm(2)
normal = doc.styles["Normal"]
normal.font.name = "Calibri"
normal.font.size = Pt(11)
normal.paragraph_format.space_after = Pt(6)
for name in ("Title", "Heading 1", "Heading 2"):
    doc.styles[name].font.name = "Calibri"
    doc.styles[name].font.color.rgb = RGBColor.from_string("17365D")
header = sec.header.paragraphs[0]
header.text = "SOC HUFLIT • CNN / AXI • Báo cáo thay đổi"
header.style = doc.styles["Caption"]
footer = sec.footer.paragraphs[0]
footer.text = "05/11/2026  |  Trang "
field = OxmlElement("w:fldSimple")
field.set(qn("w:instr"), "PAGE")
footer._p.append(field)


def p(text):
    doc.add_paragraph(text)


def table(headers, rows):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Light Shading Accent 1"
    for cell, value in zip(t.rows[0].cells, headers):
        cell.text = value
    for row in rows:
        for cell, value in zip(t.add_row().cells, row):
            cell.text = value
    for row in t.rows:
        props = row._tr.get_or_add_trPr()
        props.append(OxmlElement("w:cantSplit"))
    doc.add_paragraph()


doc.add_heading("BÁO CÁO CHỈNH SỬA\nCNN – AXI – SCRIPT BUILD", 0)
p("Ngày: 05/11/2026 • Project: SOC_HUFLIT_2026_parallel_125MHz • Board mục tiêu: PYNQ-Z2")
doc.add_heading("1. Mục tiêu và kết quả", 1)
p("Bổ sung phục hồi khi CNN hoặc bus phía sau cầu nối bị treo; sửa byte-enable khi ghi thanh ghi AXI; sửa đường dẫn project cũ. Đã cập nhật RTL, firmware PicoRV32, driver ARM và testbench. Firmware HEX mới đã được build và sao chép vào nguồn Vivado.")
table(["Hạng mục", "Trước khi sửa", "Sau khi sửa / công dụng"], [
    ("Bus/CNN bị treo", "Cầu nối có thể chờ vô hạn; phần mềm chỉ có polling timeout.", "Watchdog trả lỗi AXI khi cần, reset CNN và kênh DMA; giữ mã lỗi để chẩn đoán."),
    ("Ghi thanh ghi", "DMA_BASE, CONFIG, START chưa xét đầy đủ WSTRB.", "Chỉ byte được cho phép mới thay đổi; WSTRB=0 không kích hoạt START."),
    ("Đường dẫn project", "Một số script vẫn cố định thư mục 50MHz.", "Tự tìm project .xpr duy nhất; báo lỗi nếu thiếu hoặc có nhiều project."),
    ("Phục hồi phần mềm", "Chủ yếu yêu cầu reset hệ thống.", "ARM có arm_cnn_recover(); Pico có lệnh UART r; nạp lại ảnh sau phục hồi."),
])
p("Các thay đổi không tăng độ phân giải hoặc thay model CNN: đầu vào vẫn RGB 32×32, 3.072 byte. Chưa tạo bitstream mới, chưa chạy place-and-route và chưa kiểm thử trực tiếp trên board trong đợt này.")

doc.add_heading("2. Cơ chế watchdog và reset", 1)
p("Cầu nối theo dõi thời gian giao dịch AXI phía CNN và thời gian CNN liên tục BUSY. Khi vượt ngưỡng, nó giữ cờ lỗi, phát reset 8 chu kỳ tới CNN và nhánh phản hồi DMA của bộ nhớ cục bộ. Nếu đang có giao dịch AXI phía CNN, cầu nối trả SLVERR cho giao dịch đó. Các hàng đợi/phản hồi phía CPU không bị xóa.")
table(["Tham số", "Mặc định", "Tại clock 125 MHz"], [
    ("BUS_TIMEOUT_CYCLES", "4.096 chu kỳ", "32,768 µs / giao dịch chuyển tiếp"),
    ("CNN_TIMEOUT_CYCLES", "12.500.000 chu kỳ", "100 ms liên tục BUSY"),
    ("Thời gian reset", "8 chu kỳ", "64 ns"),
])
p("Khóa chủ sở hữu được giữ sau lỗi. Phần mềm đọc lỗi, yêu cầu phục hồi, chờ reset xong rồi nhả khóa. Cờ lỗi đang còn sẽ chặn truy cập thông thường vào CNN bằng SLVERR; các thanh ghi OWNER, ID và RECOVERY vẫn đọc được.")

doc.add_page_break()
doc.add_heading("3. Thanh ghi phục hồi mới", 1)
table(["Địa chỉ / bit", "Ý nghĩa"], [
    ("0x40004F08 – đọc bit 0", "Lỗi timeout giao dịch bus phía sau cầu nối; giữ tới khi acknowledge/reset."),
    ("0x40004F08 – đọc bit 1", "Lỗi CNN BUSY quá lâu; giữ tới khi acknowledge/reset."),
    ("0x40004F08 – đọc bit 8", "Reset CNN đang diễn ra; chờ bit này về 0."),
    ("0x40004F08 – ghi byte thấp = 1", "Yêu cầu abort/reset và xóa cờ lỗi. Bắt buộc WSTRB[0]=1. Chỉ chủ sở hữu hoặc khi chưa có chủ được thực hiện."),
    ("0x40004F00", "OWNER giữ nguyên địa chỉ: 0 rảnh, 1 PicoRV32, 2 ARM; bit 8 báo CNN BUSY."),
    ("0x40004F04", "ID cầu nối vẫn là 0x434E4E42."),
])
p("Reset phục hồi không reset PS7, HDMI, CPU hoặc toàn bộ bộ nhớ. Nó xóa trạng thái CNN, cấu hình CNN và phản hồi DMA đang chờ. Ảnh/trọng số trong RAM/ROM không được xem là frame hợp lệ để tiếp tục một công việc đã lỗi; luôn gửi lại đầy đủ ảnh và cấu hình.")
doc.add_heading("4. Sửa byte-enable và kênh DMA", 1)
table(["Vị trí", "Thay đổi"], [
    ("CNN.v – DMA_BASE, offset 0xFE0", "Cập nhật từng byte theo WSTRB[3:0], giữ các byte còn lại."),
    ("CNN.v – CONFIG, offset 0xFE4", "Byte 0/1 cập nhật số word; byte 2 cập nhật DMA/ping-pong/buffer-select. Byte 3 không thay đổi các trường này."),
    ("CNN.v – CONTROL, offset 0xFFC", "START chỉ nhận khi WSTRB[0]=1, bit START=1 và CNN không BUSY/pending START."),
    ("CNN.v – bộ đếm ghi ảnh", "Không tăng số lượt ghi ảnh khi WSTRB=0."),
    ("cnn_memory_subsystem.v", "Thêm dma_resetn riêng để xóa phản hồi DMA cũ mà giữ giao dịch CPU. Sửa phân xử read: DMA thắng khi CPU và DMA cùng yêu cầu, tránh cả hai cùng chờ."),
    ("soc_top.v / Tb_CNN.v", "Nối reset phục hồi vào CNN và nhánh DMA; cập nhật testbench cho cổng mới."),
])
doc.add_heading("5. Sử dụng từ ARM và UART Pico", 1)
p("ARM: arm_cnn_classify_rgb() trả -4 khi hết thời gian chờ phần mềm, -5 khi phát hiện lỗi watchdog/reset. Gọi arm_cnn_recover(1000000u); nếu trả 0 thì khóa ARM đã được nhả, có thể gửi lại toàn bộ frame. Nếu trả -3, không có quyền sở hữu để phục hồi. Chỉ một tác vụ ARM gọi driver tại một thời điểm.")
p("PicoRV32: gửi ký tự r thường qua UART. Khi nhận RECOVERED; RELOAD FRAME, gửi lại ảnh bằng lệnh B/0/1. Lệnh r không được phép hủy công việc do ARM sở hữu. Firmware xóa trạng thái loaded_buffers sau phục hồi để không dùng nhầm dữ liệu ping-pong cũ.")

doc.add_page_break()
doc.add_heading("6. Sửa đường dẫn và script Vivado", 1)
p("CNN_RTL/project_paths.py và firmware/project_paths.tcl là hai bộ phân giải đường dẫn dùng chung. Chúng tìm SOC_HUFLIT_2026_parallel_*/SOC_HUFLIT_2026.xpr từ thư mục repository. Nếu không có hoặc có nhiều file phù hợp, script dừng và báo lỗi; không tự chọn bản cũ.")
table(["Nhóm file", "Công dụng sau chỉnh sửa"], [
    ("deploy_coco_model.py; verify_coco_rtl.py", "Dùng đúng thư mục RTL để xác minh và triển khai trọng số model."),
    ("run_project_125MHz.tcl; select_timing_constraints_125MHz.tcl", "Kiểm tra đúng project đang mở; chọn constraint cho project hiện tại."),
    ("add_to_vivado.tcl; select_bram_test.tcl", "Tìm đúng firmware.hex trong project hiện tại."),
    ("restore_picorv32.tcl; fix_mmcm_125MHz.tcl", "Khôi phục/chỉnh sửa file trong đúng project được xác định."),
    ("show_project_100MHz_results.tcl", "Bỏ đường dẫn 50MHz cố định; vẫn là công cụ xem run 100MHz cũ, không dùng để build hệ thống 125MHz mới."),
])
p("Đã bỏ lệnh gỡ IP PS7 trong select_timing_constraints_125MHz.tcl. PS7 là thành phần cần thiết cho hệ thống USB/HDMI. Không thay đổi cấu hình chân board hoặc cấu hình PS7 trong đợt sửa này.")
doc.add_heading("7. Kết quả kiểm tra", 1)
table(["Kiểm tra", "Kết quả / phạm vi"], [
    ("WSTRB + watchdog, qua CDC AMD thực", "PASS: byte-write, ghi rỗng, START, chặn reset từ bên không sở hữu, timeout các kênh AW/W/B/AR/R, reset rồi truy cập lại."),
    ("CNN/DMA treo", "PASS: endpoint không phản hồi làm phát watchdog BUSY; phục hồi chủ động cũng hoạt động."),
    ("Nhánh DMA của bộ nhớ", "PASS: reset xóa phản hồi cũ, giữ phản hồi CPU và dữ liệu RAM, phân xử đồng thời CPU/DMA không treo."),
    ("Suy luận sau thay đổi RTL", "PASS: ảnh có người/không có người, kiểm tra mọi pixel đầu vào, khóa và backpressure."),
    ("Firmware PicoRV32", "Build thành công; code/data/BSS kết thúc 0xBC8, còn 552 byte trước vùng stack dự phòng. Mô phỏng boot và lệnh UART r: PASS."),
    ("Driver ARM", "Biên dịch object Cortex-A9 bằng Clang, -Wall -Wextra -Werror: PASS. Chưa liên kết thành ứng dụng ARM hoàn chỉnh."),
    ("Đường dẫn/deploy", "Unit test project thiếu/trùng/đổi tên và bảo vệ model tốt hơn: PASS. Tcl resolver và kiểm tra cấu trúc script: PASS."),
    ("Synthesis Vivado", "PASS cho soc_top với ENABLE_USB_HDMI=0 trong project tạm; kiểm tra RTL CNN/bridge/memory có thể tổng hợp. Không thay thế synthesis toàn hệ thống PS7/HDMI hoặc timing sau route."),
])

doc.add_page_break()
doc.add_heading("8. Áp dụng lên board", 1)
for text in [
    "Mở project SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr; giữ top soc_top và ENABLE_USB_HDMI=1 cho bản có PS7/HDMI.",
    "Firmware Pico mới đã nằm trong firmware/firmware.hex và bản trong sources_1/new. Nếu chỉnh tiếp main.c, build lại bằng python firmware/build.py.",
    "Chạy lại synthesis, implementation và Generate Bitstream. Nạp bitstream mới; bitstream cũ không có watchdog hoặc thanh ghi phục hồi.",
    "Export XSA mới và build lại ứng dụng ARM với firmware_arm/cnn_bridge.c/.h. Khởi tạo PS7/FCLK trước khi truy cập cầu nối CNN.",
    "Thử suy luận bình thường; sau đó kiểm tra phục hồi có kiểm soát và xác nhận frame sau phục hồi chạy được. Tiếp tục kiểm tra timing và USB/HDMI trên board.",
]:
    doc.add_paragraph(text, style="List Number")
doc.add_heading("9. Giới hạn cần hiểu", 1)
p("Watchdog chạy bằng clock core. Nó không phục hồi được mất clock, PS7 ngừng hoạt động, hoặc bus/CDC bị treo trước cầu nối. Nếu bên khởi tạo chỉ gửi AW mà không bao giờ gửi W, cầu nối vẫn phải chờ phần còn lại; không hủy tùy tiện nửa giao dịch.")
p("SLVERR có thể gây Data Abort trên Cortex-A9. Driver C không tự bắt ngoại lệ CPU; ứng dụng ARM cần handler phù hợp khi thử lỗi bus. Không xem việc hết polling timeout là cách bắt lỗi MMIO bị ngoại lệ.")
p("Cơ chế reset DMA chỉ áp dụng bộ nhớ cục bộ hiện tại. Nếu sau này nối DMA sang DDR thật, cần thiết kế xử lý giao dịch còn tồn và phản hồi trễ cho endpoint đó. Không chỉ nối reset này vào một master đang có giao dịch DDR chưa hoàn tất.")
p("Các ngưỡng watchdog phải được điều chỉnh nếu đổi clock hoặc nâng model. Ngưỡng BUS tính toàn bộ thời gian giao dịch chuyển tiếp; không áp dụng cho thời gian CPU giữ BREADY/RREADY ở mức thấp sau khi đã có phản hồi.")
doc.add_heading("10. Chạy lại các kiểm tra", 1)
for command in [
    "python fpga_usb_hdmi/sim/run_bridge_test.py --recovery",
    "python fpga_usb_hdmi/sim/run_bridge_test.py --memory-recovery",
    "python fpga_usb_hdmi/sim/run_bridge_test.py",
    "python fpga_usb_hdmi/sim/run_bridge_test.py --firmware-boot",
    "python -m unittest discover -s CNN_RTL -p test_project_paths.py",
    "python -m unittest discover -s CNN_RTL -p test_coco_deployment.py",
]:
    para=doc.add_paragraph()
    run=para.add_run(command);run.font.name="Consolas";run.font.size=Pt(9)
p("Log mô phỏng và synthesis nằm trong fpga_usb_hdmi/build_check/. Tài liệu kỹ thuật duy trì tại fpga_usb_hdmi/ARM_CNN_BRIDGE.md và firmware_arm/README.md. Không commit/push Git trong đợt sửa này.")

timing_dir = ROOT / "fpga_usb_hdmi/build_check/timing_recovery"
if (timing_dir / "soc_top_timing_fixed.bit").exists():
    doc.add_page_break()
    doc.add_heading("11. Cập nhật xử lý fail timing – 05/11/2026", 1)
    p("Sau phần kiểm tra RTL ban đầu, đã phân tích run implementation đầy đủ impl_soc_usb_hdmi. Báo cáo route lúc 11:22:38 có 5 điểm setup âm. Đường xấu nhất đi từ u_cpu/mem_addr_reg[21] qua nhánh phản hồi peripheral về u_cpu/decoded_rs1_reg[0]/R; 79,6% độ trễ dữ liệu đến từ routing.")
    table(["Chỉ số", "Trước tối ưu", "Sau tối ưu"], [
        ("WNS", "−0,079 ns", "+0,001 ns"),
        ("TNS", "−0,396 ns", "0 ns"),
        ("Điểm setup lỗi", "5", "0"),
        ("WHS", "+0,017 ns", "+0,017 ns"),
        ("Điểm hold lỗi", "0", "0"),
        ("Lỗi routing", "0", "0"),
    ])
    p("Đã chạy phys_opt_design -directive AggressiveExplore trên bản sao checkpoint routed. Giữ clock core 125 MHz và các constraint hiện có. Bước tối ưu sau route cũng được thêm vào script tích hợp để áp dụng cho build sau.")
    p("Bitstream mới: fpga_usb_hdmi/build_check/timing_recovery/soc_top_timing_fixed.bit. Checkpoint: soc_top_postroute.dcp trong cùng thư mục. Báo cáo timing, bus skew, route và DRC cũng nằm tại đây. Đây là cập nhật mới hơn trạng thái ‘chưa tạo bitstream’ ở các mục kiểm tra ban đầu.")
    p("Trong Vivado đang mở, source D:/LAB/custom_SOC-main/fpga_usb_hdmi/configure_timing_125MHz.tcl để cấu hình bước tối ưu cho các lần build sau. Script fix_timing_125MHz.tcl có thể tái tạo tối ưu và bitstream riêng từ checkpoint routed hiện tại.")
    p("Biên setup chỉ còn 0,001 ns. Kết quả này áp dụng checkpoint hiện tại; mỗi lần tổng hợp/route mới phải kiểm tra lại. Run cũ có thể vẫn hiển thị đỏ vì giữ báo cáo lịch sử; mở checkpoint đã sửa để xem kết quả mới. Chưa nạp thử trên board.")

OUT.parent.mkdir(exist_ok=True)
doc.core_properties.title = "Báo cáo sửa lỗi CNN AXI và đường dẫn project"
doc.core_properties.subject = "Watchdog, phục hồi, WSTRB, script build và kiểm chứng"
doc.core_properties.author = "SoC HUFLIT"
try:
    doc.save(OUT)
except PermissionError:
    # Word may have the earlier report open; preserve that document/session.
    OUT = OUT.with_name(OUT.stem + "_CAP_NHAT_TIMING.docx")
    doc.save(OUT)
with ZipFile(OUT) as archive:
    assert archive.testzip() is None
reopened = Document(OUT)
assert len(reopened.tables) >= 6
assert any("0x40004F08" in c.text for t in reopened.tables for r in t.rows for c in r.cells)
print(OUT)
print(f"DOCX_VALIDATED: {len(reopened.paragraphs)} paragraphs, {len(reopened.tables)} tables")
