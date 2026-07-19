# =============================================================================
# timing_only.xdc — RANG BUOC THOI GIAN (KHONG gan chan I/O)
# -----------------------------------------------------------------------------
# DUNG CHO: nghien cuu PPA (do Fmax / area / power) khi top = fft_analyzer_ip.
# KHONG dung de tao bitstream (vi chua gan chan) -- muon nap board thi xem
# nexys_a7.xdc / pynq_z2.xdc + module wrapper.
#
# Sua duoc loi:
#   [Timing 38-313] There are no user specified timing constraints
#   [Power 33-232]  No user defined clocks were found in the design!
#
# CACH DUNG (Tcl Console):
#   add_files -fileset constrs_1 constraints/timing_only.xdc
#   reset_run synth_1 ; launch_runs impl_1 -to_step route_design
#   open_run impl_1 ; report_timing_summary ; report_utilization ; report_power
# =============================================================================

# ---- 1) CLOCK: 100 MHz (chu ky 10 ns). Doi period de quet Fmax:
#         10.000 = 100 MHz | 6.667 = 150 MHz | 5.000 = 200 MHz | 20.000 = 50 MHz
create_clock -name clk -period 10.000 [get_ports clk]

# ---- 2) I/O delay: gia dinh ngoai IP co 2 ns setup/hold budget.
#         (Khi do PPA thuan tuy, con so nay chi anh huong duong I/O, khong anh
#          huong duong noi bo -- vong lap phe binh nhat cua thiet ke.)
set_input_delay  -clock clk 2.0 [get_ports {s_axis_tvalid s_axis_tdata[*] m_axis_tready}]
set_output_delay -clock clk 2.0 [get_ports {s_axis_tready m_axis_tvalid m_axis_tdata[*] \
                                            m_axis_tlast m_axis_tuser[*] \
                                            peak_valid peak_magnitude[*] peak_bin_idx[*] \
                                            busy core_en frame_count[*]}]

# ---- 3) Tin hieu KHONG dong bo (nut bam / reset ngoai): bo qua timing.
#         RTL da co reset dong bo; neu dua tu nut bam thi PHAI qua synchronizer
#         2-FF o wrapper (xem README). Danh dau false_path de tranh bao gia.
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports start]

# ---- 4) (Tuy chon) Neu muon Vivado bo qua rang buoc I/O va CHI toi uu duong
#         noi bo -- huu ich khi so sanh kien truc thuan tuy:
# set_false_path -from [all_inputs]  -to [all_registers]
# set_false_path -from [all_registers] -to [all_outputs]
