//---------------------------------------------------------------------------
// TangNanoDCJ11MEM 
// Memory system and UART on TangNano 20K for testing DCJ11
//
// by Ryo Mukai
// 2024/04/25
//---------------------------------------------------------------------------

module top(
    input	 sw1,
    input	 sw2,
    input	 sys_clk, // 27MHz system clock
    input	 usb_rx,
    output	 usb_tx,
    input	 GPIO_RX,
    output	 GPIO_TX,
//    input	 CLK2,
    inout [15:0] DAL,
    input [3:0]	 AIO,
    input	 INIT_SW,
    output	 INIT_n,
    input	 BUFCTL_n,
    input	 ALE_n,
    input	 SCTL_n,
    output	 LED_RGB, 
    output [5:0] LED
    );

  parameter	 SYSCLK_FRQ  = 27_000_000; //Hz
  
//  parameter	 UART_BPS    =       1200; //Hz
//  parameter	 UART_BPS    =       9600; //Hz
  parameter	 UART_BPS    =      38400; //Hz
//  parameter	 UART_BPS    =     115200; //Hz
//  parameter	 UART_BPS    =     460800; //Hz

//  reg [15:0]	 mem[65535:0];
  // address or data of memory should be latched to infer BSRAM
  reg [7:0]	 mem_hi[32767:0]; // higher 8bit (odd byte address)
  reg [7:0]	 mem_lo[32767:0]; // lower  8bit (even byte address)
  
  reg [15:0]	 DAL_latched; // latched DAL[15:0]
  reg [3:0]	 AIO_latched; // latched AIO[3:0]
  
  wire		 RCSR; // D(=bit7)
  wire [7:0]	 RBUF; // DATA(=bit7..0)
  wire		 XCSR; // D(=bit7)
  wire [7:0]	 XBUF; // DATA(=bit7..0)

  reg		 RESET_n;

//---------------------------------------------------------------------------
// ODT registers
//---------------------------------------------------------------------------
  parameter ADRS_RCSR = 16'o177560;
  parameter ADRS_RBUF = 16'o177562;
  parameter ADRS_XCSR = 16'o177564;
  parameter ADRS_XBUF = 16'o177566;
//---------------------------------------------------------------------------
// AIO codes
//---------------------------------------------------------------------------
  parameter AIO_NONIO        = 4'b1111; // Non-I/O
  parameter AIO_GPREAD       = 4'b1110; // General-Purpose Read
  parameter AIO_INTACK       = 4'b1101; // Interrupt ack and vector read
  parameter AIO_IREADRQ      = 4'b1100; // Instruction stream request read
  parameter AIO_RMWNBL       = 4'b1011; // Read-Modify-Write, no bus lock
  parameter AIO_RMWBL        = 4'b1010; // Read-Modify-Write, bus lock
  parameter AIO_DREAD        = 4'b1001; // Data stream read
  parameter AIO_IREADDM      = 4'b1000; // Instruction stream demand read
  parameter AIO_GPWRITE      = 4'b0101; // General-Purpose Write
  parameter AIO_BUSBYTEWRITE = 4'b0011; // Bus byte write
  parameter AIO_BUSWORDWRITE = 4'b0001; // Bus word write
//---------------------------------------------------------------------------
// for uart
//---------------------------------------------------------------------------
  reg [7:0]  tx_data;
  wire	     tx_ready;
  reg	     tx_send = 0;
  wire [7:0] rx_data;
  wire	     rx_data_ready;
  reg	     rx_clear;
  
  wire	     uart_tx;
  wire	     uart_rx;

  assign GPIO_TX = uart_tx;
  assign usb_tx  = uart_tx;
  assign uart_rx = GPIO_RX & usb_rx;
//---------------------------------------------------------------------------
// Aliases
//---------------------------------------------------------------------------
  wire [15:0] address;
  wire [14:0] wordaddress;
  wire [8:0]  gpcode;

  wire [3:0]  aio_code;
  wire	      aio_read;
  wire	      aio_write;
  
  assign address     = DAL_latched;
  assign wordaddress = address[15:1];
  assign gpcode      = DAL_latched[8:0];
  assign aio_code    = AIO_latched;
  
  assign aio_write = (aio_code == AIO_BUSBYTEWRITE ||
		      aio_code == AIO_BUSWORDWRITE);
  assign aio_read = (aio_code == AIO_IREADRQ ||
		     aio_code == AIO_RMWNBL || 
		     aio_code == AIO_RMWBL || 
		     aio_code == AIO_DREAD ||
		     aio_code == AIO_IREADDM);
  
