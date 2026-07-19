#!/usr/bin/env python3
# =============================================================================
# gen_twiddle_rom.py
# -----------------------------------------------------------------------------
# Sinh N/2 he so twiddle W_N^k = exp(-2*pi*j*k/N), k=0..N/2-1, Q1.15 16-bit
# signed, xuat 2 FILE RIENG: twiddle_re.mem va twiddle_im.mem (moi dong 4 hex
# digit, 16-bit), nap vao twiddle_rom.v (doc dong bo) bang $readmemh.
# Khop ham twiddle_q15() trong golden_model_fft.py.
#
#   python3 gen_twiddle_rom.py --n 256 --out ./rom_out
# =============================================================================
import argparse, os
import numpy as np

FRAC = 15
QMAX = (1 << 15) - 1
QMIN = -(1 << 15)


def to_q15(x):
    return max(QMIN, min(QMAX, int(np.round(float(x) * (1 << FRAC)))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=256)
    ap.add_argument("--out", type=str, default="./rom_out")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    N = args.n
    re_path = os.path.join(args.out, "twiddle_re.mem")
    im_path = os.path.join(args.out, "twiddle_im.mem")
    with open(re_path, "w") as fre, open(im_path, "w") as fim:
        for k in range(N // 2):
            ang = -2.0 * np.pi * k / N
            fre.write(f"{to_q15(np.cos(ang)) & 0xFFFF:04x}\n")
            fim.write(f"{to_q15(np.sin(ang)) & 0xFFFF:04x}\n")
    print(f"[gen_twiddle_rom] N={N}, {N//2} he so -> {re_path}, {im_path}")
    print(f"[gen_twiddle_rom] W^0   = {to_q15(1):6d} + j{to_q15(0):d}   (1 + 0j)")
    print(f"[gen_twiddle_rom] W^N/4 = {to_q15(0):6d} + j{to_q15(-1):d}   (0 - 1j)")


if __name__ == "__main__":
    main()
