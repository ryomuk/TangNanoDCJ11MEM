//---------------------------------------------------------------------------
// TangNanoDCJ11MEM 
// Memory system and UART on TangNano 20K for testing DCJ11
// (tape device version)
//
// by Ryo Mukai
// 2024/04/25: initial version
// 2024/05/22: PC-11(Paper-Tape Reader/Punch) emulator implemented
// 2024/06/21: tx_send and rx_clear logic modified 
// 2024/06/21: tape reader bug fixed
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

    output	 sd_clk,
    output	 sd_mosi, 
    input	 sd_miso,
    output	 sd_cs_n,
	   
    inout [15:0] DAL,
    input [3:0]	 AIO,
    input	 INIT_SW,
    output	 INIT_n,  // CPU reset signal
    input	 BUFCTL_n,
    input	 ALE_n,
    input	 SCTL_n,
    output	 LED_RGB, 
    output [5:0] LED_n
    );

  parameter	 SYSCLK_FRQ  = 27_000_000; //Hz
  
//  parameter	 UART_BPS    =       1200; //Hz
//  parameter	 UART_BPS    =       9600; //Hz
//  parameter	 UART_BPS    =      38400; //Hz
  parameter	 UART_BPS    =     115200; //Hz
//  parameter	 UART_BPS    =     460800; //Hz

  // address or data of memory should be latched to infer BSRAM
  reg [7:0]	 mem_hi[32767:0]; // higher 8bit (odd byte address)
  reg [7:0]	 mem_lo[32767:0]; // lower  8bit (even byte address)
  
  reg [15:0]	 DAL_latched; // latched DAL[15:0]
  reg [3:0]	 AIO_latched; // latched AIO[3:0]
  
  wire		 RCSR; // D(=bit7)
  wire [7:0]	 RBUF; // DATA(=bit7..0)
  wire		 XCSR; // D(=bit7)
  wire [7:0]	 XBUF; // DATA(=bit7..0)

  wire		 PR_BUSY;  // bit11
  wire		 PR_DONE;  // bit7
  wire		 PP_READY; // bit7
  wire [7:0]	 PRBUF;    // DATA(=bit7..0)
  reg [7:0]	 PPBUF;    // DATA(=bit7..0)

  reg		 tape_read;
  reg		 tape_punch;
  reg		 tape_clear_done;


  reg		 RESET_n; // Reset for memory system

