//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.02 (64-bit) 
//Created Time: 2025-09-02 09:51:28
create_clock -name sys_clk27 -period 37.037 -waveform {0 18.518} [get_ports {sys_clk27}]
create_clock -name CLK2 -period 55.556 -waveform {0 27.778} [get_ports {CLK2}]
create_clock -name ALE -period 55.556 -waveform {0 27.778} [get_ports {ALE_n}]
create_clock -name SCTL -period 55.556 -waveform {0 27.778} [get_ports {SCTL_n}]
