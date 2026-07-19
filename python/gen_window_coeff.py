import argparse
import os

import numpy as np

DATA_WIDTH = 16
FRAC_BITS = 15
Q15_MAX = 2 ** (DATA_WIDTH - 1) - 1
Q15_MIN = -2 ** (DATA_WIDTH - 1)


def to_q15(x):
    scaled = np.asarray(x, dtype=np.float64) * (2 ** FRAC_BITS)
    q = np.round(scaled)
    q = np.clip(q, Q15_MIN, Q15_MAX)
    return q.astype(np.int16)


def export_mem_hex(filename, data, width=DATA_WIDTH):
    mask = (1 << width) - 1
    hex_digits = (width + 3) // 4
    with open(filename, "w") as f:
        for v in data:
            uv = int(v) & mask
            f.write(f"{uv:0{hex_digits}x}\n")


def hann_window(n):
    """w[k] = 0.5*(1-cos(2*pi*k/N)) -- dang 'periodic', khop voi FFT (dong
    bo voi ham hann_window() trong golden_model_fft.py)."""
    k = np.arange(n)
    return 0.5 * (1 - np.cos(2 * np.pi * k / n))


def hamming_window(n):
    k = np.arange(n)
    return 0.54 - 0.46 * np.cos(2 * np.pi * k / n)


def blackman_window(n):
    k = np.arange(n)
    return (0.42 - 0.5 * np.cos(2 * np.pi * k / n)
            + 0.08 * np.cos(4 * np.pi * k / n))


WINDOW_FUNCS = {
    "hann": hann_window,
    "hamming": hamming_window,
    "blackman": blackman_window,
}


def main():
    ap = argparse.ArgumentParser(description="Sinh he so cua so Q1.15 cho window_rom.v")
    ap.add_argument("--n", type=int, default=256, help="So diem FFT (N)")
    ap.add_argument("--type", type=str, default="hann", choices=list(WINDOW_FUNCS.keys()),
                     help="Loai cua so (mac dinh: hann, theo dung chot spec)")
    ap.add_argument("--out", type=str, default="./rom_out", help="Thu muc xuat file")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    w_float = WINDOW_FUNCS[args.type](args.n)

    w_float_safe = np.clip(w_float, None, 0.999969482421875)
    w_q15 = to_q15(w_float_safe)

    out_path = os.path.join(args.out, "window_coeff.mem")
    export_mem_hex(out_path, w_q15)

    print(f"[gen_window_coeff] N={args.n}, loai cua so = {args.type}")
    print(f"[gen_window_coeff] w[0]       = {w_q15[0]:6d}  (ky vong 0, canh cua so)")
    mid = args.n // 2
    print(f"[gen_window_coeff] w[N/2]     = {w_q15[mid]:6d}  (ky vong ~32767, dinh cua so)")
    print(f"[gen_window_coeff] Da xuat file vao: {out_path}")


if __name__ == "__main__":
    main()
