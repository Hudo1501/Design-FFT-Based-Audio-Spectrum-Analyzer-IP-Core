"""
gen_bin_ram_vectors.py

Sinh vector kiem chung cho bin_ram_output.v: mo hinh Python o day mo phong
CYCLE-ACCURATE dung theo ngu nghia non-blocking assignment cua Verilog (moi
thanh ghi tinh gia tri KE TIEP dua tren gia tri CU cua MOI thanh ghi lien
quan, roi commit dong loat) -- tranh suy dien do do phuc tap pipeline 2 tang
+ ping-pong buffer cua module nay.

Sinh 2 loai frame:
  - 3 khung magnitude NGAU NHIEN (kiem bit-exact toan bo pipeline, timing,
    ping-pong).
  - 1 khung "danh dau" voi magnitude[a] = a (chi so den) -- vi RAM luu tai
    dia chi bitrev(a), doc tu nhien tai k se cho gia tri bitrev(k). Day la
    phep kiem TRUC QUAN, doc lap voi do tin cay cua mo hinh Python, dung de
    doi chieu cheo truc tiep logic dao bit-reversed->tu nhien.

Chay: python gen_bin_ram_vectors.py
"""

import numpy as np
import os

N = 256
DW = 16
HALF = N // 2
LOG2N = N.bit_length() - 1


def to_hex16u(x):
    return format(x & 0xFFFF, "04x")


def bitrev(x):
    r = 0
    for b in range(LOG2N):
        r |= ((x >> (LOG2N - 1 - b)) & 1) << b
    return r


class BinRamModel:
    """Dich 1-1 tu bin_ram_output.v, dung ngu nghia NBA: moi 'next_*' chi
    phu thuoc gia tri CU cua thanh ghi/dau vao, khong phu thuoc 'next_*'
    khac tinh trong CUNG chu ky."""

    def __init__(self):
        self.ram = [[0] * N, [0] * N]
        self.wr_sel = 0
        self.arr_idx = 0
        self.rd_active = 0
        self.rd_sel = 0
        self.rd_idx = 0
        self.rd_data = 0
        self.rd_active_d = 0
        self.rd_sof_d = 0
        self.rd_last_d = 0
        self.rd_idx_d = 0
        self.out_valid = 0
        self.out_magnitude = 0
        self.out_bin_idx = 0
        self.out_sof = 0
        self.out_last = 0

    def clock(self, in_valid, in_magnitude, in_sof, in_last):
        old = self.__dict__.copy()
        ram_snapshot = [self.ram[0][:], self.ram[1][:]]  # doc TRUOC khi ghi cua chu ky nay

        arr_cur = 0 if in_sof else ((old["arr_idx"] + 1) % N)
        wr_addr = bitrev(arr_cur)

        # ---- ghi (always block 1) ----
        next_arr_idx = old["arr_idx"]
        if in_valid:
            next_arr_idx = arr_cur
            if old["wr_sel"] == 0:
                self.ram[0][wr_addr] = in_magnitude
            else:
                self.ram[1][wr_addr] = in_magnitude

        # ---- doc + dieu khien (always block 2), TAT CA RHS dung gia tri CU ----
        next_wr_sel = old["wr_sel"]
        next_rd_sel = old["rd_sel"]
        next_rd_active = old["rd_active"]
        next_rd_idx = old["rd_idx"]

        if in_valid and in_last:
            next_rd_sel = old["wr_sel"]
            next_wr_sel = 1 - old["wr_sel"]
            next_rd_active = 1
            next_rd_idx = 0
        elif old["rd_active"] and (old["rd_idx"] == HALF - 1):
            next_rd_active = 0
            # rd_idx, rd_sel, wr_sel giu nguyen (khong gan lai trong nhanh nay)
        elif old["rd_active"]:
            next_rd_idx = old["rd_idx"] + 1
            # rd_active giu nguyen (=1)

        next_rd_active_d = old["rd_active"]
        next_rd_idx_d = old["rd_idx"]
        next_rd_sof_d = 1 if (old["rd_active"] and old["rd_idx"] == 0) else 0
        next_rd_last_d = 1 if (old["rd_active"] and old["rd_idx"] == HALF - 1) else 0
        next_rd_data = ram_snapshot[old["rd_sel"]][old["rd_idx"]]

        next_out_valid = old["rd_active_d"]
        next_out_magnitude = old["rd_data"]
        next_out_bin_idx = old["rd_idx_d"]
        next_out_sof = old["rd_sof_d"]
        next_out_last = old["rd_last_d"]

        # ---- commit dong loat ----
        self.wr_sel = next_wr_sel
        self.arr_idx = next_arr_idx
        self.rd_active = next_rd_active
        self.rd_sel = next_rd_sel
        self.rd_idx = next_rd_idx
        self.rd_data = next_rd_data
        self.rd_active_d = next_rd_active_d
        self.rd_sof_d = next_rd_sof_d
        self.rd_last_d = next_rd_last_d
        self.rd_idx_d = next_rd_idx_d
        self.out_valid = next_out_valid
        self.out_magnitude = next_out_magnitude
        self.out_bin_idx = next_out_bin_idx
        self.out_sof = next_out_sof
        self.out_last = next_out_last


