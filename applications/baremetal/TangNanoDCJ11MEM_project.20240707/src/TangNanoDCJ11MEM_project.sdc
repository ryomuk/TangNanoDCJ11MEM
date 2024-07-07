//Copyright (C)2014-2024 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9.02 
//Created Time: 2024-07-07 09:53:18
create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]
create_clock -name ALE_n -period 222.222 -waveform {0 55.555} [get_ports {ALE_n}]
create_clock -name SCTL_n -period 222.222 -waveform {0 166.666} [get_ports {SCTL_n}]
