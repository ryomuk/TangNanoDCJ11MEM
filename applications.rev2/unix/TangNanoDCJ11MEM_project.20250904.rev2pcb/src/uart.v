// simple UART module
// data 8bit, no parity, stop 1bit, no flow control
// modified from Sipeed's example
// by Ryo Mukai
//
// 2023/06/28: initial version
// 2024/04/07: small bug fix
// 2024/04/11: small bug fix
// 2024/04/12: small bug fix
// 2024/04/13: uart_tx refactored
// 2024/05/07: uart_tx refactored
// 2024/07/07: small fix
// 2024/07/25: buffer for tx implemented
// 2024/07/27: 110 bps supported (TangNano's USB is miminum 1200bps, though)

`define USE_TX_BUFFER

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
   output      tx_out    // serial data output
   );

  localparam   CYCLE  = CLK_FRQ / BAUD_RATE;

`ifdef USE_TX_BUFFER
//-----------------------------------------------------------------
// tx buffer
//-----------------------------------------------------------------
  reg [7:0]    tx_data_i;
  reg	       tx_send_i;

  reg	       tx_buf_ready;
  assign tx_ready = tx_buf_ready;

  localparam   BS_IDLE  = 2'd0; // wait for tx_send    asserted
  localparam   BS_WAIT  = 2'd1; // wait for tx_send    deasserted
  localparam   BS_WAIT2 = 2'd2; // wait for tx_ready_i deasserted
  reg [1:0]    bufstate;
  
  reg [7:0] tx_buf[2047:0]; // block size of BSRAM is 2KB
  reg [10:0] tx_head;
  reg [10:0] tx_tail;
  reg [7:0] tx_buf_data;
  reg	    tx_buf_write;
  wire [10:0] tx_tail_next = tx_tail + 1'b1;
  wire [10:0] tx_head_next = tx_head + 1'b1;
  always @(posedge clk or negedge reset_n)
    if( ~reset_n ) begin
       bufstate <= BS_IDLE;
       {tx_head, tx_tail} = 0;
       tx_buf_ready <= 1'b1;
    end
    else 
      case (bufstate)
	BS_IDLE:
	  if( tx_send ) begin
	     // data is discarded when buffer is full
	     if(tx_head != tx_tail_next) begin
		tx_buf[tx_tail] <= tx_data;
		tx_tail <= tx_tail_next;
		tx_buf_ready <= 0;
	     end
	     bufstate <= BS_WAIT;
	  end
	  else if((tx_head != tx_tail) & tx_ready_i) begin
	     tx_data_i <= tx_buf[tx_head];
	     tx_send_i <= 1'b1;
	     tx_head <= tx_head_next;
	     bufstate <= BS_WAIT2;
	  end
	  else if(tx_head != tx_tail_next)
	    tx_buf_ready <= 1'b1;
	BS_WAIT:
	  if( tx_send == 1'b0 ) // wait for tx_send deasserted
	    bufstate <= BS_IDLE;
	BS_WAIT2:
	  if( ~tx_ready_i ) begin // wait for tx_ready_i deasserted
	     tx_send_i <= 0;
	     bufstate <= BS_IDLE;
	  end
	default:;
      endcase
`else
  wire [7:0]   tx_data_i = tx_data;
  wire	       tx_send_i = tx_send;
  assign       tx_ready  = tx_ready_i;
`endif // USE_TX_BUFFER

//-----------------------------------------------------------------
// internal transmitter
//-----------------------------------------------------------------

  localparam   S_IDLE = 2'd0; // wait for tx_send_i asserted
  localparam   S_SEND = 2'd1; // send start, data, stop bits
  localparam   S_WAIT = 2'd2; // wait for tx_send_i deasserted

  reg [1:0]    state;
  reg [19:0]   cycle_cnt;  // baud counter
  reg [3:0]    bit_cnt;
  reg [9:0]    send_buf;

  assign tx_out   = (state == S_SEND) ? send_buf[0] : 1'b1;

  wire	       tx_ready_i = (state == S_IDLE);
  always@(posedge clk or negedge reset_n)
    if(reset_n == 1'b0)
      state <= S_IDLE;
    else
      case(state)
	S_IDLE:
	  if(tx_send_i == 1'b1) begin
	     send_buf <= {1'b1, tx_data_i[7:0], 1'b0}; // stop + data + start
	     cycle_cnt <= 0;
	     bit_cnt <= 0;
	     state <= S_SEND;
	  end
	S_SEND:
	  if(cycle_cnt == CYCLE - 1) begin
	     if(bit_cnt == 4'd9)
	       state <= S_WAIT;
	     else begin
		send_buf[9:0] <= {1'b1, send_buf[9:1]};
		bit_cnt <= bit_cnt + 1'd1;
	     end
	     cycle_cnt <= 0;
	  end
	  else 
	    cycle_cnt <= cycle_cnt + 1'd1;
	S_WAIT:
	  if( tx_send_i == 1'b0 ) // wait for tx_send_i deasserted
	    state <= S_IDLE;
	default:;
      endcase
endmodule 

//-----------------------------------------------------------------
// receiver
//-----------------------------------------------------------------
//
// The module uart_rx is almost the same as the Sipeed's sample code.
//
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
  reg [19:0]	    cycle_cnt; // baud counter
  reg [2:0]	    bit_cnt;   // bit counter
  reg [7:0]	    rx_buffer; // received data buffer
  
  reg		    rx_d0;
  reg		    rx_d1;

  wire rx_negedge = rx_d1 & ~rx_d0;
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
	if((cycle_cnt == CYCLE - 1)  & (bit_cnt == 3'd7))
	  next_state <= S_STOP;
	else
	  next_state <= S_RECEIVE;
      S_STOP:   // half bit cycle, to avoid missing the next byte receiver
	if(cycle_cnt == (CYCLE/2) - 1)
	  next_state <= S_IDLE;
	else
	  next_state <= S_STOP;
      default:
	next_state <= S_IDLE;
    endcase

  always@(posedge clk)
    if(~reset_n | rx_clear)
      rx_data_ready <= 1'b0;
    else if(state == S_STOP & next_state != state)
      rx_data_ready <= 1'b1;

  always@(posedge clk)
    if(~reset_n)
      rx_data <= 8'd0;
    else if(state == S_STOP & next_state != state)
      rx_data <= rx_buffer;

  always@(posedge clk)
    if(~reset_n)
      bit_cnt <= 0;
    else if(state == S_RECEIVE)
      if(cycle_cnt == CYCLE - 1)
	bit_cnt <= bit_cnt + 1'd1;
      else
	bit_cnt <= bit_cnt;
    else
      bit_cnt <= 0;

  always@(posedge clk)
    if(~reset_n)
      cycle_cnt <= 0;
    else if(((state == S_RECEIVE) & (cycle_cnt == CYCLE - 1))
	    | (next_state != state))
      cycle_cnt <= 0;
    else
      cycle_cnt <= cycle_cnt + 1'd1;	

  //receive serial data bit data
  always@(posedge clk)
    if(~reset_n)
      rx_buffer <= 8'd0;
    else if((state == S_RECEIVE) & (cycle_cnt == (CYCLE/2) - 1))
	 rx_buffer[bit_cnt] <= rx_in;
    else
      rx_buffer <= rx_buffer; 

endmodule 
