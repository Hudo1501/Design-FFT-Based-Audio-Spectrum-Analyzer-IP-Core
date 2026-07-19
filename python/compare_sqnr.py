import argparse
import numpy as np
from golden_model_fft import (N, FRAC, STAGES, to_q15, fft_core_frame, bitrev)


def sqnr(hw, ref):
    hw = np.asarray(hw); ref = np.asarray(ref)
    e = np.sum(np.abs(hw - ref) ** 2)
    p = np.sum(np.abs(ref) ** 2)
    return 10 * np.log10(p / e) if e > 0 else float('inf')


def load_input(path):
    xq = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                if v >= (1 << 15):
                    v -= (1 << 16)
                xq.append(v)
    return xq


def s16(v):
    return v - (1 << 16) if v >= (1 << 15) else v


def load_rtl_dump(path):
    """Doc dump RTL: moi dong '<re_hex> <im_hex>' hoac 1 so 32-bit {re[31:16],im[15:0]}."""
    vals = []
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if len(t) >= 2:
                re, im = s16(int(t[0], 16)), s16(int(t[1], 16))
            else:
                w = int(t[0], 16)
                re, im = s16((w >> 16) & 0xFFFF), s16(w & 0xFFFF)
            vals.append(re + 1j * im)
    return np.array(vals)


def unscramble(frame):
    X = np.zeros(N, dtype=complex)
    for k in range(N):
        X[bitrev(k)] = frame[k]
    return X


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self", action="store_true")
    ap.add_argument("--rtl", type=str, default=None)
    ap.add_argument("--input", type=str, default="rom_out/tv_input.mem")
    args = ap.parse_args()

    if args.self or not args.rtl:
        tot = []
        for seed in range(6):
            np.random.seed(seed)
            x = np.random.randn(N); x = x / (np.max(np.abs(x)) * 1.05)
            xq = [to_q15(v) for v in x]
            _, s, _, _ = fft_core_frame(xq)
            tot.append(s)
        print(f"[self] golden vs numpy.fft: SQNR = {np.mean(tot):.1f} dB (min {min(tot):.1f})")
        if not args.rtl:
            return

    xq = load_input(args.input)
    _, _, Gr, Gi = fft_core_frame(xq)                       # golden natural-order (int Q1.15)
    G = (np.array(Gr) + 1j * np.array(Gi)) / (1 << FRAC)
    Xref = np.fft.fft(np.array(xq) / (1 << FRAC)) / N       # numpy natural-order

    vals = load_rtl_dump(args.rtl)
    # tu canh khung: quet moi offset, chon SQNR-vs-golden tot nhat
    best = (-1e9, None)
    for start in range(0, len(vals) - N + 1):
        X = unscramble(vals[start:start + N]) / (1 << FRAC)
        s = sqnr(X, G)
        if s > best[0]:
            best = (s, (start, X))
    s_g, (start, X) = best
    print(f"[rtl] canh khung tai offset {start}")
    print(f"[rtl] SQNR RTL vs golden = {s_g:.1f} dB   (ky vong: rat cao / bit-exact)")
    print(f"[rtl] SQNR RTL vs numpy  = {sqnr(X, Xref):.1f} dB")
    mag = np.abs(X[:N // 2])
    print(f"[rtl] bin dinh = {int(np.argmax(mag))}")


if __name__ == "__main__":
    main()
