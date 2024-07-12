//Copyright (C)2014-2024 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9.02 
//Created Time: 2024-07-11 21:21:28
create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]
create_clock -name ALE_n -period 222.222 -waveform {0 111.111} [get_ports {ALE_n}]
create_clock -name SCTL_n -period 222.222 -waveform {0 166.6} [get_ports {SCTL_n}]
