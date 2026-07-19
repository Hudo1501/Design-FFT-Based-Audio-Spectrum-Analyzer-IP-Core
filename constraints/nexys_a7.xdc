# =============================================================================
# nexys_a7.xdc — Rang buoc cho Nexys A7-100T / A7-50T  (top = nexys_a7_top)
# -----------------------------------------------------------------------------
# *** QUAN TRONG — XAC NHAN CHAN TRUOC KHI NAP BOARD ***
# Cac ma chan duoi day theo Nexys A7 Master XDC chuan cua Digilent. TUY NHIEN
# toi KHONG the kiem chung chung tren phan cung that trong moi truong nay. Hay
# DOI CHIEU voi file "Nexys-A7-100T-Master.xdc" chinh thuc tai:
#   https://github.com/Digilent/digilent-xdc
# truoc khi generate bitstream. Gan sai chan mic co the KHONG hong board (chan
# I/O 3.3V) nhung se khong chay.
#
# Part: xc7a100tcsg324-1 (A7-100T) hoac xc7a50tcsg324-1 (A7-50T) -- CUNG bo chan.
# =============================================================================

# ---------------- CLOCK 100 MHz ----------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

# ---------------- RESET (nut CPU RESET, tich cuc THAP) ----------------
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports cpu_resetn]
set_false_path -from [get_ports cpu_resetn]

# ---------------- SWITCHES (SW0: chon nguon, SW1: du phong) ----------------
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_false_path -from [get_ports {sw[*]}]

# ---------------- MIC PDM tren board (ADMP421) ----------------
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports m_clk]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports m_data]
set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS33} [get_ports m_lrsel]
set_false_path -from [get_ports m_data]     ;# mic bat dong bo voi clk he thong

# ---------------- 7-SEGMENT (cathode CA..CG + DP, tich cuc THAP) ----------------
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]  ;# CA
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]  ;# CB
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]  ;# CC
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]  ;# CD
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]  ;# CE
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]  ;# CF
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]  ;# CG
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports dp]

# ---------------- 7-SEGMENT anode (AN0..AN7, tich cuc THAP) ----------------
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {an[2]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {an[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {an[4]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {an[5]}]
set_property -dict {PACKAGE_PIN K2  IOSTANDARD LVCMOS33} [get_ports {an[6]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {an[7]}]

# ---------------- LEDs LD0..LD15 ----------------
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {led[15]}]

# ---------------- cau hinh bitstream ----------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO      [current_design]
