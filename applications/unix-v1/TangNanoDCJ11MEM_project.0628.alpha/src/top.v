//---------------------------------------------------------------------------
// TangNanoDCJ11MEM 
// Memory system and peripherals on TangNano20K for DEC DCJ11 (PDP11)
//
// by Ryo Mukai
// https://github.com/ryomuk
//
// The following peripherals required to run UNIX version 1 are implemented,
// but with very limited functions and unstable.
// - KL11 TTY
// - RF11 drum
// - RK11 disk
// - KW11-L line time clock
// - KE11-A extended arithmetic unit
// 2024/06/09: Hard disk (RF11 and RK11) emulator (sdhd.v) implemented
// 2024/06/10: KW11-L emulator implemented
// 2024/06/11: KE11-A emulator implemented
// 2024/06/24: initial version (very unstable)
//---------------------------------------------------------------------------

`define USE_GPIOUART_DEBUG

module top(
    input	 sw1,
    input	 sw2,
    input	 sys_clk, // 27MHz system clock
    input	 usb_rx,
    output	 usb_tx,
    input	 GPIO_RX,
    output	 GPIO_TX,

    output	 sd_clk,
    output	 sd_mosi, 
    input	 sd_miso,
    output	 sd_cs_n,
	   
    inout [15:0] DAL,
    input [3:0]	 AIO,
    output [3:0] IRQ,
    output 	 EVENT_n,
    input	 INIT_SW,
    output	 INIT_n, // CPU reset signal
    input	 BUFCTL_n,
    input	 ALE_n,
    input	 SCTL_n,
    output	 LED_RGB, 
    output	 LED5_n
    );

  parameter	 SYSCLK_FRQ  = 27_000_000; //Hz
  
//  parameter	 UART_BPS    =       1200; //Hz
//  parameter	 UART_BPS    =       9600; //Hz
//  parameter	 UART_BPS    =      38400; //Hz
  parameter	 UART_BPS    =     115200; //Hz

  reg [15:0]	 DAL_latched; // latched DAL[15:0]
  reg [3:0]	 AIO_latched; // latched AIO[3:0]
  
  reg		 RESET_n; // Reset for memory system

//---------------------------------------------------------------------------
// RF11/RK11
//---------------------------------------------------------------------------
  reg	      devsel;
  parameter   DEV_RF = 1'b0;
  parameter   DEV_RK = 1'b1;
  
//---------------------------------------------------------------------------
// RF11 drum
//---------------------------------------------------------------------------
  parameter ADRS_RF_DCS  = 16'o177460; // Disk Control Status Register
    parameter RF_DCS_GO    = 1'b1;  // [0]
    parameter RF_DCS_WRITE = 2'b01; // [2:1]
    parameter RF_DCS_READ  = 2'b10; // [2:1]
  parameter ADRS_RF_WC   = 16'o177462; // Word Count Register
  parameter ADRS_RF_CMA  = 16'o177464; // Current Memory Address Register
  parameter ADRS_RF_DAR  = 16'o177466; // Disk Address Register
  parameter ADRS_RF_DAE  = 16'o177470; // Disk Address Ext & Error Register
  parameter ADRS_RF_DBR  = 16'o177472; // Disk Buffer Register
  parameter ADRS_RF_MAR  = 16'o177474; // Maintenance Register
  parameter ADRS_RF_ADS  = 16'o177476; // Address of Disk Segment Register

  reg [15:0] REG_RF_DCS;
  reg [15:0] REG_RF_WC;
  reg [15:0] REG_RF_CMA;
  reg [15:0] REG_RF_DAR;
  reg [15:0] REG_RF_DAE;
  reg [15:0] REG_RF_ADS;

  reg [15:0] REG_RF_WC_BAK;
  reg [15:0] REG_RF_CMA_BAK;
  reg [15:0] REG_RF_DAR_BAK;
  reg [15:0] REG_RF_DAE_BAK;
  
//---------------------------------------------------------------------------
// RK11 disk
//---------------------------------------------------------------------------
  parameter ADRS_RKDS = 16'o177400; // Disk Control Status Register
  parameter ADRS_RKER = 16'o177402; // Error Register
  parameter ADRS_RKCS = 16'o177404; // Control Status Register
    parameter RKCS_GO  = 1'b1;      // [0]
    parameter RKCS_CRESET = 3'b000;  // [3:1]
    parameter RKCS_WRITE  = 3'b001;  // [3:1]
    parameter RKCS_READ   = 3'b010;  // [3:1]
    parameter RKCS_SEEK   = 3'b100;  // [3:1]
    parameter RKCS_DRESET = 3'b110;  // [3:1]
  parameter ADRS_RKWC = 16'o177406; // Word Count Register
  parameter ADRS_RKBA = 16'o177410; // Current Bus Address Register
  parameter ADRS_RKDA = 16'o177412; // Disk Address Register
  parameter ADRS_RKMR = 16'o177414; // Maintenance Register
  parameter ADRS_RKDB = 16'o177416; // Disk Buffer Register

  reg [15:0] REG_RKCS;
  reg [15:0] REG_RKWC;
  reg [15:0] REG_RKBA;
  reg [15:0] REG_RKDA;
  
  reg [15:0] REG_RKWC_BAK;
  reg [15:0] REG_RKBA_BAK;

//---------------------------------------------------------------------------
// KE11 Extented Arithmetic Element
//---------------------------------------------------------------------------
  parameter  ADRS_KE_DIV = 16'o177300; // Divide
  parameter  ADRS_KE_AC  = 16'o177302; // Accumulator
  parameter  ADRS_KE_MQ  = 16'o177304; // Multiplier-Quotient
  parameter  ADRS_KE_MUL = 16'o177306; // Multiply
  parameter  ADRS_KE_SC  = 16'o177310; // Step Counter
  parameter  ADRS_KE_SR  = 16'o177311; // Status Register
  parameter  ADRS_KE_NOR = 16'o177312; // Normalization
  parameter  ADRS_KE_LSH = 16'o177314; // Logical Shift
  parameter  ADRS_KE_ASH = 16'o177326; // Arithmetic Shift

  reg [15:0] REG_KE_AC;
  reg [15:0] REG_KE_MQ;
  reg [7:0]  REG_KE_SC;
  wire [7:0] REG_KE_SR;

//---------------------------------------------------------------------------
// Console / KL11 registers
//---------------------------------------------------------------------------
  parameter ADRS_RCSR = 16'o177560; // Console read status (aka TKS)
  parameter ADRS_RBUF = 16'o177562; // Console read buffer (aka TKB)
  parameter ADRS_XCSR = 16'o177564; // Console send status (aka TPS)
  parameter ADRS_XBUF = 16'o177566; // Console send buffer (aka TPB)

  reg		 RCSR_ID;                    // bit6
  wire		 RCSR_DONE  = rx_data_ready; // bit7
  reg		 XCSR_ID;                    // bit6
  wire		 XCSR_READY = tx_ready ;     // bit7
  wire [7:0]	 RBUF       = rx_data;       // DATA(=bit7..0)
  wire [7:0]	 XBUF       = tx_data;       // DATA(=bit7..0)

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

  assign usb_tx  = uart_tx;

`ifdef USE_GPIOUART_DEBUG
  assign GPIO_TX = dbg_tx;
  assign uart_rx = usb_rx;
