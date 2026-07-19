#!/usr/bin/env python3
# Sinh vector vang cho tb_fft_r22sdf.v: input frame + FFT output natural-order
# (re/im) + magnitude single-sided + peak bin. Dung golden_model_fft.py.
import os, numpy as np
from golden_model_fft import (N, FRAC, to_q15, fft_core_frame, bitrev)

os.makedirs("rom_out", exist_ok=True)

def w16(v): return f"{v & 0xFFFF:04x}"

# Tin hieu test: tong 2 tone (bin 10 & bin 37) + it nhieu -> pho co dinh ro rang
n = np.arange(N)
sig = 0.6*np.cos(2*np.pi*10*n/N) + 0.3*np.cos(2*np.pi*37*n/N + 0.7)
sig = sig/(np.max(np.abs(sig))*1.02)          # |x|<1
xq = [to_q15(v) for v in sig]

start, sqnr, Xr, Xi = fft_core_frame(xq)
print(f"test-vector SQNR = {sqnr:.1f} dB")

# alpha-max-beta-min magnitude (khop magnitude_unit.v) tren output natural-order
ALPHA, BETA = 31471, 13036
def mag_ambm(re, im):
    ar, ai = abs(re), abs(im)
    mx, mn = max(ar, ai), min(ar, ai)
    full = ALPHA*mx + BETA*mn                  # unsigned
    # round-half-even >>15 + sat to 16-bit unsigned
    shift=15; rb=(full>>(shift-1))&1; lo=full&((1<<(shift-1))-1); base=full>>shift
    r = base if rb==0 else (base+1 if lo!=0 else (base if (base&1)==0 else base+1))
    return min(r, 0xFFFF)

mag = [mag_ambm(Xr[k], Xi[k]) for k in range(N)]
peak = int(np.argmax(mag[:N//2]))

# xuat .mem
with open("rom_out/tv_input.mem","w") as f:
    for v in xq: f.write(w16(v)+"\n")
with open("rom_out/tv_exp_real.mem","w") as f:
    for v in Xr: f.write(w16(v)+"\n")
with open("rom_out/tv_exp_imag.mem","w") as f:
    for v in Xi: f.write(w16(v)+"\n")
with open("rom_out/tv_exp_mag.mem","w") as f:
    for k in range(N//2): f.write(w16(mag[k])+"\n")
with open("rom_out/tv_meta.txt","w") as f:
    f.write(f"N={N}\nPEAK_BIN={peak}\nSQNR_dB={sqnr:.2f}\n")

print(f"expected single-sided peak bin = {peak} (expect 10)")
print("2nd peak bins around 37:", sorted(range(N//2), key=lambda k:-mag[k])[:4])
print("wrote rom_out/tv_*.mem")
