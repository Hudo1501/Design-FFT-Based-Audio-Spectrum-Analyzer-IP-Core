# FFT-Based Audio Spectrum Analyzer IP Core

IP core phân tích phổ tín hiệu âm thanh thời gian thực trên FPGA, dựa trên **FFT 256 điểm
kiến trúc R2SDF (Radix-2 Single-path Delay Feedback)**, số học điểm cố định **Q1.15**,
giao tiếp **AXI4-Stream** ở cả hai đầu. Đồ án môn **COS201 — Communication Systems**.

Board triển khai: **Digilent PYNQ-Z2** (Zynq XC7Z020CLG400-1). Đã tổng hợp, implement,
**đạt timing** và tạo bitstream (`bitstream/pynq_z2_top.bit`).

---

## 1. Tổng quan chuỗi xử lý

![Flow diagram](docs/images/flow_diagram.png)

Chuỗi xử lý: `input_buffer_fsm` (đệm khung N=256, giao thức AXI4-Stream) → `window_unit`
(cửa sổ Hann) → `fft_r22sdf_top` (FFT-256 R2SDF, output bit-reversed) → `magnitude_unit`
(biên độ phổ) → `bin_ram_output` (sắp xếp lại tự nhiên, N/2=128 bin) → rẽ song song ra
**phổ đầy đủ** (`Spectrum output`) và **đỉnh phổ** qua `peak_detector` (`Peak fsm output`).

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

## 4. Kết quả kiểm chứng: RTL so với Python (golden model)

Kiểm chứng theo mô hình **bottom-up, độc lập từng khối**: mỗi module RTL được đối chiếu
bit-exact với một golden model viết bằng Python (`golden_model_fft.py`, mô phỏng
cycle-accurate), trước khi kiểm ở cấp lõi FFT và cấp toàn hệ thống.

**Kết quả đạt được:**

| Cấp kiểm chứng | Kết quả |
|---|---|
| `twiddle_rom` (128 địa chỉ + 2 điểm neo) | **PASS**, bit-exact |
| `butterfly_r2_stage` (1024 chu kỳ, 4 khung) | **PASS**, bit-exact, `sel_o`/`cnt_o` đúng chu kỳ |
| `magnitude_unit` (2013 cặp: 13 biên + 2000 ngẫu nhiên) | **PASS**, bit-exact magnitude lẫn log2 xấp xỉ |
| `bin_ram_output` (1164 chu kỳ, 4 khung) | **PASS**, bit-exact, bitrev 128/128 đúng |
| `fft_r22sdf_top` (lõi FFT đầy đủ) | **PASS**, **SQNR = 204.6 dB**, bin đỉnh = 10 |
| Toàn hệ thống (`tb_top`, 8 khung liên tục) | **PASS**, `peak_bin` = **10** mọi khung |

**Kết luận:**
- RTL khớp **bit-exact** với golden model Python ở toàn bộ 4 module con.
- Ở cấp lõi FFT và cấp hệ thống, sai số điểm cố định (Q1.15 + scaling ÷2/tầng) cho
  **SQNR ~58–61.6 dB** qua nhiều seed ngẫu nhiên khác nhau, không tràn — và bin đỉnh phổ
  luôn xác định đúng (bin 10, khớp tần số đưa vào).
- Bộ nhân phức Karatsuba 3-mult **bit-exact** so với nhân phức trực tiếp (0 sai khác
  trên 200,000 mẫu thử).
- Mô hình Python (dấu chấm động) khớp `numpy.fft` chuẩn với sai số ~1e-16.

## 5. Kết quả PPA (Vivado 2020.2+, PYNQ-Z2, sau Place & Route)

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

## 6. Board bring-up (PYNQ-Z2)

1. Nạp `bitstream/pynq_z2_top.bit`, nhấn **BTN0** để reset.
2. **SW0 = 0** (nguồn = tone nội bộ `tone_player`) → `led[3:0]` phải là **`1010`**
   (bin đỉnh = 10 = `0001010`).
3. RGB LED xanh lá = busy, RGB LED đỏ nhấp nháy mỗi khung hoàn tất.
4. Nếu bin ≠ 10: khả năng cao `FFT_LATENCY` trong `pynq_z2_top.v` sai — chạy lại
   `tb_fft_r22sdf` để đọc LATENCY thực đo rồi sửa tham số cho khớp.

> PYNQ-Z2 không có mic PDM onboard nên bản wrapper hiện tại chỉ dùng nguồn tự-kiểm-tra
> nội bộ (`tone_player`), đã xác nhận chạy đúng trên silicon thật (bin đỉnh = 10).

## 7. Cấu trúc repo

```
rtl/
  core/           # Lõi FFT: butterfly, twiddle ROM, complex multiplier, R2SDF top
  system/         # Tiền/hậu xử lý + tích hợp IP: window, magnitude, bin reorder,
                  # peak detector, control FSM, project_top, fft_analyzer_ip
  interfaces/     # axi_stream_slave_if / axi_stream_master_if
  board/          # Wrapper board PYNQ-Z2: pynq_z2_top, tone_player, sync_2ff
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
constraints/       # pynq_z2.xdc, timing_only.xdc
docs/
  images/           # flow_diagram.png, top_module_diagram.png
  reports/          # Báo cáo timing/utilization (Vivado, đã P&R)
  interface_spec.md # Đặc tả cổng giao tiếp IP đầy đủ
bitstream/
  pynq_z2_top.bit  # Bitstream đã build, sẵn sàng nạp board
```

## 8. Đặc tả giao diện (tóm tắt)

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