//---------------------------------------------------------------------------
// for debug
//---------------------------------------------------------------------------
//  parameter	 UART_BPS_DBG    =     2_700_000; //Hz (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     6_750_000; //Hz (27_000_000 / 4)
  parameter	 UART_BPS_DBG    =    13_500_000; //Hz (27_000_000 / 2)
  reg [7:0]	 dbg_tx_data[0:1];
  reg [1:0]	 dbg_tx_send;
  wire [1:0]     dbg_tx_ready;
  wire [1:0]	 dbg_tx;

  reg [7:0]		LED_R;
  reg [7:0]		LED_G;
  reg [7:0]		LED_B;
  
  reg [25:0]		cnt_500ms;
  reg			clk_1Hz;
     
//		    && (sw2 ? tx_data[7:0]!=8'h00 : tx_data[7:0]==8'h00));
// (address == ADRS_RCSR)||
// (address == ADRS_XCSR)||
// (address == ADRS_XBUF);

  wire			dbg_trg = tx_send;
  
  assign LED[0] = tx_ready;
  assign LED[1] = tx_send;
  //
  assign LED[2] = uart_tx;
  assign LED[5] = dbg_tx[0]; 
  assign LED[4] = dbg_tx[1];
  assign LED[3] = dbg_trg;
  
  ws2812 onboard_rgb_led(.clk(sys_clk), .we(1'b1), .sout(LED_RGB),
			 .r(LED_R), .g(LED_G), .b(LED_B));

  always @(posedge sys_clk)
    if(cnt_500ms == SYSCLK_FRQ/2) begin
       cnt_500ms <= 0;
       clk_1Hz = ~clk_1Hz;
    end else 
      cnt_500ms <= cnt_500ms + 1'b1;

  always @(posedge sys_clk)
    if(~RESET_n) begin
      {LED_R, LED_G, LED_B} <= 24'h00_00_00;
    end
    else begin
       LED_R <= ( rx_data_ready ) ? 8'h10: 8'h00;
       LED_G <= ( tx_ready ) ? 8'h10: 8'h00;
       LED_B <= ( clk_1Hz | sw2) ? 8'h10: 8'h00;
    end

  reg  last_SCTL_n;
  always @(posedge sys_clk) begin
     if(last_SCTL_n & ~SCTL_n) begin // negedge of SCTL_n
	if(dbg_tx_ready == 2'b11) begin
	   if(~sw2) begin
	      dbg_tx_data[0]  <= {3'b0, BUFCTL_n, aio_code};
	      dbg_tx_data[1] <= DAL[7:0];
	   end
	   else begin
	      dbg_tx_data[0] <= address[7:0];
	      dbg_tx_data[1] <= address[15:8];
	   end
	   dbg_tx_send <= 2'b11;
	end
     end
     else begin
	dbg_tx_send <= 2'b0;
     end
     last_SCTL_n <= SCTL_n;
  end

  uart_tx#
    (
     .CLK_FRQ(SYSCLK_FRQ),
     .BAUD_RATE(UART_BPS_DBG)
     ) uart_tx_inst_dbg0
      (
       .clk           (sys_clk),
       .reset_n       (RESET_n),
       .tx_data       (dbg_tx_data[0]),
       .tx_send       (dbg_tx_send[0]),
       .tx_ready      (dbg_tx_ready[0]),
       .tx_out        (dbg_tx[0])
       );

  uart_tx#
    (
     .CLK_FRQ(SYSCLK_FRQ),
     .BAUD_RATE(UART_BPS_DBG)
     ) uart_tx_inst_dbg1
      (
       .clk           (sys_clk),
       .reset_n       (RESET_n),
       .tx_data       (dbg_tx_data[1]),
       .tx_send       (dbg_tx_send[1]),
       .tx_ready      (dbg_tx_ready[1]),
       .tx_out        (dbg_tx[1])
       );

//---------------------------------------------------------------------------
// unimplemented signals
//---------------------------------------------------------------------------
//
//
  
//---------------------------------------------------------------------------
// ROM DATA
//---------------------------------------------------------------------------
`include "rom.v"
  
//---------------------------------------------------------------------------
// reset button and power on reset
//---------------------------------------------------------------------------
  reg [23:0]	 reset_cnt = 0;
  parameter	 RESET_WIDTH = (SYSCLK_FRQ / 1000) * 100; // 100ms
  always @(posedge sys_clk)
    if(sw1 | sw2) begin
       RESET_n <= 0;
       reset_cnt <= 0;
    end
    else if (reset_cnt != RESET_WIDTH) begin
       RESET_n <= 0;
       reset_cnt <= reset_cnt + 1'd1;
    end
    else
      RESET_n <= 1;
  
  reg reg_INIT_n;

  assign INIT_n = reg_INIT_n;
  reg [23:0]	 init_cnt = 0;
  parameter	 INIT_WIDTH = (SYSCLK_FRQ / 1000) * 100; // 100ms
  always @(posedge sys_clk)
    if(INIT_SW) begin
       reg_INIT_n <= 0;
       init_cnt <= 0;
    end
    else if (init_cnt != INIT_WIDTH) begin
       reg_INIT_n <= 0;
       init_cnt <= init_cnt + 1'd1;
    end
    else
      reg_INIT_n <= 1;
       
//---------------------------------------------------------------------------
// Memory and IO
//---------------------------------------------------------------------------
  assign DAL = BUFCTL_n ? 16'bzzzz_zzzz_zzzz_zzzz :
	       (aio_code == AIO_GPREAD && gpcode == 9'o000) ? 16'h0003 :
	       (aio_code == AIO_GPREAD && gpcode == 9'o002) ? 16'h0003 :
	       address == ADRS_RCSR ? {8'b0, RCSR, 7'b0} :
	       address == ADRS_RBUF ? {8'b0, RBUF} :
	       address == ADRS_XCSR ? {8'b0, XCSR, 7'b0} :
	       address == ADRS_XBUF ? {8'b0, XBUF} :
	       {mem_hi[wordaddress], mem_lo[wordaddress]};
  
//---------------------------------------------------------------------------
// Memory
//---------------------------------------------------------------------------
  always @(negedge ALE_n) begin // latch DAL and AIO
     DAL_latched <= DAL;
     AIO_latched <= AIO;
  end
  always @(negedge SCTL_n) begin
     if( aio_code == AIO_BUSBYTEWRITE) // bus byte write
       if(address[0])
	 mem_hi[wordaddress] <= DAL[15:8];
       else
	 mem_lo[wordaddress] <= DAL[7:0];
     else if( aio_code == AIO_BUSWORDWRITE) begin // bus word write
	mem_hi[wordaddress] <= DAL[15:8];
	mem_lo[wordaddress] <= DAL[7:0];
     end
  end
  
//---------------------------------------------------------------------------
// I/O (Memory Mapped)
//---------------------------------------------------------------------------
  always @(negedge SCTL_n) begin
     if((address == ADRS_RBUF) && aio_read && ~BUFCTL_n)
       // read RBUF (AIO_DREAD)
       rx_clear <= 1;
     else
       rx_clear <= 0;
     
     if((address == ADRS_XBUF) && aio_write && BUFCTL_n) begin
	// write to XBUF (AIO_BUSBYTEWRITE)
	tx_data <= DAL[7:0];
	if(tx_ready)
	  tx_send <= 1'b1;
	else
	  tx_send <= 1'b0;
     end
     else
       tx_send <= 0;
  end
  
  assign RCSR = rx_data_ready;  
  assign RBUF = rx_data;
  assign XCSR = tx_ready;
  assign XBUF = tx_data;
  
//---------------------------------------------------------------------------
// UART
//---------------------------------------------------------------------------
  uart_rx#
    (
     .CLK_FRQ(SYSCLK_FRQ),
     .BAUD_RATE(UART_BPS)
     ) uart_rx_inst
      (
       .clk           (sys_clk      ),
       .reset_n       (RESET_n      ),
       .rx_data       (rx_data      ),
       .rx_data_ready (rx_data_ready),
       .rx_clear      (rx_clear),
       .rx_in         (uart_rx      )
       );

  uart_tx#
    (
     .CLK_FRQ(SYSCLK_FRQ),
     .BAUD_RATE(UART_BPS)
     ) uart_tx_inst
      (
       .clk           (sys_clk),
       .reset_n       (RESET_n),
       .tx_data       (tx_data),
       .tx_send       (tx_send),
       .tx_ready      (tx_ready),
       .tx_out        (uart_tx)
       );

endmodule
