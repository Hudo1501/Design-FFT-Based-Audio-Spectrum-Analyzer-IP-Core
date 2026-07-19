# FFT-Based Audio Spectrum Analyzer IP Core

IP core phân tích phổ tín hiệu âm thanh thời gian thực trên FPGA, dựa trên **FFT 256 điểm
kiến trúc R2SDF (Radix-2 Single-path Delay Feedback)**, số học điểm cố định **Q1.15**,
giao tiếp **AXI4-Stream** ở cả hai đầu. Đồ án môn **COS201 — Communication Systems**.

Board triển khai: **Digilent PYNQ-Z2** (Zynq XC7Z020CLG400-1). Đã tổng hợp, implement,
**đạt timing** và tạo bitstream (`bitstream/pynq_z2_top.bit`).

---

## 1. Tổng quan chuỗi xử lý

```
Audio (AXI4-Stream, Q1.15)
   │
   ▼
input_buffer_fsm  ──► window_unit (Hann) ──► fft_r22sdf_top ──► magnitude_unit ──► bin_ram_output ──► peak_detector
  ping-pong N=256      window_rom              8 tầng R2SDF        α-max-β-min      bit-reversed          |X[k]|max
                                                Q1.15, DIF                          → tự nhiên             + peak_bin_idx
                                                                                      N/2 = 128 bin
```

![Flow diagram](docs/images/flow_diagram.png)

- **Bin → tần số:** `f_k = k · fs / N`, với `fs = 48 kHz` → **187.5 Hz/bin**, phổ đơn biên
  128 bin (do tín hiệu audio thực).
- Output theo giao thức `sof`/`valid`/`last` tự đánh dấu vị trí trong khung — không dùng
  bus địa chỉ tường minh.

## 2. Sơ đồ khối top module

`pynq_z2_top.v` là top module thật sự nạp lên board. Bên trong bọc IP core
`fft_analyzer_ip.v`/`project_top.v`, cộng thêm hạ tầng board-specific (Clocking Wizard,
CDC, nguồn self-test nội bộ vì PYNQ-Z2 không có mic PDM onboard).

![Top module diagram](docs/images/top_module_diagram.png)

- **`tone_player`**: phát lại `tv_input.mem` (chính là test-vector vàng dùng khi mô phỏng,
  đỉnh phổ tại **bin 10**) làm nguồn kiểm tra nội bộ — xác nhận cả chuỗi chạy đúng trên
  silicon thật trước khi cần tới nguồn âm thanh thực.
- **Clocking Wizard**: hạ tần từ 125 MHz (osc. board) xuống ~50 MHz cho miền clock chính
  của thiết kế (xem mục Hiệu năng).

## 3. Kiến trúc & kỹ thuật sử dụng

| Khối | Vai trò | Kỹ thuật/thuật toán |
|---|---|---|
| `butterfly_r2_stage` | Bướm cộng/trừ + delay-commutator | Delay line nội bộ `DELAY_LEN = N>>(J+1)` (128…1), scaling ÷2/tầng, **convergent rounding** (round-half-to-even) + bão hòa |
| `twiddle_rom` | Hệ số xoay $W_N^k$ | ROM đồng bộ N/2 hệ số, đọc 1 chu kỳ |
| `complex_multiplier` | Nhân số phức | **Karatsuba 3 phép nhân** (thay vì 4), pipeline 3 tầng → 4 chu kỳ latency |
| `stage_with_twiddle` | Ghép 1 tầng FFT | Nhánh twiddle 4 chu kỳ song song nhánh bypass 4 chu kỳ (delay-matched), MUX theo `sel_o` trễ đúng nhịp |
| `fft_r22sdf_top` | Ghép 8 tầng | FFT-256 DIF, throughput 1 mẫu/chu kỳ, output **bit-reversed** |
| `window_unit` + `window_rom` | Cửa sổ hoá tín hiệu | Hann window trước khi vào FFT (giảm rò rỉ phổ) |
| `magnitude_unit` | Biên độ phổ | Xấp xỉ **α-max-β-min** (α=31471, β=13036) — thay cho `sqrt(re²+im²)` tốn tài nguyên |
| `bin_ram_output` | Sắp xếp lại | bit-reversed → thứ tự tự nhiên, gộp phổ đối xứng còn N/2=128 bin đơn biên |
| `peak_detector` | Tìm đỉnh phổ | So sánh liên tục trong 1 khung, xuất `peak_magnitude` + `peak_bin_idx` |
| `input_buffer_fsm` | Đệm khung | Ping-pong buffer N=256, chèn 1 chu kỳ bubble giữa các khung |
| `axi_stream_slave_if` / `axi_stream_master_if` | Biên giao tiếp IP | Skid buffer, tuân thủ backpressure `tready`/`tvalid` |
| `fft_control_fsm` | Điều khiển | `start`/`busy`/`core_en`/`frame_count` |

