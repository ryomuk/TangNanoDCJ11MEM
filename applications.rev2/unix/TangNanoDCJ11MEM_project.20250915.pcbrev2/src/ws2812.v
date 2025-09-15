// ws2812 controller
// 2025/09/15
// by Ryo Mukai

module ws2812
  #(
    parameter CLK_FRQ = 27_000_000, // CLK (37.04ns)
    parameter LEDS = 1
    )
  (
   input		    clk,
   input [LEDS*8-1:0] r,
   input [LEDS*8-1:0] g,
   input [LEDS*8-1:0] b,
   output reg		    sout
);

  // WS2812B(old)
  // T0H: 250ns- 550ns
  // T1H: 650ns- 950ns
  // T0L: 700ns-1000ns
  // T1L: 300ns- 600ns
  // RES:   > 50_000ns (=50us)

  // WS2812B(new(V5)), WS2812C-2020
  // T0H: 220ns- 380ns
  // T1H: 580ns-1000ns
  // T0L: 580ns-1000ns
  // T1L: 580ns-1000ns
  // RES:  > 280_000ns (=280us)

  localparam CLK_KHZ     = CLK_FRQ / 1000;
  localparam DELAY_T0H   = (300 * CLK_KHZ) / 1_000_000; // 300ns
  localparam DELAY_T1H   = (800 * CLK_KHZ) / 1_000_000; // 800ns
  localparam DELAY_T0L   = (800 * CLK_KHZ) / 1_000_000; // 800ns
  localparam DELAY_T1L   = (600 * CLK_KHZ) / 1_000_000; // 600ns
  localparam DELAY_RESET = (400 * CLK_KHZ) /      1000; // 400us

  localparam S_RESET    = 3'd0;
  localparam S_START    = 3'd1;
  localparam S_SEND     = 3'd2;
  localparam S_SEND0H   = 3'd3;
  localparam S_SEND0L   = 3'd4;
  localparam S_SEND1H   = 3'd5;
  localparam S_SEND1L   = 3'd6;

  reg [2:0]  state     = S_RESET;
  reg [7:0]  led_cnt = 0; // max LEDS = 256
  reg [4:0]  bit_cnt = 0;
  reg [27:0] clk_cnt = 0;
  reg [23:0] data;
  reg [LEDS*8-1:0] r_buf;
  reg [LEDS*8-1:0] g_buf;
  reg [LEDS*8-1:0] b_buf;

  always@(posedge clk) begin
     case ( state )
       S_RESET: begin
	  sout <= 0;
	  if (clk_cnt == DELAY_RESET) begin
	     clk_cnt <= 0;
	     r_buf <= r;
	     g_buf <= g;
	     b_buf <= b;
	     led_cnt <= 0;
	     state <= S_START;
	  end
	  else
	    clk_cnt <= clk_cnt + 1'd1;
       end
       S_START: begin
	  sout <= 0;
	  data <= {g_buf[7:0], r_buf[7:0], b_buf[7:0]};
	  if (LEDS > 1) begin
	     r_buf <= r_buf >> 8;
	     g_buf <= g_buf >> 8;
	     b_buf <= b_buf >> 8;
	  end
	  led_cnt <= led_cnt + 1'd1;
	  bit_cnt <= 0;
	  state <= S_SEND;
       end
       S_SEND:
	 if (bit_cnt != 24) begin
	    bit_cnt <= bit_cnt + 1'd1;
	    clk_cnt <= 0;
	    if(data[23] == 1)
	      state <= S_SEND1H;
	    else
	      state <= S_SEND0H;
	    data <= {data[22:0], 1'd0};
	 end
	 else begin
	    if(led_cnt == LEDS)
	      state <= S_RESET;
	    else
	      state <= S_START;
	 end
       S_SEND1H: begin
	  sout <= 1;
	  if (clk_cnt == DELAY_T1H) begin
	     clk_cnt <= 0;
	     state <= S_SEND1L;
	  end
	  else
	    clk_cnt <= clk_cnt + 1'd1;
       end
       S_SEND1L: begin
	  sout <= 0;
	  if (clk_cnt == DELAY_T1L)
	    state <= S_SEND;
	  else
	    clk_cnt <= clk_cnt + 1'd1;
       end
       S_SEND0H: begin
	  sout <= 1;
	  if (clk_cnt == DELAY_T0H) begin
	     clk_cnt <= 0;
	     state <= S_SEND0L;
	  end
	  else
	    clk_cnt <= clk_cnt + 1'd1;
       end
       S_SEND0L: begin
	  sout <= 0;
	  if (clk_cnt == DELAY_T0L)
	    state <= S_SEND;
	  else
	    clk_cnt <= clk_cnt + 1'd1;
       end
     endcase
  end
endmodule
