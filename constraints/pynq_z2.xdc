# =============================================================================
# pynq_z2.xdc — Rang buoc cho PYNQ-Z2 (XC7Z020)  (top = pynq_z2_top)
# -----------------------------------------------------------------------------
# *** QUAN TRONG — XAC NHAN CHAN TRUOC KHI NAP BOARD ***
# Ma chan theo PYNQ-Z2 Master XDC (TUL / Digilent). Toi KHONG kiem chung duoc
# tren phan cung that trong moi truong nay -- hay DOI CHIEU voi file master XDC
# chinh thuc cua PYNQ-Z2 truoc khi generate bitstream.
#
# Part: xc7z020clg400-1
#
# *** LUU Y RIENG CHO ZYNQ ***
# Zynq co khoi PS (Processing System). Neu project CHI dung PL (nhu wrapper nay,
# thuan RTL, khong Block Design) thi Vivado co the canh bao thieu PS -- van
# generate bitstream duoc. Tuy nhien mot so bo board-file yeu cau co PS de cau
# hinh clock/DDR. NEU GAP LOI, cach chac chan la:
#   Tao Block Design co ZYNQ7 PS -> them wrapper nay lam RTL module -> noi
#   FCLK_CLK0 (dat 100 hoac 125 MHz) vao 'clk'. Xem README_BOARD.md.
# =============================================================================

# ---------------- CLOCK 125 MHz (onboard oscillator) ----------------
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 8.000 [get_ports clk]
# 8.000 ns = 125 MHz. Neu timing KHONG dong: dung MMCM tao 100 MHz (period 10.000)
# hoac chen them tang thanh ghi. Xem README_BOARD.md.

# ---------------- SWITCHES (2 cai) ----------------
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_false_path -from [get_ports {sw[*]}]

# ---------------- BUTTONS (4 cai; btn[0] = reset) ----------------
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]
set_false_path -from [get_ports {btn[*]}]

# ---------------- LEDs (4 cai) ----------------
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# ---------------- RGB LEDs (LD4, LD5) ----------------
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led4_rgb[0]}] ;# B
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {led4_rgb[1]}] ;# G
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {led4_rgb[2]}] ;# R
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {led5_rgb[0]}] ;# B
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {led5_rgb[1]}] ;# G
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led5_rgb[2]}] ;# R

# ---------------- cau hinh bitstream ----------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO      [current_design]
