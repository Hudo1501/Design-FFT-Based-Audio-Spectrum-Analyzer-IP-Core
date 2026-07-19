import argparse, os
import numpy as np

FRAC = 15
QMAX = (1 << 15) - 1
QMIN = -(1 << 15)


def to_q15(x):
    q = int(np.round(float(x) * (1 << FRAC)))
    return max(QMIN, min(QMAX, q))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=256)
    ap.add_argument("--out", type=str, default="./rom_out")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    N = args.n
    path = os.path.join(args.out, "twiddle_coeff.mem")
    with open(path, "w") as f:
        for k in range(N):
            ang = -2.0 * np.pi * k / N
            re = to_q15(np.cos(ang)) & 0xFFFF
            im = to_q15(np.sin(ang)) & 0xFFFF
            f.write(f"{(re << 16) | im:08x}\n")
    print(f"[gen_twiddle_coeff] N={N} -> {path}")
    print(f"[gen_twiddle_coeff] W^0   = 1 - 0j     -> {(to_q15(1)&0xFFFF)<<16 | (to_q15(0)&0xFFFF):08x}")
    print(f"[gen_twiddle_coeff] W^N/4 = 0 - 1j     -> {(to_q15(0)&0xFFFF)<<16 | (to_q15(-1)&0xFFFF):08x}")


if __name__ == "__main__":
    main()