### Điểm thiết kế then chốt
- **Valid-gating toàn tuyến (`en`)**: mọi khối (ROM, nhân phức, delay-line framing) đều
  nhận chân enable = valid, nên **chịu được bubble** giữa các khung mà không lệch latency.
- **Scaling ÷2 mỗi tầng** (tổng 1/N sau 8 tầng): bắt buộc để tránh tràn Q1.15 — không có
  bước này SQNR chỉ ~1.5 dB (nhiễu tràn), có scaling → **SQNR ~60 dB**.
- **Q1.15 signed** cho dữ liệu phức, **unsigned 16-bit** cho magnitude, **Q8.8** cho
  `log2` xấp xỉ (tuỳ chọn `ENABLE_LOG`).

## 4. Bug quan trọng nhất đã tìm & sửa: `LATENCY = 283 → 291`

Tham số latency dùng để tạo `out_sof/out_valid/out_last` được tính lý thuyết ban đầu:

```
tổng DELAY_LEN 8 tầng (128+64+32+16+8+4+2+1)        = 255
+ overhead pipeline twiddle 7 tầng có nhân (7 × 4)   =  28
                                                      = 283
```

Con số này **thiếu 1 chu kỳ thanh ghi ngõ ra** của chính `butterfly_r2_stage`
(`out_re <= o_re_n`), nằm ngoài mảng delay-line nên không được cộng vào `DELAY_LEN`.
Cộng dồn qua 8 tầng → thiếu đúng 8 chu kỳ. **Giá trị đúng đã kiểm chứng bằng mô phỏng
thực tế: 291.**

| Testbench | LATENCY=283 (gốc) | LATENCY=291 (đã sửa) |
|---|---|---|
| `tb_fft_r22sdf.v` (offset mặc định ±6) | SQNR = −3.0 dB, bin đỉnh = 122 (sai) → **FAIL** | SQNR = **204.6 dB**, bin đỉnh = 10 → **PASS** |
| `tb_top.sv` (hệ thống, 8 khung liên tục) | `peak_bin` = 26 mọi khung (sai) → **FAIL** | `peak_bin` = **10** mọi khung → **PASS** |

Điểm quan trọng: **toàn bộ thuật toán (Karatsuba, twiddle, butterfly delay-commutator,
bit-reversal, scaling) đều đúng ngay từ đầu** — bug chỉ nằm ở việc gắn nhãn thời điểm
(framing), khiến hệ thống đọc sai vị trí bin dù dữ liệu tính toán nội bộ vẫn chính xác.
Chi tiết đầy đủ xem `docs/README_PATCH.md` (nếu có trong lịch sử) hoặc phần kiểm chứng bên dưới.

## 5. Phương pháp kiểm chứng (Verilog ↔ Python)

Kiểm chứng theo mô hình **bottom-up, độc lập từng khối**, dùng Python làm golden model
rồi đối chiếu bit-exact với RTL:

```
golden_model_fft.py (Python, bit-accurate mô phỏng cycle-accurate)
        │
        ├─ gen_twiddle_expected.py  → tw_exp_re/im.mem     ─┐
        ├─ gen_butterfly_vectors.py → bf_exp_*.mem          │  đối chiếu
        ├─ gen_magnitude_vectors.py → mag_exp_*.mem         │  bit-exact
        ├─ gen_bin_ram_vectors.py   → br_exp_*.mem          │  với RTL
        └─ gen_vectors.py           → tv_exp_*.mem (FFT-256)─┘
                                              │
                        iverilog/Vivado xsim (tb_*.v, tb_top.sv)
                                              │
                                    compare_sqnr.py (SQNR, PASS/FAIL)
```

