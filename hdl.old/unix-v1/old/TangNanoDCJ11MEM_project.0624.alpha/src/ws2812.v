// ws2812 controller
// 2023/6/21
// by Ryo Mukai

module ws2812(
	    input	clk,
	    input	we,
    	    input [7:0]	r,
    	    input [7:0]	g,
    	    input [7:0]	b,
	    output reg	sout
);

  parameter WIDTH   = 24; 
  parameter CLK_FRE = 27_000_000  ; // CLK (37.04ns)
  
  parameter DELAY_T0H    = 16'd9;     // 333ns, (220 to 380ns)
  parameter DELAY_T1H    = 16'd20;    // 740ns, (580 to 1000ns)
  parameter DELAY_T0L    = 16'd20;    // 740ns, (580 to 1000ns)
  parameter DELAY_T1L    = 16'd9;     // 333ns, (220 to 420ns)
  parameter DELAY_RESET  = 16'd13500; // 500us, ( > 280us)

  parameter S_WAIT     = 3'd0;
  parameter S_RESET    = 3'd1;
  parameter S_SEND     = 3'd2;
  parameter S_SEND0H   = 3'd3;
  parameter S_SEND0L   = 3'd4;
  parameter S_SEND1H   = 3'd5;
  parameter S_SEND1L   = 3'd6;
  
  reg [ 2:0] state     = S_WAIT;
  reg [ 4:0] bit_count = 0;
  reg [15:0] clk_count = 0;
  reg [23:0] data;

  always@(posedge clk) begin
     case ( state )
       S_WAIT: begin
	  sout <= 0;
	 if (we) begin
	    data <= {g, r, b};
	    bit_count <= 0;
	    state <= S_RESET;
	 end
       end
       S_RESET: begin
	  sout <= 0;
	  if (clk_count == DELAY_RESET) 
	    state <= S_SEND;
	  else
	    clk_count <= clk_count + 16'd1;
       end
       S_SEND:
	 if (bit_count != WIDTH) begin
	    bit_count <= bit_count + 1'd1;
	    clk_count <= 0;
	    if(data[23] == 1)
	      state <= S_SEND1H;
	    else
	      state <= S_SEND0H;
	    data <= {data[22:0], 1'd0};
	 end
	 else
	   state <= S_WAIT;
       S_SEND1H: begin
	  sout <= 1;
	  if (clk_count == DELAY_T1H) begin
	     clk_count <= 0;
	     state <= S_SEND1L;
	  end
	  else
	    clk_count <= clk_count + 16'd1;
       end
       S_SEND1L: begin
	  sout <= 0;
	  if (clk_count == DELAY_T1L)
	    state <= S_SEND;
	  else
	    clk_count <= clk_count + 16'd1;
       end
       S_SEND0H: begin
	  sout <= 1;
	  if (clk_count == DELAY_T0H) begin
	     clk_count <= 0;
	     state <= S_SEND0L;
	  end
	  else
	    clk_count <= clk_count + 16'd1;
       end
       S_SEND0L: begin
	  sout <= 0;
	  if (clk_count == DELAY_T0L)
	    state <= S_SEND;
	  else
	    clk_count <= clk_count + 16'd1;
       end
     endcase
  end
endmodule