//---------------------------------------------------------------------------
// Papertape Reader/Puncher registers
//---------------------------------------------------------------------------
  parameter ADRS_PRS  = 16'o177550; // Papertape Reader Status Register
  parameter ADRS_PRB  = 16'o177552; // Papertape Reader Buffer
  parameter ADRS_PPS  = 16'o177554; // Papertape Punch  Status
  parameter ADRS_PPB  = 16'o177556; // Papertape Punch  Buffer

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
  wire	      bus_read  = (aio_read  && (BUFCTL_n == 1'b0));
  wire	      bus_write = (aio_write && (BUFCTL_n == 1'b1));
  
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
`ifdef DBG_UART
//  parameter	 UART_BPS_DBG    =     2_700_000; //Hz (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     6_750_000; //Hz (27_000_000 / 4)
  parameter	 UART_BPS_DBG    =    13_500_000; //Hz (27_000_000 / 2)
  reg [7:0]	 dbg_tx_data[0:1];
  reg [1:0]	 dbg_tx_send;
  wire [1:0]     dbg_tx_ready;
  wire [1:0]	 dbg_tx;

  wire			dbg_trg = tx_send;
`endif
  
  reg [7:0]		LED_R;
  reg [7:0]		LED_G;
  reg [7:0]		LED_B;
  
  reg [25:0]		cnt_500ms;
  reg			clk_1Hz;
     
  assign LED_n = ~{sd_state[5:0]};
  
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
       LED_B <= ( clk_1Hz | sw2 ) ? 8'h10: 8'h00;
    end

`ifdef DEBUG_UART
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
`endif
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
// reset for UART and SD memory
  reg [23:0]	 reset_cnt = 0;
  parameter	 RESET_WIDTH = (SYSCLK_FRQ / 1000) * 100; // 100ms
  always @(posedge sys_clk)
    if( sw1 ) begin
       RESET_n <= 0;
       reset_cnt <= 0;
    end
    else if (reset_cnt != RESET_WIDTH) begin
       RESET_n <= 0;
       reset_cnt <= reset_cnt + 1'd1;
    end
    else
      RESET_n <= 1;
  
// reset for CPU
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
// Power-up Configurations
//---------------------------------------------------------------------------
// Power-Up Configuration Register
// [15:9] Bit<15:9> of the boot address (<8:0> are zeros.)
// [8]    FPA Here
// [7:4]  Unused
// [3]    Halt Option
// [2:1]  Power-up Mode
// [0]    POK

  // Enter console ODT
  wire [15:0] PUP_ODT   = 16'b0000000_0_0000_0_01_1;

  // Power-up to User Program
  wire [15:0] PUP_BOOTADDRESS  = 16'o001000; // boot address(Octal)
  wire [15:0] PUP_USER  = {PUP_BOOTADDRESS[15:9], 9'b0_0000_0_11_1};

  wire [15:0] PUP_CONF = PUP_ODT;
//  wire [15:0] PUP_CONF = PUP_USER;

//---------------------------------------------------------------------------
// Memory and IO
//---------------------------------------------------------------------------
  assign DAL = BUFCTL_n ? 16'bzzzz_zzzz_zzzz_zzzz :
	       (address == ADRS_RCSR) ? {8'b0, RCSR, 7'b0}:
	       (address == ADRS_RBUF) ? {8'b0, RBUF}:
	       (address == ADRS_XCSR) ? {8'b0, XCSR, 7'b0}:
	       (address == ADRS_XBUF) ? {8'b0, XBUF}:
	       (address == ADRS_PRS)  ? {4'b0, PR_BUSY, 3'b0, PR_DONE, 7'b0}:
	       (address == ADRS_PRB)  ? {8'b0, PRBUF}:
	       (address == ADRS_PPS)  ? {8'b0, PP_READY, 7'b0}:
	       (address == ADRS_PPB)  ? {8'b0, PPBUF}:
	       (aio_code == AIO_GPREAD && gpcode == 9'o000) ? PUP_CONF :
	       (aio_code == AIO_GPREAD && gpcode == 9'o002) ? PUP_CONF :
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
  always @(negedge BUFCTL_n or negedge rx_data_ready)
    if( ~rx_data_ready )
      rx_clear <= 0;
    else if( address == ADRS_RBUF )
      rx_clear <= 1;
    else
      rx_clear <= 0;

  always @(negedge SCTL_n or negedge tx_ready)
    if( ~tx_ready)
      tx_send <= 1'b0;
    else if((address == ADRS_XBUF) & bus_write)
      {tx_data[7:0], tx_send} <= {DAL[7:0], 1'b1};
    else
      tx_send <= 1'b0; // fail safe to avoid deadlock

  always @(negedge SCTL_n or posedge PR_BUSY) // reader enable
    if( PR_BUSY )
      tape_read <= 1'b0;
    else if((address == ADRS_PRS) & bus_write)
      if( DAL[0] == 1'b1 )
	tape_read <= 1'b1; // update PRBUF
      else 
	tape_read <= 1'b0;
    else
      tape_read <= 1'b0;
      
  always @(negedge BUFCTL_n) // read tape buffer
    if( wordaddress == (ADRS_PRB>>1) )
      tape_clear_done <= 1'b1;
    else if( ~PR_DONE )
      tape_clear_done <= 1'b0;
  
  always @(negedge SCTL_n) // write tape buffer
    if((address == ADRS_PPB) & bus_write) begin
       PPBUF <= DAL[7:0];
       if( PP_READY )  // tape punch ready
	 tape_punch <= 1'b1;
    end
    else if( ~PP_READY )
      tape_punch <= 1'b0;
  
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

//---------------------------------------------------------------------------
// SD memory tape emulator
//---------------------------------------------------------------------------
  wire tape_write_ready;
  wire tape_read_busy;
  wire tape_read_done;

  wire [3:0]  sd_error;
  wire [5:0]  sd_state;

  sdtape #(
	      .SYS_FRQ(27_000_000),
	      .MEM_FRQ(400_000)
    ) sdtape_inst
  (
   .i_clk              (sys_clk),
   .i_reset_n          (RESET_n),
   .i_sd_miso          (sd_miso),
   .o_sd_mosi          (sd_mosi),
   .o_sd_cs_n          (sd_cs_n),
   .o_sd_clk           (sd_clk),
   .o_tape_read_busy   (PR_BUSY),
   .o_tape_read_done   (PR_DONE),
   .o_tape_punch_ready (PP_READY),
   .i_tape_read        (tape_read),
   .i_tape_punch       (tape_punch),
   .i_tape_clear_done  (tape_clear_done),
   .i_tape_punch_data  (PPBUF),
   .o_tape_read_data   (PRBUF),
   .i_tape_flush       (sw2),
   .o_sd_state         (sd_state),
   .o_sd_error         (sd_error),
   .o_dbg              (DBG)
   );
  

endmodule