| Testbench | Số vector kiểm | Kết quả |
|---|---|---|
| `tb_twiddle_rom` | 128 địa chỉ (toàn bộ N/2) + 2 điểm neo $W^0, W^{N/4}$ | PASS, bit-exact |
| `tb_butterfly_r2_stage` | 1024 chu kỳ (4 khung N=256) | PASS, bit-exact + `sel_o`/`cnt_o` đúng chu kỳ |
| `tb_magnitude_unit` | 2013 cặp (13 biên + 2000 ngẫu nhiên) | PASS, bit-exact magnitude lẫn log2 xấp xỉ |
| `tb_bin_ram_output` | 1164 chu kỳ (4 khung) | PASS, bit-exact + kiểm bitrev 128/128 |
| `tb_fft_r22sdf` (lõi FFT đầy đủ) | Tự dò offset, tự đo LATENCY | PASS, SQNR = 204.6 dB, bin đỉnh = 10 |
| `tb_top` (toàn hệ thống, SystemVerilog) | 8 khung liên tục | PASS, `peak_bin` = 10 mọi khung |

**7/7 bước trong quy trình bottom-up có bằng chứng kiểm chứng riêng lẻ**, độc lập với
Python golden model ở cấp hệ thống.

**Xấp xỉ dấu chấm động** (`golden_model_fft.py` so với `numpy.fft` chuẩn): sai số ~1e-16
(đúng cấu trúc). **Xấp xỉ điểm cố định** Q1.15 + scaling ÷2/tầng: **SQNR ~58–61.6 dB**
qua 8 seed ngẫu nhiên khác nhau, không tràn. Karatsuba 3-mult **bit-exact** so với nhân
phức trực tiếp (0 sai khác / 200000 mẫu thử).

### Cách chạy mô phỏng
```bash
# 1) Sinh ROM & vector vàng (chạy 1 lần)
python3 python/gen_twiddle_rom.py --n 256 --out sim/vectors
python3 python/gen_window_coeff.py
python3 python/gen_vectors.py
python3 python/unit_test_gen/gen_twiddle_expected.py
python3 python/unit_test_gen/gen_butterfly_vectors.py
python3 python/unit_test_gen/gen_magnitude_vectors.py
python3 python/unit_test_gen/gen_bin_ram_vectors.py

# 2) Kiểm lõi FFT (Icarus Verilog)
cd sim/vectors   # các file .mem cần cùng thư mục làm việc mô phỏng
iverilog -g2012 -o sim_core ../../tb/tb_fft_r22sdf.v \
   ../../rtl/core/fft_r22sdf_top.v ../../rtl/core/stage_with_twiddle.v \
   ../../rtl/core/butterfly_r2_stage.v ../../rtl/core/complex_multiplier.v \
   ../../rtl/core/twiddle_rom.v
vvp sim_core
python3 ../../python/compare_sqnr.py --self

# 3) Kiểm hệ thống (Vivado xsim — cần SystemVerilog cho tb_top.sv)
# Add toàn bộ rtl/**/*.v + tb/tb_top.sv vào Simulation Sources, Set as Top, run -all
```

## 6. Kết quả PPA (Vivado 2020.2+, PYNQ-Z2, sau Place & Route)

| Tài nguyên | Dùng | Có sẵn | Tỉ lệ |
|---|---|---|---|
| Slice LUTs | 4,432 | 53,200 | 8.33% |
| Slice Registers | 4,328 | 106,400 | 4.07% |
| Slices | 1,882 | 13,300 | 14.15% |
| Block RAM (tile) | 7.5 | 140 | 5.36% |
| DSP48E1 | 24 | 220 | 10.91% |

**Timing:** clock chính sau Clocking Wizard chạy **49.98 MHz**, WNS = **+2.510 ns** →
**đạt timing với biên độ dư**, Fmax lý thuyết ≈ **57 MHz**
(`docs/reports/pynq_z2_top_timing_summary_routed.rpt`,
`docs/reports/pynq_z2_top_utilization_placed.rpt`).

## 7. Board bring-up (PYNQ-Z2)

1. Nạp `bitstream/pynq_z2_top.bit`, nhấn **BTN0** để reset.
2. **SW0 = 0** (nguồn = tone nội bộ `tone_player`) → `led[3:0]` phải là **`1010`**
   (bin đỉnh = 10 = `0001010`).
3. RGB LED xanh lá = busy, RGB LED đỏ nhấp nháy mỗi khung hoàn tất.
4. Nếu bin ≠ 10: khả năng cao `FFT_LATENCY` trong `pynq_z2_top.v` sai — chạy lại
   `tb_fft_r22sdf` để đọc LATENCY thực đo rồi sửa tham số cho khớp.

