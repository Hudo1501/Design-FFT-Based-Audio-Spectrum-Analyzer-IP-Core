"""
gen_twiddle_expected.py

Sinh doc lap tw_exp_re.mem / tw_exp_im.mem tu ham twiddle_q15() chinh thuc
trong golden_model_fft.py, dung de doi chieu voi NOI DUNG THAT DANG NAM
trong twiddle_re.mem / twiddle_im.mem (file ma twiddle_rom.v dang $readmemh).

Muc dich: khong chi kiem tra ROM doc dung dia chi (hardware fidelity), ma
con xac nhan CHINH NOI DUNG file .mem hien co trong project dung la ket qua
cua cong thuc twiddle_q15() HIEN TAI - phong truong hop file .mem bi cu/lech
so voi script sinh (dung dang bug "vector cu" da gap 1 lan voi tv_*.mem).

Chay: python gen_twiddle_expected.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from golden_model_fft import twiddle_q15

N = 256


def to_hex16(x):
    return format(x & 0xFFFF, "04x")


def main():
    os.makedirs("sim", exist_ok=True)
    with open("sim/tw_exp_re.mem", "w") as fre, open("sim/tw_exp_im.mem", "w") as fim:
        for k in range(N // 2):
            re, im = twiddle_q15(k)
            fre.write(to_hex16(re) + "\n")
            fim.write(to_hex16(im) + "\n")
    print(f"Da sinh {N//2} he so twiddle (doc lap) vao sim/tw_exp_re.mem, sim/tw_exp_im.mem")


if __name__ == "__main__":
    main()
