// simple UART module
// data 8bit, no parity, stop 1bit, no flow control
// modified from Sipeed's example
// by Ryo Mukai
// 2023/06/28: initial version
// 2024/04/07: small bug fix
// 2024/04/11: small bug fix
// 2024/04/12: small bug fix
// 2024/04/13: uart_tx refactored
// 2024/06/21: tx_ready changed from reg to wire

module uart_tx
  #(
    parameter CLK_FRQ   = 0, //clock frequency(Mhz)
    parameter BAUD_RATE = 0  //serial baud rate
    )
  (
   input       clk, // clock input
   input       reset_n, // synchronous reset input, low active 
   input [7:0] tx_data, // data to send
   input       tx_send, // trigger for sending data
   output      tx_ready, // tx module ready
   output reg  tx_out    // serial data output
   );

  localparam   CYCLE = CLK_FRQ / BAUD_RATE;
  localparam   S_IDLE    = 2'd0; // wait for tx_send asserted
  localparam   S_SEND    = 2'd1; // send start, data, stop bits
  localparam   S_WAIT    = 2'd2; // wait for tx_send deasserted

  reg [1:0]    state;
  reg [15:0]   cycle_cnt;  // baud counter
  reg [3:0]    bit_cnt;
  reg [9:0]    send_buf;

  always@(posedge clk or negedge reset_n)
    if(reset_n == 1'b0)
      state <= S_IDLE;
    else
      case(state)
	S_IDLE:
	  if(tx_send == 1'b1)
	    state <= S_SEND;
	  else
	    state <= S_IDLE;
	S_SEND:
	  if(cycle_cnt == CYCLE - 1 && bit_cnt == 4'd9)
	    state <= S_WAIT;
	  else
	    state <= S_SEND;
	S_WAIT:
	  if( tx_send == 1'b0 ) // wait for tx_send deasserted
	    state <= S_IDLE;
	  else state <= S_WAIT;
	default:
	  state <= state;
      endcase
  
  assign tx_ready = (state == S_IDLE);

  always@(posedge clk)
    case(state)
      S_IDLE:
	send_buf <= {1'b1, tx_data[7:0], 1'b0}; // stop + data + start
      S_SEND:
	if(cycle_cnt == CYCLE - 1)
	  send_buf[9:0] <= {1'b1, send_buf[9:1]};
	else
	  send_buf <= send_buf;
      default:
	send_buf <= send_buf;
    endcase

  always@(posedge clk )
    case(state)
      S_IDLE:
	bit_cnt <= 4'd0;
      S_SEND:
	if(cycle_cnt == CYCLE - 1)
	  bit_cnt <= bit_cnt + 3'd1;
	else
	  bit_cnt <= bit_cnt;
      default:
	bit_cnt <= bit_cnt;
    endcase

  always@(posedge clk)
    case(state)
      S_SEND:
	if(cycle_cnt == CYCLE - 1)
	  cycle_cnt <= 16'd0;
	else
	  cycle_cnt <= cycle_cnt + 16'd1;	
      default:
	cycle_cnt <= 16'd0;
      endcase

  always@(posedge clk)
    if(state ==  S_SEND)
      tx_out <= send_buf[0];
    else
      tx_out <= 1'b1;

endmodule 

module uart_rx
  #(
    parameter CLK_FRQ   = 0, //clock frequency(Hz)
    parameter BAUD_RATE = 0  //serial baud rate
    )
  (
   input	    clk,     // clock input
   input	    reset_n, // synchronous reset input, low active 
   output reg [7:0] rx_data, // received serial data
   output reg	    rx_data_ready, // flag to indicate received data is ready
   input	    rx_clear,      // clear the rx_data_ready flag
   input	    rx_in   // serial data input
   );
  //calculates the clock cycle for baud rate 
  localparam	    CYCLE = CLK_FRQ / BAUD_RATE;
  //state machine code
  localparam	    S_IDLE      = 2'd0;
  localparam	    S_START     = 2'd1;
  localparam	    S_RECEIVE   = 2'd2;
  localparam	    S_STOP      = 2'd3;

  reg [1:0]	    state;
  reg [1:0]	    next_state;
  reg [15:0]	    cycle_cnt; // baud counter
  reg [2:0]	    bit_cnt;   // bit counter
  reg [7:0]	    rx_buffer; // received data buffer
  
  reg		    rx_d0;
  reg		    rx_d1;

  assign rx_negedge = rx_d1 && ~rx_d0;
  always@(posedge clk)
    if(reset_n == 1'b0)
      begin
	 rx_d0 <= 1'b0;
	 rx_d1 <= 1'b0;	
      end
    else
      begin
	 rx_d0 <= rx_in;
	 rx_d1 <= rx_d0;
      end

  always@(posedge clk)
    if(reset_n == 1'b0)
      state <= S_IDLE;
    else
      state <= next_state;

  always@(*)
    case(state)
      S_IDLE:
	if(rx_negedge)
	  next_state <= S_START;
	else
	  next_state <= S_IDLE;
      S_START:                      //one data cycle for start bit
	if(cycle_cnt == CYCLE - 1)
	  next_state <= S_RECEIVE;
	else
	  next_state <= S_START;
      S_RECEIVE:                     //receive 8bit data
	if(cycle_cnt == CYCLE - 1  && bit_cnt == 3'd7)
	  next_state <= S_STOP;
	else
	  next_state <= S_RECEIVE;
      S_STOP:   // half bit cycle, to avoid missing the next byte receiver
	if(cycle_cnt == CYCLE/2 - 1)
	  next_state <= S_IDLE;
	else
	  next_state <= S_STOP;
      default:
	next_state <= S_IDLE;
    endcase

  always@(posedge clk)
    if(~reset_n | rx_clear)
      rx_data_ready <= 1'b0;
    else if(state == S_STOP && next_state != state)
      rx_data_ready <= 1'b1;

  always@(posedge clk)
    if(~reset_n)
      rx_data <= 8'd0;
    else if(state == S_STOP && next_state != state)
      rx_data <= rx_buffer;

  always@(posedge clk)
    if(~reset_n)
      bit_cnt <= 3'd0;
    else if(state == S_RECEIVE)
      if(cycle_cnt == CYCLE - 1)
	bit_cnt <= bit_cnt + 3'd1;
      else
	bit_cnt <= bit_cnt;
    else
      bit_cnt <= 3'd0;

  always@(posedge clk)
    if(~reset_n)
      cycle_cnt <= 16'd0;
    else if((state == S_RECEIVE && cycle_cnt == CYCLE - 1)
	    || next_state != state)
      cycle_cnt <= 16'd0;
    else
      cycle_cnt <= cycle_cnt + 16'd1;	

  //receive serial data bit data
  always@(posedge clk)
    if(~reset_n)
      rx_buffer <= 8'd0;
    else if(state == S_RECEIVE && cycle_cnt == CYCLE/2 - 1)
	 rx_buffer[bit_cnt] <= rx_in;
    else
      rx_buffer <= rx_buffer; 

endmodule 
