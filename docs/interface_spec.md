# Interface Specification — FFT Audio Spectrum Analyzer IP

IP top-level: **`fft_analyzer_ip`**. Reset `rst_n` active-low, single clock `clk`.
Fixed-point **Q1.15** signed for complex data, **UNSIGNED 16-bit** for magnitude.

## 1. Parameters
| Parameter | Default | Meaning |
|---|---|---|
| `N` | 256 | FFT size (samples/frame) |
| `DATA_WIDTH` | 16 | Sample/bin width (Q1.15) |
| `FFT_LATENCY` | 283 | Core latency in **valid-samples** (measure via `tb_fft_r22sdf`) |
| `ENABLE_LOG` | 1 | Compute `out_mag_log2` (Q8.8) in `magnitude_unit` |
| `WINDOW_FILE` | `window_coeff.mem` | Hann window ROM |
| `TW_RE_FILE`/`TW_IM_FILE` | `twiddle_re/im.mem` | Twiddle ROMs (N/2 each) |

## 2. AXI4-Stream slave — audio input
| Port | Dir | Width | Description |
|---|---|---|---|
| `s_axis_tvalid` | in | 1 | Beat valid |
| `s_axis_tdata` | in | `DATA_WIDTH` | Audio sample, **Q1.15 signed** |
| `s_axis_tready` | out | 1 | Ready (may deassert; skid buffer, no data loss) |

Samples are grouped into frames of `N` by `input_buffer_fsm` (ping-pong).

## 3. AXI4-Stream master — spectrum output
| Port | Dir | Width | Description |
|---|---|---|---|
| `m_axis_tvalid` | out | 1 | Beat valid |
| `m_axis_tdata` | out | `DATA_WIDTH` | Magnitude \|X[k]\|, **UNSIGNED** |
| `m_axis_tlast` | out | 1 | End of spectrum frame (bin N/2−1) |
| `m_axis_tuser[0]` | out | 1 | Start of frame (bin 0) |
| `m_axis_tready` | in | 1 | Backpressure |

Spectrum is **single-sided, natural order**: `N/2 = 128` bins, `k = 0..N/2−1`.
**Bin → frequency:** `f_k = k · fs / N` (fs = 48 kHz → 187.5 Hz/bin).

> The core spectrum stream is self-timed (free-running). Keep `m_axis_tready`
> high, or insert a FIFO before `axi_stream_master_if` if it can stall.

## 4. Peak + status
| Port | Dir | Width | Description |
|---|---|---|---|
| `peak_valid` | out | 1 | 1 pulse per frame |
| `peak_magnitude` | out | `DATA_WIDTH` | Max magnitude in frame |
| `peak_bin_idx` | out | `clog2(N/2)`=7 | Natural bin of peak; `f = peak_bin_idx·fs/N` |
| `start` | in | 1 | High = run |
| `busy` | out | 1 | Processing |
| `core_en` | out | 1 | Enable (clean start/stop at frame boundary) |
| `frame_count` | out | 32 | Completed frames |

## 5. Framing contract
- Every framed stream carries `sof` (first element) and `last` (final element);
  downstream self-counts the position — no explicit address bus.
- The FFT core produces output in **bit-reversed** order internally; `bin_ram_output`
  reorders to natural single-sided before `magnitude`-based peak detection.
- Datapath is **valid-gated**: `valid=0` bubbles (e.g. 1-cycle inter-frame gap from
  `input_buffer_fsm`) are tolerated; latency counts valid-samples.

## 6. Numeric formats
| Quantity | Format |
|---|---|
| Audio / X[k] re,im | Q1.15 signed |
| Twiddle W_N^k | Q1.15 signed (2.14 effective, \|W\|≤1) |
| Magnitude | UNSIGNED 16-bit (α-max-β-min, α=31471, β=13036) |
| `out_mag_log2` | Q8.8 signed (approx log2) |

Rounding everywhere: **convergent (round-half-to-even)** + saturation.