def main():
    os.makedirs("sim", exist_ok=True)
    rng = np.random.default_rng(21)

    frames_mag = []
    # 3 khung ngau nhien
    for _ in range(3):
        frames_mag.append(list(rng.integers(0, 65536, size=N)))
    # 1 khung "danh dau": magnitude[a] = a (0..N-1) -> doc tu nhien phai la bitrev(k)
    frames_mag.append(list(range(N)))

    in_mag, in_sof, in_last = [], [], []
    for frame in frames_mag:
        for a in range(N):
            in_mag.append(frame[a])
            in_sof.append(1 if a == 0 else 0)
            in_last.append(1 if a == N - 1 else 0)

    TOTAL = len(in_mag)

    model = BinRamModel()
    exp_valid, exp_mag, exp_bin, exp_sof, exp_last = [], [], [], [], []
    for t in range(TOTAL):
        model.clock(1, in_mag[t], in_sof[t], in_last[t])
        exp_valid.append(model.out_valid)
        exp_mag.append(model.out_magnitude)
        exp_bin.append(model.out_bin_idx)
        exp_sof.append(model.out_sof)
        exp_last.append(model.out_last)

    # chay them vai chu ky "duoi" (in_valid=0) de xa het pipeline doc cua khung cuoi
    DRAIN = 140
    for _ in range(DRAIN):
        model.clock(0, 0, 0, 0)
        exp_valid.append(model.out_valid)
        exp_mag.append(model.out_magnitude)
        exp_bin.append(model.out_bin_idx)
        exp_sof.append(model.out_sof)
        exp_last.append(model.out_last)

    with open("sim/br_in_mag.mem", "w") as f:
        for v in in_mag:
            f.write(to_hex16u(v) + "\n")
    with open("sim/br_in_sof.mem", "w") as f:
        for v in in_sof:
            f.write(("1" if v else "0") + "\n")
    with open("sim/br_in_last.mem", "w") as f:
        for v in in_last:
            f.write(("1" if v else "0") + "\n")

    with open("sim/br_exp_valid.mem", "w") as f:
        for v in exp_valid:
            f.write(("1" if v else "0") + "\n")
    with open("sim/br_exp_mag.mem", "w") as f:
        for v in exp_mag:
            f.write(to_hex16u(v) + "\n")
    with open("sim/br_exp_bin.mem", "w") as f:
        for v in exp_bin:
            f.write(format(v & 0xFF, "02x") + "\n")
    with open("sim/br_exp_sof.mem", "w") as f:
        for v in exp_sof:
            f.write(("1" if v else "0") + "\n")
    with open("sim/br_exp_last.mem", "w") as f:
        for v in exp_last:
            f.write(("1" if v else "0") + "\n")

    with open("sim/br_total.txt", "w") as f:
        f.write(str(TOTAL + DRAIN))
    with open("sim/br_total_input.txt", "w") as f:
        f.write(str(TOTAL))

    print(f"Da sinh {TOTAL} chu ky vao ({len(frames_mag)} khung) + {DRAIN} chu ky xa pipeline")
    print(f"Khung cuoi (chi so 3, 0-based) la khung 'danh dau': ky vong out_magnitude = bitrev(out_bin_idx)")


if __name__ == "__main__":
    main()