> PYNQ-Z2 không có mic PDM onboard nên bản wrapper hiện tại chỉ dùng nguồn tự-kiểm-tra
> nội bộ. Có kèm sẵn wrapper `nexys_a7_top.v` (dùng mic PDM thật) cho board Nexys A7,
> nhưng thiếu module `pdm_pcm_frontend` nên **chưa build được** — xem mục Hạn chế.

## 8. Cấu trúc repo

```
rtl/
  core/           # Lõi FFT: butterfly, twiddle ROM, complex multiplier, R2SDF top
  system/         # Tiền/hậu xử lý + tích hợp IP: window, magnitude, bin reorder,
                  # peak detector, control FSM, project_top, fft_analyzer_ip
  interfaces/     # axi_stream_slave_if / axi_stream_master_if
  board/          # Wrapper board-specific: pynq_z2_top, nexys_a7_top, tone_player...
tb/
  tb_fft_r22sdf.v # Testbench lõi FFT (tự dò offset, tự đo latency)
  tb_top.sv       # Testbench hệ thống (SystemVerilog)
  unit_tests/     # Testbench riêng cho 4 module: twiddle_rom, butterfly, magnitude, bin_ram
python/
  gen_*.py, compare_sqnr.py   # Sinh ROM/vector vàng + đối chiếu SQNR
  unit_test_gen/               # golden_model_fft.py + sinh vector cho 4 unit test
sim/
  vectors/              # Vector vàng cấp hệ thống (.mem)
  unit_test_vectors/    # Vector vàng cấp từng module (.mem/.txt)
constraints/       # pynq_z2.xdc, nexys_a7.xdc, timing_only.xdc
docs/
  images/           # flow_diagram.png, top_module_diagram.png
  reports/          # Báo cáo timing/utilization (Vivado, đã P&R)
  interface_spec.md # Đặc tả cổng giao tiếp IP đầy đủ
bitstream/
  pynq_z2_top.bit  # Bitstream đã build, sẵn sàng nạp board
```

## 9. Đặc tả giao diện (tóm tắt)

Xem đầy đủ tại `docs/interface_spec.md`. Tóm tắt:

| Tham số | Giá trị mặc định | Ý nghĩa |
|---|---|---|
| `N` | 256 | Kích thước FFT (mẫu/khung) |
| `DATA_WIDTH` | 16 | Độ rộng mẫu/bin (Q1.15) |
| `FFT_LATENCY` | 291 | Latency lõi tính theo mẫu-valid |
| `ENABLE_LOG` | 1 | Xuất `out_mag_log2` (Q8.8, log2 xấp xỉ) |

AXI4-Stream slave (audio in) và master (spectrum out) đều có `tvalid/tready` backpressure
qua skid buffer. Output phổ đơn biên, thứ tự tự nhiên, `tuser[0]` = start-of-frame,
`tlast` = bin cuối (N/2−1).

## 10. Hạn chế đã biết

- Nhánh Nexys A7 (`nexys_a7_top.v`, dùng mic PDM thật) **thiếu module `pdm_pcm_frontend`**
  nên hiện chưa tổng hợp được — chỉ nhánh PYNQ-Z2 (tone nội bộ) đã build & nạp thành công.
- Mã chân `PACKAGE_PIN` trong các file `.xdc` lấy theo master XDC chuẩn của Digilent,
  **chưa được đối chiếu trên phần cứng thật** — kiểm tra lại trước khi generate bitstream
  cho board khác.
- `fs` thực tế phụ thuộc clock chia từ Clocking Wizard; nếu cần đúng 48.000 kHz tuyệt đối
  cần tinh chỉnh lại hệ số chia.

## 11. Bối cảnh môn học

Đồ án thực hiện trong khuôn khổ môn **COS201 — Communication Systems**, vận dụng các khái
niệm: biến đổi Fourier rời rạc/nhanh (DFT/FFT, Ch.2), lấy mẫu & lượng tử hoá tín hiệu số
(Ch.7), và các kỹ thuật xử lý tín hiệu số áp dụng cho phân tích phổ thời gian thực trên
phần cứng khả trình (FPGA).

---

*Repo được tổ chức lại và tài liệu hoá bởi thành viên nhóm với sự hỗ trợ của Claude
(Anthropic) — xem lịch sử debug chi tiết (bug latency, kiểm chứng bottom-up) trong quá
trình phát triển thực tế của nhóm.*
