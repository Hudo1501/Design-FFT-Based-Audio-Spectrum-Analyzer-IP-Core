"""
gen_butterfly_vectors.py

Sinh vector kiem chung RIENG cho butterfly_r2_stage.v (khong co twiddle -
twiddle la viec cua twiddle_rom.v + complex_multiplier.v o TANG SAU, xem
stage_with_twiddle.v). Mo hinh Python o day la ban "thuan butterfly" duoc
suy ra truc tiep tu class _Stage trong golden_model_fft.py, CHI BO buoc
nhan twiddle (cmul_q15) trong nhanh LOAD - giu nguyen moi thu khac (FIFO
delay-commutator, sel/cnt, scaling ÷2 round-half-even) HET SUC GIONG RTL.

Tham so mac dinh: N=256, J=0 (DELAY_LEN=128) - dung dung cau hinh tang 0
that su dang dung trong fft_r22sdf_top.v.

Chay: python gen_butterfly_vectors.py
"""

import numpy as np
import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from golden_model_fft import round_sat_shift  # ham lam tron/bao hoa CHINH THUC cua project

N = 256
J = 0
L = N >> (J + 1)      # DELAY_LEN = 128
FRAMES = 4
TOTAL = N * FRAMES     # 1024 chu ky test


def to_hex16(x):
    return format(x & 0xFFFF, "04x")


def main():
    rng = np.random.default_rng(7)
    in_re = rng.integers(-32768, 32767, size=TOTAL)
    in_im = rng.integers(-32768, 32767, size=TOTAL)

    fifo = [(0, 0)] * L
    cnt = -1
    exp_re, exp_im, exp_sel, exp_cnt = [], [], [], []

    for t in range(TOTAL):
        isof = 1 if (t % N == 0) else 0
        xr, xi = int(in_re[t]), int(in_im[t])
        c = 0 if isof else (cnt + 1)
        sel = 1 if (c % (2 * L)) >= L else 0
        fr, fi = fifo[0]
        if sel == 0:                       # LOAD: xuat gia tri cu trong delay line, KHONG nhan twiddle
            to = (xr, xi)
            nr, ni = fr, fi
        else:                              # COMPUTE: butterfly + scale /2 (round-half-even)
            nr = round_sat_shift(fr + xr, 1)
            ni = round_sat_shift(fi + xi, 1)
            dr = round_sat_shift(fr - xr, 1)
            di = round_sat_shift(fi - xi, 1)
            to = (dr, di)
        fifo = fifo[1:] + [to]
        cnt = c
        exp_re.append(nr)
        exp_im.append(ni)
        exp_sel.append(sel)
        exp_cnt.append(c % L)

    os.makedirs("sim", exist_ok=True)
    with open("sim/bf_in_re.mem", "w") as f:
        for v in in_re:
            f.write(to_hex16(int(v)) + "\n")
    with open("sim/bf_in_im.mem", "w") as f:
        for v in in_im:
            f.write(to_hex16(int(v)) + "\n")
    with open("sim/bf_exp_re.mem", "w") as f:
        for v in exp_re:
            f.write(to_hex16(v) + "\n")
    with open("sim/bf_exp_im.mem", "w") as f:
        for v in exp_im:
            f.write(to_hex16(v) + "\n")
    with open("sim/bf_exp_sel.mem", "w") as f:
        for v in exp_sel:
            f.write(format(v, "01x") + "\n")
    with open("sim/bf_exp_cnt.mem", "w") as f:
        for v in exp_cnt:
            f.write(format(v & 0xFF, "02x") + "\n")

    print(f"Da sinh {TOTAL} chu ky vector cho butterfly_r2_stage (N={N}, J={J}, DELAY_LEN={L})")
    print(f"File: sim/bf_in_re.mem, bf_in_im.mem, bf_exp_re.mem, bf_exp_im.mem, bf_exp_sel.mem, bf_exp_cnt.mem")


if __name__ == "__main__":
    main()