`else
  assign GPIO_TX = uart_tx;
  assign uart_rx = GPIO_RX & usb_rx;
`endif // USE_GPIOUART_DEBUG
  
//---------------------------------------------------------------------------
// Aliases
//---------------------------------------------------------------------------
  wire [15:0] address = DAL_latched;
  wire [8:0]  gpcode  = DAL_latched[8:0];
  wire [2:0]  irq_ack_level; // IRQ level acknowledged

  assign irq_ack_level = (DAL_latched[3:0] == 4'b0001) ? 3'd4: // IRQ0
			 (DAL_latched[3:0] == 4'b0010) ? 3'd5: // IRQ1
			 (DAL_latched[3:0] == 4'b0100) ? 3'd6: // IRQ2
			 (DAL_latched[3:0] == 4'b1000) ? 3'd7: // IRQ3
			 0;
			 
  wire	      bus_read  = (aio_read  && (BUFCTL_n == 1'b0));
  wire	      bus_write = (aio_write && (BUFCTL_n == 1'b1));
  
  wire [3:0]  aio_code = AIO_latched;
  wire aio_write = (aio_code == AIO_BUSBYTEWRITE ||
		      aio_code == AIO_BUSWORDWRITE);
  wire aio_write_lowbyte = (aio_code == AIO_BUSBYTEWRITE) & ~address[0];
  wire aio_write_highbyte = (aio_code == AIO_BUSBYTEWRITE) & address[0];
  wire aio_read = (aio_code == AIO_IREADRQ ||
		     aio_code == AIO_INTACK ||
		     aio_code == AIO_RMWNBL || 
		     aio_code == AIO_RMWBL || 
		     aio_code == AIO_DREAD ||
		     aio_code == AIO_IREADDM);
  wire aio_iread = (aio_code == AIO_IREADRQ ||
		    aio_code == AIO_IREADDM);

//---------------------------------------------------------------------------
// reset button and power on reset
//---------------------------------------------------------------------------
// reset for UART and SD memory
  reg [27:0]	 reset_cnt = 0;
  parameter	 RESET_WIDTH = (SYSCLK_FRQ / 1000) * 250; // 250ms
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
  reg [27:0]	 init_cnt = 0;
  parameter	 INIT_WIDTH = (SYSCLK_FRQ / 1000) * 250; // 250ms
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
// see "DCJ11 Microprocessor User's Guide, 8.3.3 Power-Up Configuration"
//
// Power-Up Configuration Register
// [15:9] Bit<15:9> of the boot address (<8:0> are zeros.)
// [8]    FPA Here
// [7:4]  Unused
// [3]    Halt Option
//          0: Enters console ODT on HALT
//          1: Trap to 4
// [2:1]  Power-up Mode
//          01: Enter console ODT (PS=0)
//          10: Power-up to 17773000(173000) (PS=340)
//          11: Power-up to the user-defined address([15:9])(PS=340)
// [0]    POK (1: power OK)

  // Enter console ODT
  wire [15:0] PUP_ODT   = 16'b0000000_0_0000_0_01_1;

  // Power-up to 173000
  wire [15:0] PUP_173000  = 16'b0000000_0_0000_0_10_1;

  // Power-up to User Program (xxx000, lower 9bits are 0)
  wire [15:0] PUP_BOOTADDRESS  = 16'o173000; // boot address(Octal)
  wire [15:0] PUP_USER  = {PUP_BOOTADDRESS[15:9], 9'b0_0000_0_11_1};

//  wire [15:0] PUP_CONF = PUP_ODT;
//  wire [15:0] PUP_CONF = PUP_173000;
  wire [15:0] PUP_CONF = PUP_USER;

//---------------------------------------------------------------------------
// Memory and IO
//---------------------------------------------------------------------------
  assign DAL = BUFCTL_n ? 16'bzzzz_zzzz_zzzz_zzzz :
       (address == ADRS_RCSR) ? {8'b0, RCSR_DONE, RCSR_ID, 6'b0}:
       (address == ADRS_RBUF) ? {8'b0, RBUF}:
       (address == ADRS_XCSR) ? {8'b0, XCSR_READY, XCSR_ID, 6'b0}:
       (address == ADRS_XBUF) ? {8'b0, XBUF}:
       (address == ADRS_RF_DCS) ? {8'b0, RFRK_READY, REG_RF_DCS[6:1], 1'b0}:
       (address == ADRS_RF_WC)  ? REG_RF_WC:
       (address == ADRS_RF_CMA) ? REG_RF_CMA:
       (address == ADRS_RF_DAR) ? REG_RF_DAR:
       (address == ADRS_RF_DAE) ? REG_RF_DAE:
       (address == ADRS_RF_ADS) ? REG_RF_ADS:
       (address == ADRS_RKDS) ? {8'b000_01001,
				 RFRK_READY, RFRK_READY,
				 2'b01, REG_RKDA[3:0]}:
       (address == ADRS_RKER) ? 16'b0: // error register not implemented
       (address == ADRS_RKCS) ? {2'b00, REG_RKCS[13:8],
				 RFRK_READY, REG_RKCS[6:0]}:
       (address == ADRS_RKWC) ? REG_RKWC:
       (address == ADRS_RKBA) ? REG_RKBA:
       (address == ADRS_RKDA) ? REG_RKDA:
       (address == ADRS_KW11L)  ? REG_KW11L:
       (address == ADRS_KE_DIV) ? 16'b0:
       (address == ADRS_KE_AC ) ? REG_KE_AC:
       (address == ADRS_KE_MQ ) ? REG_KE_MQ:
       (address == ADRS_KE_MUL) ? 16'b0:
       (address == ADRS_KE_SC ) ? {REG_KE_SR, REG_KE_SC}:
       (address == ADRS_KE_SR ) ? {REG_KE_SR, REG_KE_SC}:
       (address == ADRS_KE_NOR) ? REG_KE_SC: // read NOR returns SC
       (address == ADRS_KE_LSH) ? 16'b0:
       (address == ADRS_KE_ASH) ? 16'b0:
       (aio_code == AIO_GPREAD && gpcode == 9'o000) ? PUP_CONF :
       (aio_code == AIO_GPREAD && gpcode == 9'o002) ? PUP_CONF :
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ0) ? VA_IRQ0:
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ1) ? VA_IRQ1:
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ2) ? VA_IRQ2:
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ3) ? VA_IRQ3:
       (address == ADRS_DBG0) ? REG_DBG0:
       (address == ADRS_DBG1) ? REG_DBG1:
       (address == ADRS_DBG2) ? REG_DBG2:
       d_ram_to_cpu;
  
//---------------------------------------------------------------------------
// Memory
//---------------------------------------------------------------------------
  always @(negedge ALE_n) begin // latch DAL and AIO
     DAL_latched <= DAL;
     AIO_latched <= AIO;
  end

//  always @(negedge SCTL_n) begin
//     if( aio_code == AIO_BUSBYTEWRITE) // bus byte write
//       if(address[0])
//	 mem_hi[wordaddress] <= DAL[15:8];
//       else
//	 mem_lo[wordaddress] <= DAL[7:0];
//     else if( aio_code == AIO_BUSWORDWRITE) begin // bus word write
//	mem_hi[wordaddress] <= DAL[15:8];
//	mem_lo[wordaddress] <= DAL[7:0];
//     end
//  end
  
  wire write_memory_hi = ~SCTL_n &
       (( aio_code == AIO_BUSWORDWRITE) |
	( aio_code == AIO_BUSBYTEWRITE) & address[0]);
  wire write_memory_lo = ~SCTL_n &
       (( aio_code == AIO_BUSWORDWRITE) |
	( aio_code == AIO_BUSBYTEWRITE) & ~address[0]);
  
//---------------------------------------------------------------------------
// I/O (Memory Mapped)
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
// KE11 Arithmetic unit
//---------------------------------------------------------------------------
  assign REG_KE_SR[7:0] = {1'b0, // not implemented
			   REG_KE_AC[15], // not implemented preperly
			   REG_KE_AC == 16'o177777,
			   REG_KE_AC == 16'o0,
			   REG_KE_MQ == 16'o0,
			   (REG_KE_AC == 16'o0) && (REG_KE_MQ == 16'o0),
			   REG_KE_AC == (REG_KE_MQ[15] ? 16'o177777: 16'o0),
			   REG_KE_SR0
			   };

  wire div_clk = sys_clk;
  reg [31:0] dividend;
  reg [15:0] divisor;
  wire [31:0] quotient;  //= dividend[31:0] / divisor[15:0];
  wire [15:0] remainder; //= dividend[31:0] % divisor[15:0];
  
//------------
// divider
//------------
// Gowin IP
  Integer_Division_Top integer_division(
		.clk(div_clk), //input clk
		.rstn(INIT_n), //input rstn
		.dividend(dividend), //input [31:0] dividend
		.divisor(divisor), //input [15:0] divisor
		.remainder(remainder), //output [15:0] remainder
		.quotient(quotient) //output [31:0] quotient
	);

  reg [6:0] div_cnt;
  parameter DIV_LATENCY = 6'd34;
  reg	    div_done;
  reg	    last_div_execute;
  reg	    div_execute;
  always @(posedge div_clk)
    last_div_execute <= div_execute;

  always @(posedge div_clk)
    if( ~last_div_execute & div_execute)
      {div_cnt, div_done} <= 0;
    else if (div_cnt == DIV_LATENCY)
      if( div_execute )
	div_done <=  1'b1;
      else
	div_done <=  1'b0;
    else
      div_cnt <= div_cnt + 1'b1;

//------------
// multiplier
//------------
  wire	[15:0]  abs_multiplicand = REG_KE_MQ[15] ?
		((~REG_KE_MQ[15:0]) + 1'b1) :
		REG_KE_MQ[15:0];
  wire [15:0]	abs_multiplier   = REG_KE_X[15] ? 
		((~REG_KE_X[15:0]) + 1'b1) :
		REG_KE_X[15:0];
  wire		mul_sign = REG_KE_MQ[15] ^ REG_KE_X[15];
  wire [31:0]	abs_product = abs_multiplicand[15:0] * abs_multiplier[15:0];
  wire [31:0]	product = mul_sign ?
		((~abs_product[30:0])+1'b1) :
		{1'b0, abs_product[30:0]};
  
//------------
// Bus access 
//------------

  reg REG_KE_SR0;  // SR[0]
  wire [15:0] REG_KE_X = aio_write_lowbyte ? 
              {(DAL[7] ? 8'hFF: 8'h00), DAL[7:0]} // extend sign
	      : DAL;

  always @(negedge SCTL_n or negedge ALE_n or negedge INIT_n)
    if( ~INIT_n ) begin
       {REG_KE_AC, REG_KE_MQ, REG_KE_SC, div_execute} <= 0;
    end
    else if( ~ALE_n ) begin
       if ( div_execute & div_done) begin
	  //	  REG_KE_MQ[15:0] <= {quotient[15], quotient[14:0]};
	  REG_KE_MQ[15:0] <= quotient[15:0];
	  REG_KE_AC <= remainder[15:0];
	  div_execute <= 0;
       end
    end
    else if(bus_write)
      case (address)
	ADRS_KE_AC: begin
	   if(aio_write_lowbyte) // extend sign
	     REG_KE_AC <= {(DAL[7] ? 8'hFF: 8'h00), DAL[7:0]};
	   else 
	     REG_KE_AC <= DAL;
	end
	ADRS_KE_MQ: begin
	   if(aio_write_lowbyte) begin // extend sign
	      REG_KE_MQ <= {(DAL[7] ? 8'hFF: 8'h00), DAL[7:0]};
	      REG_KE_AC <= DAL[7] ? 16'hFFFF: 16'h0000;
	   end
	   else begin  // extend sign to AC
	      REG_KE_MQ <= DAL;
	      REG_KE_AC <= DAL[15] ? 16'hFFFF: 16'h0000;
	   end
	end
	ADRS_KE_SC:  REG_KE_SC <= DAL[7:0];
	ADRS_KE_DIV: begin
	   // MQ={AC,MQ}/DIV, AC={AC,MQ}%DIV
	   dividend[31:0] <= {REG_KE_AC[15:0], REG_KE_MQ[15:0]};
	   divisor[15:0]  <= REG_KE_X[15:0];
	   div_execute    <= 1'b1;
	   REG_KE_SR0     <= 1'b0;  
//	   {dummy16[15:0], REG_KE_MQ} <= {REG_KE_AC, REG_KE_MQ} / REG_KE_X;
//	   REG_KE_AC <= {REG_KE_AC, REG_KE_MQ} % REG_KE_X;
//	   {dummy16[15:0], REG_KE_MQ} <= {REG_KE_AC, REG_KE_MQ} / 16'd12;
//	   REG_KE_AC <= {REG_KE_AC, REG_KE_MQ} % 16'd12;
	end
	ADRS_KE_MUL: begin
	   // {AC,MQ}=MQ*MUL
	   {REG_KE_AC, REG_KE_MQ} <= product;
	   REG_KE_SR0 <= 1'b0;
	end
	ADRS_KE_NOR: begin // not implemented yet
	   REG_KE_SR0 <= 1'b0;
	end
	ADRS_KE_LSH: begin
	   REG_KE_SC <= DAL[7:0];
	   if(~DAL[5])
	     {REG_KE_SR0, REG_KE_AC, REG_KE_MQ}
	       <= {REG_KE_SR0, REG_KE_AC, REG_KE_MQ} << DAL[4:0];
	   else
	     {REG_KE_AC, REG_KE_MQ, REG_KE_SR0}
	       <= {REG_KE_AC, REG_KE_MQ, REG_KE_SR0}
		  >> ((~DAL[4:0])+1'b1);
	end
	ADRS_KE_ASH: begin
	   REG_KE_SC <= DAL[7:0];
	   if(~DAL[5])
	     {REG_KE_SR0, REG_KE_AC[14:0], REG_KE_MQ}
	       <= {REG_KE_SR0, REG_KE_AC[14:0], REG_KE_MQ} << DAL[4:0];
	   else
	     {REG_KE_AC[14:0], REG_KE_MQ, REG_KE_SR0}
	       <= {REG_KE_AC[14:0], REG_KE_MQ, REG_KE_SR0}
		  >> ((~DAL[4:0])+1'b1);
	end
	default:;
      endcase
  
//---------------------------------------------------------------------------
// RL11 TTY console
//---------------------------------------------------------------------------
//  always @(negedge BUFCTL_n)
  always @(negedge BUFCTL_n or negedge rx_data_ready)
    if( ~rx_data_ready )
      rx_clear <= 0;
    else if( address == ADRS_RBUF )
      rx_clear <= 1;
    else
      rx_clear <= 0;

  always @(negedge SCTL_n or negedge tx_ready)
    if( ~tx_ready )
      tx_send <= 1'b0;
    else if((address == ADRS_XBUF) & bus_write)
      {tx_data[7:0], tx_send} <= {DAL[7:0], 1'b1};
    else 
      tx_send <= 1'b0; // fail safe to avoid deadlock
  
  always @(negedge SCTL_n )
    if( (address == ADRS_RCSR) & bus_write)
      RCSR_ID <= DAL[6];
    else if( (address == ADRS_XCSR) & bus_write)
      XCSR_ID <= DAL[6];

//---------------------------------------------------------------------------
// RF11 (drum) and RK11 (disk)
//---------------------------------------------------------------------------
  parameter  RF_total_block_size   = 11'd1024; // 512byte * 1024 blocks

//  wire RFRK_READY = disk_ready & ~disk_read & ~disk_write;
  wire	     RFRK_READY = disk_ready;
  wire [12:0] RK_block_address = {1'b0, REG_RKDA[12:4], 3'b000} +
  	      {2'b00, REG_RKDA[12:4], 2'b00} +
	      {9'b00000000,   REG_RKDA[3:0]} +
	      RF_total_block_size;

  always @(negedge SCTL_n or negedge disk_ready or negedge INIT_n)
    if( ~INIT_n ) begin
       {REG_RF_DCS, REG_RF_WC,  REG_RF_CMA}     <= 0;
       {REG_RF_DAR, REG_RF_DAE, REG_RF_ADS}     <= 0;
       {REG_RKCS, REG_RKWC, REG_RKBA, REG_RKDA} <= 0;
    end
    else if( ~disk_ready ) begin
       disk_read  <= 1'b0;
       disk_write <= 1'b0;
       disk_seek  <= 1'b0;
    end
    else if( bus_write )
      if( address == ADRS_RF_DCS ) begin
	 REG_RF_DCS <= DAL;
	 if( DAL[8] ) begin // RF disk clear 
	    {REG_RF_DCS, REG_RF_WC,  REG_RF_CMA} <= 0;
	    {REG_RF_DAR, REG_RF_DAE, REG_RF_ADS} <= 0;
	 end
	 else if(DAL[0] == RF_DCS_GO) begin
	    devsel <= DEV_RF;
	    disk_block_address[12:0] <= {3'b000,
					 REG_RF_DAE[1:0], REG_RF_DAR[15:8]};
	    dma_start_address <= REG_RF_CMA;
	    dma_wordcount     <= REG_RF_WC;
	    
	    // update registers (this is not correct implementation)
	    REG_RF_WC  <= 0;
	    REG_RF_CMA <= REG_RF_CMA + (((~REG_RF_WC[15:0]) + 1'b1)<<1);
	    {REG_RF_DAE[1:0], REG_RF_DAR} <= {REG_RF_DAE[1:0], REG_RF_DAR} +
					     {(~REG_RF_WC[15:0]) + 1'b1};
	    
	    REG_RF_WC_BAK  <= REG_RF_WC;
	    REG_RF_CMA_BAK <= REG_RF_CMA;
	    REG_RF_DAE_BAK <= REG_RF_DAE;
	    REG_RF_DAR_BAK <= REG_RF_DAR;
	    
	    case(DAL[2:1])
	      RF_DCS_READ:  disk_read  <= 1'b1;
	      RF_DCS_WRITE: disk_write <= 1'b1;
	      default:;
	    endcase
	 end
      end
      else if(address == ADRS_RKCS ) begin
	 REG_RKCS   <= DAL;
	 if(DAL[0] == RKCS_GO) begin
	    devsel <= DEV_RK;
	    //	  disk_block_address [12:0] <= (REG_RKDA[12:4] * 12) +
	    //				       REG_RKDA[3:0] +
	    //				       RF_total_block_size;
	    disk_block_address[12:0] <= RK_block_address[12:0];
	    dma_start_address <= REG_RKBA;
	    dma_wordcount     <= REG_RKWC;

	    // update registers (this is not correct implementation)
	    REG_RKWC <= 0;
	    REG_RKBA <= REG_RKBA + (((~REG_RKWC[15:0]) + 1'b1)<<1);
	    REG_RKWC_BAK <= REG_RKWC;
	    REG_RKBA_BAK <= REG_RKBA;
	    
	    case ( DAL[3:1] ) // REG_RKCS[13] is SCP(Search complete) bit
	      RKCS_READ:   {disk_read,  REG_RKCS[13]} <= 2'b10;
	      RKCS_WRITE:  {disk_write, REG_RKCS[13]} <= 2'b10;
	      RKCS_CRESET: {REG_RKCS, REG_RKWC, REG_RKBA, REG_RKDA} <= 0;
	      RKCS_DRESET: {disk_seek, REG_RKCS[13]} <= 2'b11;
	      RKCS_SEEK:   {disk_seek, REG_RKCS[13]} <= 2'b11;
	      default: REG_RKCS[13] <= 1'b0;
	    endcase
	 end
      end
      else
	case (address)
	  ADRS_RF_WC:  REG_RF_WC  <= DAL;
	  ADRS_RF_CMA: REG_RF_CMA <= DAL;
	  ADRS_RF_DAR: REG_RF_DAR <= DAL;
	  ADRS_RF_DAE: REG_RF_DAE <= DAL;
	  ADRS_RF_ADS: REG_RF_ADS <= DAL;
	  ADRS_RKWC:   REG_RKWC   <= DAL;
	  ADRS_RKBA:   REG_RKBA   <= DAL;
	  ADRS_RKDA:   REG_RKDA   <= DAL;
	  default:;
	endcase	
  
//---------------------------------------------------------------------------
// Time sharing dual port ram
//---------------------------------------------------------------------------
//  wire pll_clk;
//  Gowin_rPLL pll_instance(
//				.clkout(pll_clk), //output clkout
//				.clkin(sys_clk) //input clkin
//				);

//  wire ram_clk = pll_clk;
  wire ram_clk = sys_clk;
  // address or data of memory should be latched to infer BSRAM
  reg [7:0] mem_hi[32767:0]; // higher 8bit (odd byte address)
  reg [7:0] mem_lo[32767:0]; // lower  8bit (even byte address)

  wire [15:0]  d_cpu_to_ram = DAL;
  wire [15:0]  d_ram_to_cpu = {dout0_hi[7:0], dout0_lo[7:0]};
  wire [7:0]   d_dma_to_ram;
  wire [7:0]   d_ram_to_dma = dma_address[0] ? dout1_hi[7:0]: dout1_lo[7:0];
  
  reg	      ram_select = 1'b1;

  always@(posedge ram_clk)
    ram_select <= ~ram_select;
  
  wire [14:0] wa0    = address[15:1];
  wire [14:0] wa1    = dma_address[15:1];
  reg [14:0]  dpwa; // word address for dual port memory
  always@(negedge ram_clk)
    dpwa <= ram_select ? wa0 : wa1;
  
  reg [7:0]   dout0_hi;
  reg [7:0]   dout0_lo;
  reg [7:0]   dout1_hi;
  reg [7:0]   dout1_lo;
  always@(posedge ram_clk)
    if(ram_select)
      {dout0_hi, dout0_lo} <= {mem_hi[dpwa], mem_lo[dpwa]};
    else
      {dout1_hi, dout1_lo} <= {mem_hi[dpwa], mem_lo[dpwa]};
  
  wire [7:0]  din0_hi  = d_cpu_to_ram[15:8];
  wire [7:0]  din0_lo  = d_cpu_to_ram[7:0];
  wire [7:0]  din1_hi  = d_dma_to_ram[7:0]; // dma data is 8bit 
  wire [7:0]  din1_lo  = d_dma_to_ram[7:0]; // dma data is 8bit 
  wire	      we0_hi   = write_memory_hi;
  wire	      we0_lo   = write_memory_lo;
  wire	      we1_hi   = dma_write &   dma_address[0];
  wire	      we1_lo   = dma_write & (~dma_address[0]);
  always@(posedge ram_clk)
    if(ram_select) begin
       if(we0_lo) mem_lo[dpwa] <= din0_lo;
       if(we0_hi) mem_hi[dpwa] <= din0_hi;
    end
    else begin
      if(we1_lo) mem_lo[dpwa] <= din1_lo;
      if(we1_hi) mem_hi[dpwa] <= din1_hi;
    end

//---------------------------------------------------------------------------
// ROM DATA
//---------------------------------------------------------------------------
`include "rom.v"

//---------------------------------------------------------------------------
// Interrupt
//---------------------------------------------------------------------------
  // interrupt levels  
  parameter LV_IRQ0 = 3'd4;
  parameter LV_IRQ1 = 3'd5;
  parameter LV_IRQ2 = 3'd6;
  parameter LV_IRQ3 = 3'd7;

//---------------------------------------------------------------------------
// unused IRQs
//---------------------------------------------------------------------------
// set unused IRQs(0,3) = 1 to unlit onboard LEDs
  assign {IRQ[0], IRQ[3]}  = 2'b11;
//assign {IRQ[0], IRQ[3]}  = 0;

//---------------------------------------------------------------------------
// Interrupt by TTY I/O
//---------------------------------------------------------------------------
  wire	      IRQ_ttyi = rx_data_ready & RCSR_ID;
  wire	      IRQ_ttyo = tx_interrupt  & XCSR_ID;

  parameter   VA_ttyi  = 16'o000060; // Interrupt vector address
  parameter   VA_ttyo  = 16'o000064; // Interrupt vector address
  wire [15:0] VA_IRQ1  = IRQ_ttyi ? VA_ttyi : VA_ttyo;

  assign      IRQ[1] = IRQ_ttyi | IRQ_ttyo;

  reg last_tx_ready;
  always @( posedge sys_clk )
    last_tx_ready <= tx_ready;
  
  reg tx_interrupt;
  always @( posedge sys_clk or negedge INIT_n)
    if( ~INIT_n)
      tx_interrupt <= 1'b0;
    else if( ~last_tx_ready & tx_ready) // posedge of tx_ready
      tx_interrupt <= 1'b1;
    else if( (address == ADRS_XCSR) || (address == ADRS_XBUF))
      tx_interrupt <= 1'b0;   // clear by access tor tx registers
    else if( ~tx_ready)
      tx_interrupt <= 1'b0;   // clear when tx is not ready

//---------------------------------------------------------------------------
// Interrupt by drum/disk ready
//---------------------------------------------------------------------------
// IRQ2(level 6)
  reg		 IRQ_RFRK;
  parameter	 VA_RF  = 16'o000204; // drum(RF)
  parameter	 VA_RK  = 16'o000220; // disk(RK)
  parameter	 LV_RFRK  = LV_IRQ2;
  wire [15:0]	 VA_IRQ2  = (devsel == DEV_RF) ? VA_RF : VA_RK;
  assign IRQ[2]           = IRQ_RFRK;

  // unused interrupt vector address
  wire [15:0]	 VA_IRQ0 = 16'o0;
  wire [15:0]	 VA_IRQ3 = 16'o0;
  
  wire	 ack_IRQ_RFRK = (aio_code == AIO_INTACK && irq_ack_level == LV_RFRK);
  wire	 RF_INT_ENABLE = REG_RF_DCS[6];
  wire	 RK_INT_ENABLE = REG_RKCS[6];
	 
  reg	 last_RFRK_READY;
  wire	 posedge_RFRK_READY = ((~last_RFRK_READY) & RFRK_READY);
  always @( posedge sys_clk )
    last_RFRK_READY <= RFRK_READY;
  
  always @( posedge sys_clk or posedge ack_IRQ_RFRK or negedge INIT_n)
    if( ~INIT_n )
      IRQ_RFRK <= 0;
    else if ( ack_IRQ_RFRK)
      IRQ_RFRK <= 0;
    else if( posedge_RFRK_READY )
      IRQ_RFRK <= (devsel == DEV_RF) ? RF_INT_ENABLE:
		  (devsel == DEV_RK) ? RK_INT_ENABLE:
		  0; // this cannot occur

//---------------------------------------------------------------------------
// EVENT (timer) 
//---------------------------------------------------------------------------
  assign EVENT_n = ~IRQ_timer; // EVENT_n(level 6, address=0100)
  wire EVENT_ACK = ((aio_code == AIO_GPWRITE) && (gpcode == 9'o100));

//---------------------------------------------------------------------------
// KW11-L line time clock
//---------------------------------------------------------------------------
  parameter   ADRS_KW11L  = 16'o177546;
  reg	      REG_KW11L_INT_ENABLE;  // bit 6
  reg	      REG_KW11L_INT_MONITOR; // bit 7
  wire [15:0] REG_KW11L = {8'b0, 
			   REG_KW11L_INT_MONITOR, REG_KW11L_INT_ENABLE,
			   6'b0};
  wire	      IRQ_timer = REG_KW11L_INT_ENABLE & REG_KW11L_INT_MONITOR;

  reg	     clk_60Hz = 0;
  reg [19:0] cnt_8333us;
  always @(posedge sys_clk)
    if(cnt_8333us == SYSCLK_FRQ/120) begin
       cnt_8333us <= 0;
       clk_60Hz   <= ~clk_60Hz;
    end else 
      cnt_8333us <= cnt_8333us + 1'b1;

  always @(negedge SCTL_n or negedge clk_60Hz
	   or posedge EVENT_ACK or negedge INIT_n)
    if( ~INIT_n ) begin
       REG_KW11L_INT_ENABLE <= 0;
       REG_KW11L_INT_MONITOR <= 1'b1; // set on processor INIT
    end
    else if(EVENT_ACK)
      REG_KW11L_INT_MONITOR <= 0;
    else if(~SCTL_n) begin
       if ( (address == ADRS_KW11L) & bus_write) begin
	  REG_KW11L_INT_ENABLE  <= DAL[6];
	  REG_KW11L_INT_MONITOR <= 0;
       end
    end
    else
      REG_KW11L_INT_MONITOR <= 1'b1;
//      REG_KW11L_INT_MONITOR <= ~REG_KW11L_INT_MONITOR;
  
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
// SD memory Hard disk emulator
//---------------------------------------------------------------------------
  wire	      disk_ready;
  reg	      disk_read;
  reg	      disk_write;
  reg	      disk_seek;
//  reg [23:0]  disk_block_address;
  reg [12:0]  disk_block_address;
  wire [9:0]  disk_buf_address;
  wire [15:0] dma_address;
  reg [15:0]  dma_start_address;
  reg [15:0]  dma_wordcount;
  wire [5:0]  sd_state;
  wire [3:0]  sd_error;

  sdhd #(
	      .SYS_FRQ(27_000_000),
	      .MEM_FRQ(400_000)
    ) sdhd_inst
  (
   .i_clk                (sys_clk),
   .i_reset_n            (RESET_n),
   .i_sd_miso            (sd_miso),
   .o_sd_mosi            (sd_mosi),
   .o_sd_cs_n            (sd_cs_n),
   .o_sd_clk             (sd_clk),
   .o_disk_ready         (disk_ready),
   .i_disk_read          (disk_read),
   .i_disk_write         (disk_write),
   .i_disk_seek          (disk_seek),
   .i_disk_block_address ({11'b0, disk_block_address[12:0]}),
   .o_dma_address        (dma_address),
   .i_dma_start_address  (dma_start_address),
   .i_dma_wordcount      (dma_wordcount),
   .i_dma_data           (d_ram_to_dma),
   .o_dma_data           (d_dma_to_ram),
   .o_dma_write          (dma_write),
   .o_sd_state           (sd_state),
   .o_sd_error           (sd_error)
   );

//---------------------------------------------------------------------------
// for debug
//---------------------------------------------------------------------------
  reg [7:0]		LED_R;
  reg [7:0]		LED_G;
  reg [7:0]		LED_B;
  
  reg [25:0]		cnt_500ms;
  reg			clk_1Hz;
     
  reg			dbg_trg;
  assign LED5_n = dbg_trg;

  reg [15:0]		REG_DBG0;
  reg [15:0]		REG_DBG1;
  reg [15:0]		REG_DBG2;
  reg			REG_DBG_CP;
  parameter	ADRS_DBG0 = 16'o177760;
  parameter	ADRS_DBG1 = 16'o177762;
  parameter	ADRS_DBG2 = 16'o177764;
  always @(negedge SCTL_n or negedge RESET_n)
    if( ~RESET_n ) begin
       REG_DBG0 <= 16'o177775;
       REG_DBG1 <= 16'o177775;
       REG_DBG2 <= 16'o177775;
    end
    else if(bus_write)
      case (address)
	ADRS_DBG0: REG_DBG0 <= DAL;
	ADRS_DBG1: REG_DBG1 <= DAL;
	ADRS_DBG2: REG_DBG2 <= DAL;
	default:;
      endcase
  
  always @(posedge sys_clk or negedge RESET_n)
    if( ~RESET_n )
      REG_DBG_CP <= 0;
    else if( address == ADRS_XCSR) // degate HALT when console ODT starts
      dbg_trg <= 0; 
//    else if( ((dbg_reg4 == 16'o004720) | sw2) & aio_iread )
//      dbg_trg <= 1'b1;
    else if( (address == REG_DBG0) & aio_iread )
      dbg_trg <= 1'b1;
    else if( (address == REG_DBG1) & aio_iread) begin
       REG_DBG_CP <= 1'b1;
    end
    else if( (address == REG_DBG2) & aio_iread  & REG_DBG_CP)
      dbg_trg <= 1'b1;

  ws2812 onboard_rgb_led(.clk(sys_clk), .we(1'b1), .sout(LED_RGB),
			 .r(LED_R), .g(LED_G), .b(LED_B));

  always @(posedge sys_clk)
    if(cnt_500ms == SYSCLK_FRQ/2) begin
       cnt_500ms <= 0;
       clk_1Hz = ~clk_1Hz;
    end else 
      cnt_500ms <= cnt_500ms + 1'b1;

  reg [5:0] event_count;
  reg	    event_monitor;
  always @(posedge EVENT_ACK or negedge INIT_n)
    if( ~INIT_n )
      {event_count, event_monitor} <= 0;
    else if(event_count == 6'd30) begin
       event_count <= 0;
       event_monitor <= ~event_monitor;
    end
    else
      event_count <= event_count + 1'd1;

  always @(posedge sys_clk)
    if(~RESET_n) begin
      {LED_R, LED_G, LED_B} <= 24'h00_00_00;
    end
    else begin
       LED_R <= rx_data_ready ? 8'h10:
		~sd_mosi ? 8'h20:
		8'h00;
       LED_G <= ~tx_ready ? 8'h10:
		~sd_miso ? 8'h20:
		8'h00;
       LED_B <= event_monitor ? 8'h10: 8'h00;
//       LED_B <= clk_1Hz ? 8'h10 : 8'h00;
    end

`ifdef USE_GPIOUART_DEBUG
  // debug_print
  // print dbg_regw:dbg_reg0,dbg_reg1,dbg_reg2,dbg_reg3,dbg_reg4

  function [7:0] itoh(input [3:0] x);
     case (x)
       4'h0: itoh="0"; 4'h1: itoh="1"; 4'h2: itoh="2"; 4'h3: itoh="3";
       4'h4: itoh="4"; 4'h5: itoh="5"; 4'h6: itoh="6"; 4'h7: itoh="7";
       4'h8: itoh="8"; 4'h9: itoh="9"; 4'ha: itoh="a"; 4'hb: itoh="b";
       4'hc: itoh="c"; 4'hd: itoh="d"; 4'he: itoh="e"; 4'hf: itoh="f";
     endcase
  endfunction
  function [7:0] itoh0(input [15:0] x); itoh0 = itoh(x[3:0]);   endfunction
  function [7:0] itoh1(input [15:0] x); itoh1 = itoh(x[7:4]);   endfunction
  function [7:0] itoh2(input [15:0] x); itoh2 = itoh(x[11:8]);  endfunction
  function [7:0] itoh3(input [15:0] x); itoh3 = itoh(x[15:12]); endfunction

  function [7:0] itoo(input [2:0] x);
     case (x)
       4'h0: itoo="0"; 4'h1: itoo="1"; 4'h2: itoo="2"; 4'h3: itoo="3";
       4'h4: itoo="4"; 4'h5: itoo="5"; 4'h6: itoo="6"; 4'h7: itoo="7";
     endcase
  endfunction
  function [7:0] itoo0(input [15:0] x); itoo0 = itoo(x[2:0]);  endfunction
  function [7:0] itoo1(input [15:0] x); itoo1 = itoo(x[5:3]);  endfunction
  function [7:0] itoo2(input [15:0] x); itoo2 = itoo(x[8:6]);  endfunction
  function [7:0] itoo3(input [15:0] x); itoo3 = itoo(x[11:9]); endfunction
  function [7:0] itoo4(input [15:0] x); itoo4 = itoo(x[14:12]);endfunction
  function [7:0] itoo5(input [15:0] x); itoo5 = itoo({2'b0, x[15]});endfunction

  reg [15:0] dbg_regt;
  reg [15:0] dbg_regw;
  reg [15:0] dbg_reg0;
  reg [15:0] dbg_reg1;
  reg [15:0] dbg_reg2;
  reg [15:0] dbg_reg3;
  reg [15:0] dbg_reg4;
  reg [7:0]  dbg_pstate;
  reg	     dbg_ptrg = 0;
  reg	     dbg_ptrg_last = 0;
  reg [7:0]  dbg_pbuf[255:0];
  reg [6:0]  dbg_pcnt;
  parameter  DBG_PSTATE_IDLE  = 8'd255;
  parameter  DBG_PSTATE_PRINT = 8'd254;
  parameter  DBG_PSTATE_WAIT  = 8'd253;
  reg	     dbg_print;
  wire	     dbg_clear = (dbg_pcnt == 7'd2);
  always @(posedge sys_clk or negedge RESET_n)
    if(~RESET_n) begin
       dbg_pstate <= DBG_PSTATE_IDLE;
    end
    else
      case (dbg_pstate)
	DBG_PSTATE_IDLE:
	  if( dbg_print ) begin
	     dbg_pstate <= 8'd0;
	     dbg_pcnt   <= 8'd0;
	  end
	  else
	    dbg_pstate <= DBG_PSTATE_IDLE;
	8'd0 : {dbg_pbuf[0 ], dbg_pstate} <= {itoh3(dbg_regt), 8'd1 };
	8'd1 : {dbg_pbuf[1 ], dbg_pstate} <= {itoh2(dbg_regt), 8'd2 };
	8'd2 : {dbg_pbuf[2 ], dbg_pstate} <= {itoh1(dbg_regt), 8'd3 };
	8'd3 : {dbg_pbuf[3 ], dbg_pstate} <= {itoh0(dbg_regt), 8'd4 };
	8'd4 : {dbg_pbuf[4 ], dbg_pstate} <= {" ",             8'd5 };
	8'd5 : {dbg_pbuf[5 ], dbg_pstate} <= {dbg_regw[15:8],  8'd6 };
	8'd6 : {dbg_pbuf[6 ], dbg_pstate} <= {dbg_regw[7:0],   8'd7 };
	8'd7 : {dbg_pbuf[7 ], dbg_pstate} <= {",",             8'd8 };
	8'd8 : {dbg_pbuf[8 ], dbg_pstate} <= {itoo5(dbg_reg0), 8'd9 };
	8'd9 : {dbg_pbuf[9 ], dbg_pstate} <= {itoo4(dbg_reg0), 8'd10};
	8'd10: {dbg_pbuf[10], dbg_pstate} <= {itoo3(dbg_reg0), 8'd11};
	8'd11: {dbg_pbuf[11], dbg_pstate} <= {itoo2(dbg_reg0), 8'd12};
	8'd12: {dbg_pbuf[12], dbg_pstate} <= {itoo1(dbg_reg0), 8'd13};
	8'd13: {dbg_pbuf[13], dbg_pstate} <= {itoo0(dbg_reg0), 8'd14};
	8'd14: {dbg_pbuf[14], dbg_pstate} <= {",",             8'd15};
	8'd15: {dbg_pbuf[15], dbg_pstate} <= {itoo5(dbg_reg1), 8'd16};
	8'd16: {dbg_pbuf[16], dbg_pstate} <= {itoo4(dbg_reg1), 8'd17};
	8'd17: {dbg_pbuf[17], dbg_pstate} <= {itoo3(dbg_reg1), 8'd18};
	8'd18: {dbg_pbuf[18], dbg_pstate} <= {itoo2(dbg_reg1), 8'd19};
	8'd19: {dbg_pbuf[19], dbg_pstate} <= {itoo1(dbg_reg1), 8'd20};
	8'd20: {dbg_pbuf[20], dbg_pstate} <= {itoo0(dbg_reg1), 8'd21};
	8'd21: {dbg_pbuf[21], dbg_pstate} <= {",",             8'd22};
	8'd22: {dbg_pbuf[22], dbg_pstate} <= {itoo5(dbg_reg2), 8'd23};
	8'd23: {dbg_pbuf[23], dbg_pstate} <= {itoo4(dbg_reg2), 8'd24};
	8'd24: {dbg_pbuf[24], dbg_pstate} <= {itoo3(dbg_reg2), 8'd25};
	8'd25: {dbg_pbuf[25], dbg_pstate} <= {itoo2(dbg_reg2), 8'd26};
	8'd26: {dbg_pbuf[26], dbg_pstate} <= {itoo1(dbg_reg2), 8'd27};
	8'd27: {dbg_pbuf[27], dbg_pstate} <= {itoo0(dbg_reg2), 8'd28};
	8'd28: {dbg_pbuf[28], dbg_pstate} <= {",",             8'd29};
	8'd29: {dbg_pbuf[29], dbg_pstate} <= {itoo5(dbg_reg3), 8'd30};
	8'd30: {dbg_pbuf[30], dbg_pstate} <= {itoo4(dbg_reg3), 8'd31};
	8'd31: {dbg_pbuf[31], dbg_pstate} <= {itoo3(dbg_reg3), 8'd32};
	8'd32: {dbg_pbuf[32], dbg_pstate} <= {itoo2(dbg_reg3), 8'd33};
	8'd33: {dbg_pbuf[33], dbg_pstate} <= {itoo1(dbg_reg3), 8'd34};
	8'd34: {dbg_pbuf[34], dbg_pstate} <= {itoo0(dbg_reg3), 8'd35};
	8'd35: {dbg_pbuf[35], dbg_pstate} <= {",",             8'd36};
	8'd36: {dbg_pbuf[36], dbg_pstate} <= {itoo5(dbg_reg4), 8'd37};
	8'd37: {dbg_pbuf[37], dbg_pstate} <= {itoo4(dbg_reg4), 8'd38};
	8'd38: {dbg_pbuf[38], dbg_pstate} <= {itoo3(dbg_reg4), 8'd39};
	8'd39: {dbg_pbuf[39], dbg_pstate} <= {itoo2(dbg_reg4), 8'd40};
	8'd40: {dbg_pbuf[40], dbg_pstate} <= {itoo1(dbg_reg4), 8'd41};
	8'd41: {dbg_pbuf[41], dbg_pstate} <= {itoo0(dbg_reg4), 8'd42};
	8'd42: {dbg_pbuf[42], dbg_pstate} <= {8'h0d,           8'd43}; // \r
	8'd43: {dbg_pbuf[43], dbg_pstate} <= {8'h0a,           8'd44}; // \n
	8'd44: {dbg_pbuf[44], dbg_pstate} <= {8'b0, DBG_PSTATE_PRINT};
	DBG_PSTATE_PRINT:
	  if( dbg_pbuf[dbg_pcnt] == 8'b0)
	    dbg_pstate <= DBG_PSTATE_IDLE;
	  else if( dbg_tx_ready ) begin
	     dbg_tx_data <= dbg_pbuf[dbg_pcnt];
	     dbg_tx_send <= 1;
	     dbg_pcnt <= dbg_pcnt + 1'd1;
	     dbg_pstate <= DBG_PSTATE_WAIT;
	  end
	  else
	    dbg_pstate <= DBG_PSTATE_PRINT;

	DBG_PSTATE_WAIT:
	  if( ~dbg_tx_ready) begin
	     dbg_tx_send <= 0;
	     dbg_pstate <= DBG_PSTATE_PRINT;
	  end
	  else
	    dbg_pstate <= DBG_PSTATE_WAIT;

	// dummy to avoid warning
	default: dbg_pbuf[dbg_pstate] <= dbg_pbuf[dbg_pstate];
      endcase
  
  reg [11:0] cnt_100us;
  reg [15:0] dbg_time;
  always @(posedge sys_clk or negedge INIT_n)
    if(~INIT_n)
      {cnt_100us, dbg_time} <= 0;
    else if(cnt_100us == (SYSCLK_FRQ / 1000 / 1000)*100 -1) begin // 100us
       cnt_100us <= 0;
       dbg_time <= dbg_time + 1'd1;
    end
    else
      cnt_100us <= cnt_100us + 1'd1;

  wire [15:0] REG_RF_DCS_R ={8'b0, RFRK_READY, REG_RF_DCS[6:1], 1'b0};
  wire [15:0] REG_RKCS_R   ={2'b00, REG_RKCS[13:8], RFRK_READY, REG_RKCS[6:0]};
  wire [15:0] REG_RKDS_R   ={8'b000_01001, RFRK_READY, RFRK_READY,
			     2'b01, REG_RKDA[3:0]};
  
  always @(posedge sys_clk)
    if (dbg_clear)
      dbg_print<= 1'b0;
//    else if ((address == 16'o16756) & aio_iread ) begin
    else if (IRQ_RFRK & (devsel == DEV_RF)) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "i0";
       dbg_reg0 <= REG_RF_DCS_R;
       dbg_reg1 <= REG_RF_WC;
       dbg_reg2 <= REG_RF_CMA;
       dbg_reg3 <= REG_RF_DAR;
       dbg_reg4 <= REG_RF_DAE;
       dbg_print<= 1'b1;
    end
//    else if ((address == 16'o17000) & aio_iread ) begin
    else if (IRQ_RFRK & (devsel == DEV_RK)) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "i1";
       dbg_reg0 <= REG_RKCS_R;
       dbg_reg1 <= REG_RKWC;
       dbg_reg2 <= REG_RKBA;
       dbg_reg3 <= REG_RKDA;
       dbg_reg4 <= REG_RKDS_R;
       dbg_print<= 1'b1;
    end
    else if ((address == 16'o173000) & aio_iread ) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "bt";
       dbg_reg0 <= address;
       dbg_reg1 <= 0;
       dbg_reg2 <= 0;
       dbg_reg3 <= 0;
       dbg_reg4 <= 0; 
       dbg_print<= 1'b1;
    end
    else if ((address == ADRS_RF_DCS) & bus_write & disk_read) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "R0";
       dbg_reg0 <= REG_RF_DCS;
       dbg_reg1 <= REG_RF_WC_BAK;
       dbg_reg2 <= REG_RF_CMA_BAK;
       dbg_reg3 <= REG_RF_DAR_BAK;
       dbg_reg4 <= REG_RF_DAE_BAK;
       dbg_print<= 1'b1;
    end
    else if ((address == ADRS_RF_DCS) & bus_write & disk_write) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "W0";
       dbg_reg0 <= REG_RF_DCS;
       dbg_reg1 <= REG_RF_WC_BAK;
       dbg_reg2 <= REG_RF_CMA_BAK;
       dbg_reg3 <= REG_RF_DAR_BAK;
       dbg_reg4 <= REG_RF_DAE_BAK;
       dbg_print<= 1'b1;
    end
    else if ((address == ADRS_RKCS) & bus_write & disk_read) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "R1";
       dbg_reg0 <= REG_RKCS;
       dbg_reg1 <= REG_RKWC_BAK;
       dbg_reg2 <= REG_RKBA_BAK;
       dbg_reg3 <= REG_RKDA;
       dbg_reg4 <= 0;
       dbg_print<= 1'b1;
    end
    else if ((address == ADRS_RKCS) & bus_write & disk_write) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "W1";
       dbg_reg0 <= REG_RKCS;
       dbg_reg1 <= REG_RKWC_BAK;
       dbg_reg2 <= REG_RKBA_BAK;
       dbg_reg3 <= REG_RKDA;
       dbg_reg4 <= 0;
       dbg_print<= 1'b1;
    end
    else if ((address == ADRS_RKCS) & bus_write & disk_seek) begin
       dbg_regt <= dbg_time;
       dbg_regw <= "S1";
       dbg_reg0 <= REG_RKCS_R;
       dbg_reg1 <= REG_RKWC_BAK;
       dbg_reg2 <= REG_RKBA_BAK;
       dbg_reg3 <= REG_RKDA;
       dbg_reg4 <= REG_RKDS_R;
       dbg_print<= 1'b1;
    end

  
  parameter	 UART_BPS_DBG    =       115_200; //Hz (for teraterm)
//  parameter	 UART_BPS_DBG    =     1_700_000; //Hz (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     2_700_000; //Hz (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     6_750_000; //Hz (27_000_000 / 4)
//  parameter	 UART_BPS_DBG    =    13_500_000; //Hz (27_000_000 / 2)
  reg [7:0]	 dbg_tx_data;
  reg		 dbg_tx_send;
  wire		 dbg_tx_ready;
  wire		 dbg_tx;
  
  uart_tx#
    (
     .CLK_FRQ(SYSCLK_FRQ),
     .BAUD_RATE(UART_BPS_DBG)
     ) uart_tx_inst_dbg
      (
       .clk           (sys_clk),
       .reset_n       (RESET_n),
       .tx_data       (dbg_tx_data),
       .tx_send       (dbg_tx_send),
       .tx_ready      (dbg_tx_ready),
       .tx_out        (dbg_tx)
       );
`endif // USE_GPIOUART_DEBUG
  
endmodule
