//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9.02
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C
//Created Time: Wed Jun 19 20:44:20 2024

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	Integer_Division_Top your_instance_name(
		.clk(clk_i), //input clk
		.rstn(rstn_i), //input rstn
		.dividend(dividend_i), //input [31:0] dividend
		.divisor(divisor_i), //input [15:0] divisor
		.remainder(remainder_o), //output [15:0] remainder
		.quotient(quotient_o) //output [31:0] quotient
	);

//--------Copy end-------------------
