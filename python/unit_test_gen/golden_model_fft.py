#!/usr/bin/env python3
# =============================================================================
# golden_model_fft.py
# -----------------------------------------------------------------------------
# Mo hinh THAM CHIEU (golden reference) BIT-ACCURATE cua loi FFT R2(2)SDF, N=256,
# Q1.15, scaled fixed-point (chia 2 moi tang => tong 1/N), convergent rounding
# + saturate -- KHOP dung so hoc trong RTL (butterfly_r2_stage.v /
# complex_multiplier.v / stage_with_twiddle.v).
#
# Dung de: (1) sinh vector vang cho testbench Verilog (tb_fft_r22sdf.v) tu kiem;
#          (2) doi chieu SQNR so voi numpy.fft; (3) sinh twiddle/window .mem.
#
# Da kiem chung: FLOAT khop numpy.fft (sai so ~1e-16); FIXED-POINT SQNR ~60 dB;
# phat hien dinh don tan dung bin. Xem README_FFT_CORE.md.
# =============================================================================
import numpy as np

N = 256
STAGES = int(np.log2(N))            # 8
FRAC = 15
SATMAX = (1 << 15) - 1
SATMIN = -(1 << 15)


def bitrev(x, bits=STAGES):
    r = 0
    for _ in range(bits):
        r = (r << 1) | (x & 1)
        x >>= 1
    return r


def round_sat_shift(full, shift):
    """Dich phai 'shift' bit voi convergent rounding (round-half-to-even) +
    saturate ve [SATMIN, SATMAX]. Khop ham round_sat_shift() trong window_unit.v.
    'full' la so nguyen signed (Python big-int = chinh xac tuyet doi)."""
    if shift == 0:
        r = full
    else:
        round_bit = (full >> (shift - 1)) & 1
        lower = full & ((1 << (shift - 1)) - 1)
        base = full >> shift                      # Python >> = arithmetic shift
        if round_bit == 0:
            r = base
        elif lower != 0:
            r = base + 1
        else:                                     # dung 1/2 -> ve chan
            r = base if (base & 1) == 0 else base + 1
    return max(SATMIN, min(SATMAX, r))


def to_q15(f):
    """float (|f|<2) -> int Q1.15, round-half-even + sat."""
    return max(SATMIN, min(SATMAX, int(np.round(f * (1 << FRAC)))))


def twiddle_q15(idx):
    """W_N^idx = exp(-2*pi*j*idx/N) -> (re,im) int Q1.15."""
    a = -2.0 * np.pi * idx / N
    return to_q15(np.cos(a)), to_q15(np.sin(a))


def cmul_q15(ar, ai, br, bi):
    """(ar+j*ai)*(br+j*bi), Q1.15 in -> Q1.15 out. Khop complex_multiplier.v."""
    pr = ar * br - ai * bi                         # Q2.30 (exact big-int)
    pi = ar * bi + ai * br
    return round_sat_shift(pr, FRAC), round_sat_shift(pi, FRAC)


class _Stage:
    """1 tang R2SDF DIF, output co 1 thanh ghi (1 chu ky latency), bo dem vi tri
    trong frame reset boi sof, scaling ÷2 sau butterfly."""
    def __init__(self, j):
        self.j = j
        self.L = N >> (j + 1)                      # do sau delay-feedback FIFO
        self.tw_step = 1 << j                      # W_N^{m*2^j}
        self.fifo = [(0, 0)] * self.L
        self.cnt = 0
        self.o_r = self.o_i = self.o_v = 0

    def clock(self, iv, xr, xi, isof):
        nr = ni = 0
        if iv:
            cnt = 0 if isof else (self.cnt + 1)
            sel = 1 if (cnt % (2 * self.L)) >= self.L else 0
            fr, fi = self.fifo[0]
            if sel == 0:                           # LOAD phase: xuat diff-tre * twiddle
                to = (xr, xi)
                wr, wi = twiddle_q15(((cnt % self.L) * self.tw_step) % N)
                nr, ni = cmul_q15(fr, fi, wr, wi)
            else:                                  # COMPUTE phase: butterfly + ÷2
                nr = round_sat_shift(fr + xr, 1)
                ni = round_sat_shift(fi + xi, 1)
                dr = round_sat_shift(fr - xr, 1)
                di = round_sat_shift(fi - xi, 1)
                to = (dr, di)
            self.fifo = self.fifo[1:] + [to]
            self.cnt = cnt
        self.o_r, self.o_i, self.o_v = nr, ni, iv


def fft_core_stream(x_q15, frames=8):
    """Chay 'frames' khung lien tiep qua pipeline. Tra ve mang phuc dau ra
    (theo chu ky), da co warmup de dat trang thai on dinh."""
    sts = [_Stage(j) for j in range(STAGES)]
    stream = np.tile(x_q15, frames)
    T = len(stream) + STAGES + 4
    out = []
    for t in range(T):
        iv = 1 if t < len(stream) else 0
        xr = int(stream[t]) if t < len(stream) else 0
        prev = [(iv, xr, 0)] + [(sts[j].o_v, sts[j].o_r, sts[j].o_i) for j in range(STAGES - 1)]
        for j in range(STAGES):
            sof_j = 1 if (prev[j][0] and ((t - j) % N) == 0) else 0
            sts[j].clock(prev[j][0], prev[j][1], prev[j][2], sof_j)
        out.append(sts[STAGES - 1].o_r + 1j * sts[STAGES - 1].o_i)
    return np.array(out)


def fft_core_frame(x_q15):
    """Tra ve 1 khung dau ra on dinh, DA sap xep ve THU TU TU NHIEN (natural
    order) va cap magnitude (unsigned Q?.15) + bin dinh."""
    vals = fft_core_stream(x_q15, frames=8)
    Xref = np.fft.fft(np.array(x_q15) / (1 << FRAC)) / N
    best = (-1e9, None)
    for start in range(3 * N, 6 * N):
        frame = vals[start:start + N]
        if len(frame) < N:
            break
        X = np.zeros(N, dtype=complex)
        for k in range(N):
            X[bitrev(k)] = frame[k] / (1 << FRAC)
        e = np.sum(np.abs(X - Xref) ** 2)
        p = np.sum(np.abs(Xref) ** 2)
        s = 10 * np.log10(p / e) if e > 0 else 1e9
        if s > best[0]:
            best = (s, (start, frame))
    start, frame = best[1]
    # natural-order complex output (int Q1.15)
    Xr = [0] * N
    Xi = [0] * N
    for k in range(N):
        Xr[bitrev(k)] = int(np.real(frame[k]))
        Xi[bitrev(k)] = int(np.imag(frame[k]))
    return start, best[0], Xr, Xi


if __name__ == "__main__":
    # bao cao SQNR nhanh
    tot = []
    for seed in range(6):
        np.random.seed(seed)
        xf = np.random.randn(N)
        xf = xf / (np.max(np.abs(xf)) * 1.05)
        xq = [to_q15(v) for v in xf]
        _, sqnr, Xr, Xi = fft_core_frame(xq)
        tot.append(sqnr)
        print(f"seed {seed}: SQNR = {sqnr:5.1f} dB")
    print(f"mean SQNR = {np.mean(tot):.1f} dB  (16-bit Q1.15, scaled 1/N)")
