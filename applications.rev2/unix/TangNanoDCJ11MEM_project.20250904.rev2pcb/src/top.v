//---------------------------------------------------------------------------
// TangNanoDCJ11MEM
// Memory system and peripherals on TangNano20K for DEC DCJ11 (PDP11)
// for PCB rev.2.0
//
// version 20250904.pcb2
//
// by Ryo Mukai (https://github.com/ryomuk)
//
// The emulatior of the following peripherals are implemented
// for running the UNIX first edition (UNIX V1).
// - KL11 TTY
// - RF11 drum
// - RK11 disk
// - KW11-L line time clock
// - KE11-A extended arithmetic unit
//
// 2024/06/09: - Hard disk (RF11 and RK11) emulator (sdhd.v) implemented
// 2024/06/10: - KW11-L emulator implemented
// 2024/06/11: - KE11-A emulator implemented
// 2024/06/24: - initial version (very unstable)
// 2024/07/10: - separate command reception for RF11 and RK11
// 2024/07/13: - IRQ bug fixed
// 2024/07/14: - debug register address changed
// 2024/07/15: - Stretched cycle installed for RF, RK, RE11
//               - CONT_n is assigned to LED3.
//             - IRQ2 and IRQ3 are removed. LED2_n is free.
//             - Memory sytem modified to single port RAM
// 2024/07/19: - Relatively stable compared to previous versions.
// 2024/07/27: - Stabilized disk ready logic for IRQ_RFRK (dirty workaround)
//             - Bufferd TX (uart.v) implemented
//             - Some features for UNIX V6 Experiments
//               - ABORT_n installed (pin is LED[2]_n)
//                 write to 160000-167777 or read 177700 causes bus error
//               - Make RAM 28KW (160000-177777 is a ROM area)
//               - boot from RK0 disk (174000g)
// 2024/07/28: - read 160000-160077 causes bus error
// 2024/07/29: - ABORT_n changed to tri-state
//             - bus error condition changed
//                 read 170000-170077 or 177700 causes bus error
// 2024/07/30: - multiple RK disks supported
//
// Major update
// 2025/08/26: - modified to use CLK2 (GPIO_RX is removed)
//---------------------------------------------------------------------------

// Commenting out the following `define makes the GPIO mirror the console,
// but the timing constraints may need to be modified.
`define USE_GPIOUART_DEBUG

module top(
    input	 sw1,
    input	 sw2,
    input	 sys_clk27, // 27MHz system clock
    input	 usb_rx,
    output	 usb_tx,

    input	 CLK2,
    output	 GPIO_TX,

    output	 sd_clk,
    output	 sd_mosi, 
    input	 sd_miso,
    output	 sd_cs_n,
	   
    inout [15:0] DAL,
    input [3:0]	 AIO,
    output	 IRQ0,
    output	 IRQ1,
    inout	 ABORT_n,
    output	 EVENT_n,
    input	 INIT_SW,
    output	 INIT_n, // CPU reset signal
    input	 BUFCTL_n,
    input	 ALE_n,
    input	 SCTL_n,
    output	 CONT_n,
    output	 HALT,

    output	 LED_RGB
    );

//---------------------------------------------------------------------------
// Clock signals
//---------------------------------------------------------------------------
  // system clock
  parameter	 SYS_CLK_FRQ  = 18_000_000; //Hz
  wire		 sys_clk      = CLK2;

  // CPU clock stops while INIT, 
  // so another clock is required for the initialization
  parameter	 INIT_CLK_FRQ = 27_000_000; // Hz
  wire		 init_clk     = sys_clk27;
  
  // clock for sdhd module
  parameter	 SDHD_CLK_FRQ = SYS_CLK_FRQ;
  wire		 sdhd_clk     = sys_clk;

  // clock for RGB LED (must be 27MHz for current implementation)
  parameter	 LED_CLK_FRQ  = 27_000_000;
  wire		 led_clk      = sys_clk27;

//---------------------------------------------------------------------------
// UART BPS
//---------------------------------------------------------------------------
//  parameter	 UART_BPS    =        110; //Hz (needs appropriate serial IF)
//  parameter	 UART_BPS    =        300; //Hz (minimum speed of FT232)
//  parameter	 UART_BPS    =       1200; //Hz (minimum speed of TangNano USB)
//  parameter	 UART_BPS    =       9600; //Hz
//  parameter	 UART_BPS    =      38400; //Hz
  parameter	 UART_BPS    =     115200; //Hz

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
    parameter RKCS_CRESET = 3'b000;  // [3:1] 'b0001 = 'o001
    parameter RKCS_WRITE  = 3'b001;  // [3:1] 'b0011 = 'o003
    parameter RKCS_READ   = 3'b010;  // [3:1] 'b0101 = 'o005
    parameter RKCS_SEEK   = 3'b100;  // [3:1] 'b1001 = 'o011
    parameter RKCS_DRESET = 3'b110;  // [3:1] 'b1101 = 'o015
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
  reg [15:0] REG_KE_AC_OUT;
  reg [15:0] REG_KE_MQ;
  reg [15:0] REG_KE_MQ_OUT;
  reg [15:0] REG_KE_X;
  reg [7:0]  REG_KE_SC;
  reg [7:0]  REG_KE_SC_OUT;
  wire [7:0] REG_KE_SR;
  reg	     REG_KE_SR0;  // SR[0]

//---------------------------------------------------------------------------
// Console / KL11 registers
//---------------------------------------------------------------------------
  parameter ADRS_RCSR = 16'o177560; // Console read status (aka TKS)
  parameter ADRS_RBUF = 16'o177562; // Console read buffer (aka TKB)
  parameter ADRS_XCSR = 16'o177564; // Console send status (aka TPS)
  parameter ADRS_XBUF = 16'o177566; // Console send buffer (aka TPB)
  parameter ADRS_SWR  = 16'o177570; // Console Switch Register

  reg		 RCSR_ID;                    // bit6
  wire		 RCSR_DONE  = rx_data_ready; // bit7
  reg		 XCSR_ID;                    // bit6
  wire		 XCSR_READY = tx_ready ;     // bit7
  wire [7:0]	 RBUF       = rx_data;       // DATA(=bit7..0)
  wire [7:0]	 XBUF       = tx_data;       // DATA(=bit7..0)

  reg [15:0]	 REG_SWR;
  
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
// GP codes
//---------------------------------------------------------------------------
// GP Read
  parameter GP_PUP            = 8'o000; // Reads the power-up mode
  parameter GP_FPA            = 8'o001; // Reads FPA data
  parameter GP_PUP2           = 8'o002; // Reads the power-up mode, clear FPS
// GP Write
  parameter GP_BUSRESET       = 8'o014; // Asserts bus reset signal
  parameter GP_EXIT_ODT       = 8'o034; // Signals exit from console ODT
  parameter GP_ACK_EVENT      = 8'o100; // Acknowledges EVENT
  parameter GP_NEG_BUSRESET   = 8'o214; // Negates bus reset signal
  parameter GP_TEST1          = 8'o220; // Microdiagnostic test 1 passed
  parameter GP_TEST2          = 8'o224; // Microdiagnostic test 2 passed
  parameter GP_TEST3          = 8'o230; // Microdiagnostic test 3 passed
  parameter GP_ENTRY_ODT      = 8'o234; // Signals entry into console ODT
  
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
  assign uart_rx = usb_rx;

`ifdef USE_GPIOUART_DEBUG
  assign GPIO_TX = dbg_tx;
`else
  assign GPIO_TX = uart_tx;
`endif // USE_GPIOUART_DEBUG
  
//---------------------------------------------------------------------------
// Aliases
//---------------------------------------------------------------------------
  wire [15:0] address = DAL_latched;
  wire [7:0]  gpcode  = DAL_latched[7:0];
  wire [2:0]  irq_ack_level; // IRQ level acknowledged

  assign irq_ack_level = (DAL_latched[3:0] == 4'b0001) ? 3'd4: // IRQ0
			 (DAL_latched[3:0] == 4'b0010) ? 3'd5: // IRQ1
			 (DAL_latched[3:0] == 4'b0100) ? 3'd6: // IRQ2
			 (DAL_latched[3:0] == 4'b1000) ? 3'd7: // IRQ3
			 0;
			 
  wire bus_read           = (aio_read  && (BUFCTL_n == 1'b0));
  wire bus_write          = (aio_write && (BUFCTL_n == 1'b1));
  wire vec_read           = (aio_code == AIO_INTACK) & (BUFCTL_n == 1'b0);
  
  wire [3:0] aio_code     = AIO_latched;
  wire aio_write          = (aio_code == AIO_BUSBYTEWRITE) |
                            (aio_code == AIO_BUSWORDWRITE);
  wire aio_write_lowbyte  = (aio_code == AIO_BUSBYTEWRITE) & ~address[0];
  wire aio_write_highbyte = (aio_code == AIO_BUSBYTEWRITE) & address[0];
  wire aio_read           = (aio_code == AIO_IREADRQ) |
                            (aio_code == AIO_INTACK)  |
                            (aio_code == AIO_RMWNBL)  |
                            (aio_code == AIO_RMWBL)   |
                            (aio_code == AIO_DREAD)   |
                            (aio_code == AIO_IREADDM);
  wire aio_iread          = (aio_code == AIO_IREADRQ) |
                            (aio_code == AIO_IREADDM);
  wire aio_iread_dm       = (aio_code == AIO_IREADDM);

//---------------------------------------------------------------------------
// reset button and power on reset
//---------------------------------------------------------------------------
  reg		 RESET_n; // Reset for memory system

// reset for UART and SD memory
  reg [27:0]	 reset_cnt = 0;
  parameter	 RESET_WIDTH = (INIT_CLK_FRQ / 1000) * 250; // 250ms
  always @(posedge init_clk)
    if( sw1 ) 
      {RESET_n, reset_cnt} <= 0;
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
  parameter	 INIT_WIDTH = (INIT_CLK_FRQ / 1000) * 250; // 250ms
  always @(posedge init_clk)
    if(INIT_SW)
      {reg_INIT_n, init_cnt} <= 0;
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
  wire [15:0] PUP_ODT    = 16'b0000000_0_0000_0_01_1;

  // Power-up to 173000
  wire [15:0] PUP_173000 = 16'b0000000_0_0000_0_10_1;

  // Power-up to User Program (xxx000, lower 9bits are 0)
  wire [15:0] PUP_BOOTADDRESS  = 16'o173000; // boot address(Octal)
  wire [15:0] PUP_USER   = {PUP_BOOTADDRESS[15:9], 9'b0_0000_0_11_1};

  wire [15:0] PUP_CONF = sw2 ? PUP_USER : PUP_ODT;
//  wire [15:0] PUP_CONF = PUP_ODT;
//  wire [15:0] PUP_CONF = PUP_173000;
//  wire [15:0] PUP_CONF = PUP_USER;

//---------------------------------------------------------------------------
// Microdiagnostic test on the power-up sequence
//---------------------------------------------------------------------------
  reg diag_test1 = 0;
  reg diag_test2 = 0;
  reg diag_test3 = 0;
  always @(negedge SCTL_n)
    if (aio_code == AIO_GPWRITE)
      if(gpcode == GP_TEST1)
	diag_test1 <= 1'b1;
      else if (gpcode == GP_TEST2)
	diag_test2 <= 1'b1;
      else if (gpcode == GP_TEST3)
	diag_test3 <= 1'b1;

//---------------------------------------------------------------------------
// Memory and IO
//---------------------------------------------------------------------------
  assign DAL = BUFCTL_n ? 16'bzzzz_zzzz_zzzz_zzzz :
       (address == ADRS_RCSR) ? {8'b0, RCSR_DONE, RCSR_ID, 6'b0}:
       (address == ADRS_RBUF) ? {8'b0, RBUF}:
       (address == ADRS_XCSR) ? {8'b0, XCSR_READY, XCSR_ID, 6'b0}:
       (address == ADRS_XBUF) ? {8'b0, XBUF}:
       (address == ADRS_SWR)  ? REG_SWR:
       (address == ADRS_RF_DCS) ? {8'b0, RF_READY, REG_RF_DCS[6:1], 1'b0}:
       (address == ADRS_RF_WC)  ? REG_RF_WC:
       (address == ADRS_RF_CMA) ? REG_RF_CMA:
       (address == ADRS_RF_DAR) ? REG_RF_DAR:
       (address == ADRS_RF_DAE) ? REG_RF_DAE:
       (address == ADRS_RF_ADS) ? REG_RF_ADS:
       (address == ADRS_RKDS) ? {8'b000_01001,
				 RK_READY, RK_READY,
				 2'b01, REG_RKDA[3:0]}:
       (address == ADRS_RKER) ? 16'b0: // error register not implemented
       (address == ADRS_RKCS) ? {2'b00, REG_RKCS[13:8],
				 RK_READY, REG_RKCS[6:0]}:
       (address == ADRS_RKWC) ? REG_RKWC:
       (address == ADRS_RKBA) ? REG_RKBA:
       (address == ADRS_RKDA) ? REG_RKDA:
       (address == ADRS_KW11L)  ? REG_KW11L:
       (address == ADRS_KE_DIV) ? 16'b0:
       (address == ADRS_KE_AC ) ? REG_KE_AC_OUT:
       (address == ADRS_KE_MQ ) ? REG_KE_MQ_OUT:
       (address == ADRS_KE_MUL) ? 16'b0:
       (address == ADRS_KE_SC ) ? {REG_KE_SR, REG_KE_SC_OUT}:
       (address == ADRS_KE_SR ) ? {REG_KE_SR, REG_KE_SC_OUT}:
       (address == ADRS_KE_NOR) ? REG_KE_SC_OUT: // read NOR returns SC
       (address == ADRS_KE_LSH) ? 16'b0:
       (address == ADRS_KE_ASH) ? 16'b0:
       (aio_code == AIO_GPREAD && gpcode == GP_PUP)  ? PUP_CONF :
       (aio_code == AIO_GPREAD && gpcode == GP_PUP2) ? PUP_CONF :
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ0) ? VA_IRQ0:
       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ1) ? VA_IRQ1:
//       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ2) ? VA_IRQ2:
//       (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ3) ? VA_IRQ3:
       (address == ADRS_DBG0) ? REG_DBG0:
       (address == ADRS_DBG1) ? REG_DBG1:
       (address == ADRS_DBG2) ? REG_DBG2:
       (address == ADRS_TRACE0) ? REG_TRACE[0]:
       (address == ADRS_TRACE1) ? REG_TRACE[1]:
       (address == ADRS_TRACE2) ? REG_TRACE[2]:
       (address == ADRS_TRACE3) ? REG_TRACE[3]:
       (address == ADRS_TRACE4) ? REG_TRACE[4]:
       (address == ADRS_TRACE5) ? REG_TRACE[5]:
       (address == ADRS_TRACE6) ? REG_TRACE[6]:
       (address == ADRS_TRACE7) ? REG_TRACE[7]:
       (address == ADRS_TRACE8) ? REG_TRACE[8]:
       (address == ADRS_TRACE9) ? REG_TRACE[9]:
       (address == ADRS_TRACE10) ? REG_TRACE[10]:
       (address == ADRS_TRACE11) ? REG_TRACE[11]:
       (address == ADRS_TRACE12) ? REG_TRACE[12]:
       (address == ADRS_TRACE13) ? REG_TRACE[13]:
       (address == ADRS_TRACE14) ? REG_TRACE[14]:
       (address == ADRS_TRACE15) ? REG_TRACE[15]:
       (address == ADRS_TRACE16) ? REG_TRACE[16]:
       (address == ADRS_TRACE17) ? REG_TRACE[17]:
       (address == ADRS_TRACE18) ? REG_TRACE[18]:
       (address == ADRS_TRACE19) ? REG_TRACE[19]:
       (address == ADRS_TRACE20) ? REG_TRACE[20]:
       (address == ADRS_TRACE21) ? REG_TRACE[21]:
       (address == ADRS_TRACE22) ? REG_TRACE[22]:
       (address == ADRS_TRACE23) ? REG_TRACE[23]:
       d_ram_to_cpu;
  
//---------------------------------------------------------------------------
// Synchronize ALE_n and SCTL_n to sys_clk(negedge)
//---------------------------------------------------------------------------
  reg ALE_n0;
  reg ALE_n1;
  wire negedge_ALE_n = ALE_n1 & ~ALE_n0;
  wire posedge_ALE_n = ALE_n0 & ~ALE_n1;
  always @(negedge sys_clk ) begin
     ALE_n0 <= ALE_n;
     ALE_n1 <= ALE_n0;
  end

  reg SCTL_n0;
  reg SCTL_n1;
  wire negedge_SCTL_n = SCTL_n1 & ~SCTL_n0;
  always @(negedge sys_clk) begin
     SCTL_n0 <= SCTL_n;
     SCTL_n1 <= SCTL_n0;
  end

// Somehow, the following code does not work.
//  reg [1:0] ALE_ns;
//  wire	    negedge_ALE_n = ALE_ns[1] & ~ALE_ns[0];
//  wire	    posedge_ALE_n = ALE_ns[0] & ~ALE_ns[1];
//  always @(negedge sys_clk )
//    ALE_ns[1:0]  <= {ALE_ns[0], ALE_n};
//
//  reg [1:0] SCTL_ns;
//  wire    negedge_SCTL_n = SCTL_ns[1] & ~SCTL_ns[0];
//  always @(negedge sys_clk )
//    SCTL_ns[1:0] <= {SCTL_ns[0], SCTL_n};
  
//---------------------------------------------------------------------------
// Bus error
// read 170000-170077 or 177700 causes bus error
//---------------------------------------------------------------------------
  assign ABORT_n = bus_error ? 1'b0 : 1'bz;

  wire bus_error =
       ((address      ==16'o177700) & bus_read) | // Microdiagnostic test 2
       ((address[15:6]==10'o1700)   & bus_read);  // read 170000-170077

//  reg bus_error;
//  always @(posedge sys_clk)
//    if(((address == 16'o177700) & bus_read)|     // Microdiagnostic test 2
//       ((address[15:6] == 10'o1600) & bus_read)| // read 160000-160077
//       ((address[15:12] == 4'o16) &              // write to 160000-167777
//	negedge_SCTL_n & bus_write)             
//       )
//      bus_error <= 1'b1;
//    else 
//      bus_error <= 0;
	
//---------------------------------------------------------------------------
// Memory
//---------------------------------------------------------------------------
  reg [15:0]	 DAL_latched; // latched DAL[15:0]
  reg [3:0]	 AIO_latched; // latched AIO[3:0]
  
// The leading edge of ALE is typically used by external logic
// to latch addresses, AIO codes, BS codes and the MAP control signals.
// (user's manual 2.4.1)
  always @(negedge ALE_n) begin // latch DAL and AIO
     DAL_latched <= DAL;
     AIO_latched <= AIO;
  end
  
  wire write_memory_hi = ~SCTL_n &
       (( aio_code == AIO_BUSWORDWRITE) |
	( aio_code == AIO_BUSBYTEWRITE) & address[0]);
  wire write_memory_lo = ~SCTL_n &
       (( aio_code == AIO_BUSWORDWRITE) |
	( aio_code == AIO_BUSBYTEWRITE) & ~address[0]);
  
  wire DMA = disk_busy; // DMA is activated during disk access

//---------------------------------------------------------------------------
// stretched cycle control signals
//---------------------------------------------------------------------------
  assign CONT_n = (DMA | stretch_trig | stretch_start | KE11_stretch ) ?
		  1'b1 : SCTL_n;

  wire stretch_trig = RF_go | RK_go;
  reg  stretch_start;
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n )
      stretch_start <= 0;
    else if(stretch_trig)
      stretch_start <= 1'b1;
    else if ( disk_busy )
      stretch_start <= 0;
  
//---------------------------------------------------------------------------
// 28KW RAM 
//   - 000000-157777: RAM
//   - 160000-160077: No memory (read/write causes bus error)
//   - 160100-167777: ROM (write causes bus error)
//   - 170000-177777: ROM and Memory mapped I/O
//---------------------------------------------------------------------------
// mem_hi and mem_lo have 32KW capacity for fail safe
  reg [7:0] mem_hi[32767:0]; // higher 8bit (odd byte address)
  reg [7:0] mem_lo[32767:0]; // lower  8bit (even byte address)

  wire [7:0] d_dma_to_ram; // dma data is from sdhd module
  reg [15:0] d_cpu_to_ram;
  always @(negedge SCTL_n) // write data from cpu is latched at negedge SCTL_n
    d_cpu_to_ram <= DAL;

  // address or data of memory should be latched to infer BSRAM
  reg [14:0] wa;  // word address for RAM
  always @(negedge sys_clk)
    wa <= DMA ? dma_address[15:1] : address[15:1];

  wire [15:0] d_ram_to_cpu = {mem_hi[wa], mem_lo[wa]};
  wire [7:0]  d_ram_to_dma = dma_address[0] ? mem_hi[wa]: mem_lo[wa];

  wire	we_hi = DMA ? (dma_write &   dma_address[0])  : write_memory_hi;
  wire	we_lo = DMA ? (dma_write & (~dma_address[0])) : write_memory_lo;

//wire ram_area = (wa[14:12] != 3'b111); // 160000-177777 is ROM (RAM=28KW)
  wire ram_area = (wa[14:11] != 4'b1111); // 170000-177777 is ROM (RAM=30KW)
  always @(posedge sys_clk)
    if( ram_area ) begin 
       if(we_lo) // dma data is 8bit 
	 mem_lo[wa] <= DMA ? d_dma_to_ram[7:0] : d_cpu_to_ram[7:0];
       if(we_hi)
	 mem_hi[wa] <= DMA ? d_dma_to_ram[7:0] : d_cpu_to_ram[15:8];
    end
  
//---------------------------------------------------------------------------
// ROM DATA
//---------------------------------------------------------------------------
`include "rom.v"

//---------------------------------------------------------------------------
// KE11 Arithmetic unit
//---------------------------------------------------------------------------
  assign REG_KE_SR[7:0] =
		{1'b0, // not implemented
		 REG_KE_AC_OUT[15], // not implemented preperly
		 REG_KE_AC_OUT == 16'o177777,
		 REG_KE_AC_OUT == 16'o0,
		 REG_KE_MQ_OUT == 16'o0,
		 (REG_KE_AC_OUT == 16'o0) && (REG_KE_MQ_OUT == 16'o0),
		 REG_KE_AC_OUT == (REG_KE_MQ_OUT[15] ? 16'o177777: 16'o0),
		 REG_KE_SR0
		 };

  wire div_clk = sys_clk;
  wire [31:0] quotient;  //= dividend[31:0] / divisor[15:0];
  wire [15:0] remainder; //= dividend[31:0] % divisor[15:0];
  
  wire [31:0] dividend = {REG_KE_AC[15:0], REG_KE_MQ[15:0]};
  wire [15:0] divisor  = REG_KE_X[15:0];
//-------------------
// divider
//-------------------
// Gowin IP
  Integer_Division_Top integer_division(
		.clk(div_clk), //input clk
		.rstn(INIT_n), //input rstn
		.dividend(dividend), //input [31:0] dividend
		.divisor(divisor), //input [15:0] divisor
		.remainder(remainder), //output [15:0] remainder
		.quotient(quotient) //output [31:0] quotient
	);

//-------------------
// multiplier
//-------------------
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
  
//-------------------
// logical shifter
//-------------------
  wire KE_SC_SIGN = REG_KE_SC[5];

  wire [32:0] lsh_left =  {REG_KE_SR0, REG_KE_AC, REG_KE_MQ}
                        << REG_KE_SC[4:0];
  wire [32:0] lsh_right = {REG_KE_AC, REG_KE_MQ, REG_KE_SR0}
                        >> ((~REG_KE_SC[4:0])+1'b1);

//-------------------
// arithmetic shifter
//-------------------
  wire [31:0] ash_left = {REG_KE_SR0, REG_KE_AC[14:0], REG_KE_MQ}
	                << REG_KE_SC[4:0];
  wire [31:0] ash_right = {REG_KE_AC[14:0], REG_KE_MQ, REG_KE_SR0}
	                >> ((~REG_KE_SC[4:0])+1'b1);

//-------------------
// normalizer
//-------------------
  reg [7:0]  KE_nor_cnt;
  reg [31:0] KE_nor_ACMQ;
  wire	     KE_nor_start = (KE_operation == KE_OP_NOR);
  reg	     last_KE_nor_start;
  reg	     posedge_KE_nor_start;
  always @(posedge sys_clk ) begin
     last_KE_nor_start <= KE_nor_start;
     posedge_KE_nor_start <= KE_nor_start & ~last_KE_nor_start;
  end

  always @(posedge sys_clk )
    if( posedge_KE_nor_start) begin
       KE_nor_ACMQ <= {REG_KE_AC, REG_KE_MQ};
       KE_nor_cnt <= 0;
    end
    else if((KE_nor_ACMQ[31] == KE_nor_ACMQ[30]) &
	    (KE_nor_ACMQ != 32'b11000000_00000000_00000000_00000000) &
	    (KE_nor_cnt != 8'd31)) begin
       KE_nor_ACMQ[30:0] <= {KE_nor_ACMQ[29:0], 1'b0};
       KE_nor_cnt <= KE_nor_cnt + 1'd1;
    end
  
//-------------------
// Assignment of results
//-------------------
  parameter	KE_OP_NOP     = 4'd0;
  parameter	KE_OP_DIV     = 4'd1;
  parameter	KE_OP_MUL     = 4'd2;
  parameter	KE_OP_LOAD_AC = 4'd3;
  parameter	KE_OP_LOAD_MQ = 4'd4;
  parameter	KE_OP_LOAD_SC = 4'd5;
  parameter	KE_OP_ASH     = 4'd6;
  parameter	KE_OP_LSH     = 4'd7;
  parameter	KE_OP_NOR     = 4'd8;
  reg [3:0]	KE_operation;
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n)
      {REG_KE_AC_OUT, REG_KE_MQ_OUT, REG_KE_SR0} <= 0;
    else if( negedge_ALE_n )
      case (KE_operation)
	KE_OP_NOP: ; // do nothing
	KE_OP_DIV: begin
	   REG_KE_MQ_OUT <= quotient[15:0];
	   REG_KE_AC_OUT <= remainder[15:0];
	   REG_KE_SR0    <= 1'b0;  
	end
	KE_OP_MUL: begin
	   {REG_KE_AC_OUT, REG_KE_MQ_OUT} <= product;
	   REG_KE_SR0 <= 1'b0;
	end
	KE_OP_LOAD_AC:
	  REG_KE_AC_OUT <= REG_KE_AC;
	
	KE_OP_LOAD_MQ: begin
	   REG_KE_MQ_OUT <= REG_KE_MQ;
	   REG_KE_AC_OUT <= REG_KE_AC;
	end
	KE_OP_LOAD_SC:
	  REG_KE_SC_OUT <= REG_KE_SC;

	KE_OP_LSH: begin
	   if(~KE_SC_SIGN)
	     {REG_KE_SR0, REG_KE_AC_OUT, REG_KE_MQ_OUT} <= lsh_left;
	   else
	     {REG_KE_AC_OUT, REG_KE_MQ_OUT, REG_KE_SR0} <= lsh_right;
	   REG_KE_SC_OUT <= 0;
	end
	
	KE_OP_ASH: begin
	  if(~KE_SC_SIGN)
	    {REG_KE_SR0, REG_KE_AC_OUT[14:0], REG_KE_MQ_OUT} <= ash_left;
	  else
	    {REG_KE_AC_OUT[14:0], REG_KE_MQ_OUT, REG_KE_SR0} <= ash_right;
	   REG_KE_SC_OUT <= 0;
	end

	KE_OP_NOR: begin
	   REG_KE_SR0 <= 1'b0;
	   REG_KE_SC_OUT <= KE_nor_cnt;
	   {REG_KE_AC_OUT, REG_KE_MQ_OUT} <= KE_nor_ACMQ;
	end
	default: ;
      endcase
  
//-------------------
// Bus access 
//-------------------
  wire [15:0] DAL_sign_extended = aio_write_lowbyte ? 
	      {(DAL[7] ? 8'hFF: 8'h00), DAL[7:0]} // extend sign
	      : DAL;

  wire	      KE11_stretch = (KE11_stretch_cnt != 0);
  
  parameter   KE11_stretch_cnt_DIV = 8'd40;
  parameter   KE11_stretch_cnt_NOR = 8'd32;
  reg [7:0]   KE11_stretch_cnt;
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n ) begin
       {REG_KE_AC, REG_KE_MQ, REG_KE_SC} <= 0;
       KE_operation <= KE_OP_NOP;
       KE11_stretch_cnt <= 0;
    end
    else if(KE11_stretch_cnt != 0)
      KE11_stretch_cnt <= KE11_stretch_cnt - 1'd1;
    else if( negedge_SCTL_n & bus_write )
      case (address)
	ADRS_KE_AC: begin
	   KE_operation <= KE_OP_LOAD_AC;
	   REG_KE_AC <= DAL_sign_extended;
	end
	ADRS_KE_MQ: begin
	   KE_operation <= KE_OP_LOAD_MQ;
	   REG_KE_MQ <= DAL_sign_extended;
	   REG_KE_AC <= DAL_sign_extended[15] ? 16'hFFFF: 16'h0000;
	end
	ADRS_KE_SC:  begin
	   KE_operation <= KE_OP_LOAD_SC;
	   REG_KE_SC <= DAL[7:0];
	end
	ADRS_KE_DIV: begin
	   KE_operation <= KE_OP_DIV;
	   REG_KE_X <= DAL_sign_extended;
	   REG_KE_AC <= REG_KE_AC_OUT;
	   REG_KE_MQ <= REG_KE_MQ_OUT;
	   KE11_stretch_cnt <= KE11_stretch_cnt_DIV;
	end
	ADRS_KE_MUL: begin
	   KE_operation <= KE_OP_MUL;
	   REG_KE_X <= DAL_sign_extended;
	   REG_KE_AC <= REG_KE_AC_OUT;
	   REG_KE_MQ <= REG_KE_MQ_OUT;
	end
	ADRS_KE_NOR: begin
	   KE_operation <= KE_OP_NOR;
	   REG_KE_AC <= REG_KE_AC_OUT;
	   REG_KE_MQ <= REG_KE_MQ_OUT;
	   KE11_stretch_cnt <= KE11_stretch_cnt_NOR;
	end
	ADRS_KE_LSH: begin
	   KE_operation <= KE_OP_LSH;
	   REG_KE_SC <= DAL[7:0];
	   REG_KE_AC <= REG_KE_AC_OUT;
	   REG_KE_MQ <= REG_KE_MQ_OUT;
	end
	ADRS_KE_ASH: begin
	   KE_operation <= KE_OP_ASH;
	   REG_KE_SC <= DAL[7:0];
	   REG_KE_AC <= REG_KE_AC_OUT;
	   REG_KE_MQ <= REG_KE_MQ_OUT;
	end
	default:;
      endcase
  
//---------------------------------------------------------------------------
// RL11 TTY console
//---------------------------------------------------------------------------
  always @(posedge sys_clk)
    if( ~rx_data_ready )
      rx_clear <= 0;
    else if( (address == ADRS_RBUF) & bus_read)
      rx_clear <= 1;
  
  always @(posedge sys_clk)
    if( ~tx_ready )
      tx_send <= 1'b0;
    else if( negedge_SCTL_n & bus_write)
      if(address == ADRS_XBUF )
	{tx_data[7:0], tx_send} <= {DAL[7:0], 1'b1};
  
  always @(posedge sys_clk)
    if(negedge_SCTL_n & bus_write)
      if(address == ADRS_RCSR )
	RCSR_ID <= DAL[6];
      else if( address == ADRS_XCSR)
	XCSR_ID <= DAL[6];
      else if(address == ADRS_SWR)
	REG_SWR <= DAL[15:0];
       
//---------------------------------------------------------------------------
// RF11 (drum) and RK11 (disk)
//
// RF: 1024 block
// RK: 6144 block (=256cyl*2sur*12sectors)
// SD memory block
//          0-1023: RF
//       1024-7167: RK0
//      7168-13311: RK1
//     13312-19455: RK2
//     19456-25599: RK3
// # sample for making a sd image from unix disk drive images
// dd if=rf0 of=sd.dsk bs=512 
// (if no rf0 file,  dd if=/dev/zero of=sd.dsk bs=512 count=1024)
// dd if=rk0 of=sd.dsk bs=512 seek=1024 conv=notrunc
// dd if=rk1 of=sd.dsk bs=512 seek=7168 conv=notrunc
// dd if=rk2 of=sd.dsk bs=512 seek=13312 conv=notrunc
// dd if=rk3 of=sd.dsk bs=512 seek=19456 conv=notrunc
//---------------------------------------------------------------------------
  parameter  RF_total_block_size   = 11'd1024; // 512byte * 1024 blocks

  wire [15:0] RF_block_address;
  wire [15:0] RK_block_address;
  assign RF_block_address = {6'b000, REG_RF_DAE[1:0], REG_RF_DAR[15:8]};
  assign RK_block_address = {1'b0, REG_RKDA[15:4], 3'b000} +
  			    {2'b00, REG_RKDA[15:4], 2'b00} +
			    {12'b00000000,   REG_RKDA[3:0]} +
			    RF_total_block_size;
  // (= REG_RKDA[15:4] * 12 + REG_RKDA[3:0] + RF_total_block_size)

//--------------------------------------------------------------------------
// RF_READY, RK_READY
//--------------------------------------------------------------------------
  reg	    devsel;
  parameter DEV_RF = 1'b0;
  parameter DEV_RK = 1'b1;

  reg [2:0] disk_readys;
  reg [2:0] devsels;
// wire  posedge_disk_ready = (disk_readys[0] & ~disk_readys[2]);
// IRQ sometimes did not occur. This is a dirty workaround.
//  wire	    posedge_disk_ready = (disk_readys[0] & ~disk_readys[2])|
//                                 (disk_readys[0] & ~disk_readys[1])|
//                                 (disk_readys[1] & ~disk_readys[2]);
// or the following works
  wire	    posedge_disk_ready = (disk_readys[2:0] == 3'b001) |
  	                         (disk_readys[2:0] == 3'b011);
  wire	    current_dev = devsels[2];
  always @(posedge sys_clk ) begin
     disk_readys[2:0] <= {disk_readys[1:0], disk_ready};
     devsels[2:0]     <= {devsels[1:0], devsel};
  end

  reg  RF_READY;
  always @(posedge sys_clk or negedge INIT_n)
    if(~INIT_n)
      RF_READY <= 1'b1;
    else if( RF_go )
      RF_READY <= 0;
    else if(posedge_disk_ready & (current_dev == DEV_RF))
      RF_READY <= 1'b1;

  reg  RK_READY;
  always @(posedge sys_clk or negedge INIT_n)
    if(~INIT_n)
      RK_READY <= 1'b1;
    else if( RK_go )
      RK_READY <= 0;
    else if(posedge_disk_ready & (current_dev == DEV_RK))
      RK_READY <= 1'b1;

//--------------------------------------------------------------------------
// RF_go, RK_go
//--------------------------------------------------------------------------
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n ) begin
       {disk_read, disk_write, disk_seek} <= 0;
       {RF_go_clear, RK_go_clear} <= 0;
    end
    else if( disk_busy ) begin
       disk_read   <= 0;
       disk_write  <= 0;
       disk_seek   <= 0;
       RF_go_clear <= 0;
       RK_go_clear <= 0;
    end
    else if( RF_go ) begin
       RF_go_clear <= 1'b1;
       devsel <= DEV_RF;
       disk_block_address <= RF_disk_block_address;
       dma_start_address  <= RF_dma_start_address;
       dma_wordcount      <= RF_dma_wordcount;
       case(RF_command)
	 RF_DCS_READ:  disk_read  <= 1'b1;
	 RF_DCS_WRITE: disk_write <= 1'b1;
	 default:;
       endcase
    end
    else if( RK_go ) begin
       RK_go_clear <= 1'b1;
       devsel <= DEV_RK;
       disk_block_address <= RK_disk_block_address;
       dma_start_address  <= RK_dma_start_address;
       dma_wordcount      <= RK_dma_wordcount;
       case ( RK_command )
	 RKCS_READ:   disk_read  <= 1'b1;
	 RKCS_WRITE:  disk_write <= 1'b1;
	 RKCS_DRESET: disk_seek  <= 1'b1;
	 RKCS_SEEK:   disk_seek  <= 1'b1;
	 default: ;
       endcase
    end

//---------------------------------------------------------------------------
// RF11 (drum)
//---------------------------------------------------------------------------
  reg [15:0]  RF_disk_block_address;
  reg [15:0]  RF_dma_start_address;
  reg [15:0]  RF_dma_wordcount;
  reg	      RF_go;	      
  reg	      RF_go_clear;
  reg [1:0]   RF_command;
  
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n ) begin
       {REG_RF_DCS, REG_RF_WC,  REG_RF_CMA}     <= 0;
       {REG_RF_DAR, REG_RF_DAE, REG_RF_ADS}     <= 0;
    end
    else if( RF_go_clear )
      RF_go <= 0;
    else if( negedge_SCTL_n & bus_write )
      if( address == ADRS_RF_DCS ) begin
	 REG_RF_DCS <= DAL;
	 if( DAL[8] ) begin // RF disk clear 
	    {REG_RF_DCS, REG_RF_WC,  REG_RF_CMA} <= 0;
	    {REG_RF_DAR, REG_RF_DAE, REG_RF_ADS} <= 0;
	 end
	 else if((DAL[0] == RF_DCS_GO) & RF_READY) begin
	    RF_go                       <= 1'b1;
	    RF_command                  <=DAL[2:1]; 
	    RF_disk_block_address[15:0] <= RF_block_address[15:0];
	    RF_dma_start_address        <= REG_RF_CMA;
	    RF_dma_wordcount            <= REG_RF_WC;
	    
	    // update registers (this is not correct implementation)
	    REG_RF_WC  <= 0;
	    REG_RF_CMA <= REG_RF_CMA + (((~REG_RF_WC[15:0]) + 1'b1)<<1);
	    {REG_RF_DAE[1:0], REG_RF_DAR} <= {REG_RF_DAE[1:0], REG_RF_DAR} +
					     {(~REG_RF_WC[15:0]) + 1'b1};
	    
	    // for debug
	    REG_RF_WC_BAK  <= REG_RF_WC;
	    REG_RF_CMA_BAK <= REG_RF_CMA;
	    REG_RF_DAE_BAK <= REG_RF_DAE;
	    REG_RF_DAR_BAK <= REG_RF_DAR;
	    
	 end
      end
      else
	case (address)
	  ADRS_RF_WC:  REG_RF_WC  <= DAL;
	  ADRS_RF_CMA: REG_RF_CMA <= DAL;
	  ADRS_RF_DAR: REG_RF_DAR <= DAL;
	  ADRS_RF_DAE: REG_RF_DAE <= DAL;
	  ADRS_RF_ADS: REG_RF_ADS <= DAL;
	  default:;
	endcase	
  
//---------------------------------------------------------------------------
// RK11 (disk)
//---------------------------------------------------------------------------
  reg [15:0]  RK_disk_block_address;
  reg [15:0]  RK_dma_start_address;
  reg [15:0]  RK_dma_wordcount;
  reg	      RK_go;
  reg	      RK_go_clear;
  reg [2:0]   RK_command;

  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n ) begin
       {REG_RKCS, REG_RKWC, REG_RKBA, REG_RKDA} <= 0;
    end
    else if( RK_go_clear )
      RK_go <= 0;
    else if( negedge_SCTL_n & bus_write )
      if(address == ADRS_RKCS ) begin
	 REG_RKCS   <= DAL;
	 if((DAL[0] == RKCS_GO) & RK_READY) begin
	    RK_go       <= 1'b1;
	    RK_command  <= DAL[3:1];
	    if( DAL[3:1] == RKCS_READ || DAL[3:1] == RKCS_WRITE) begin
	       RK_disk_block_address[15:0] <= RK_block_address[15:0];
	       RK_dma_start_address <= REG_RKBA;
	       RK_dma_wordcount     <= REG_RKWC;
	       // update registers (this is not correct implementation)
	       REG_RKWC <= 0;
	       if( ~REG_RKCS[11] ) // Inhibit incrementing the RKBA (IBA)
		 REG_RKBA <= REG_RKBA + (((~REG_RKWC[15:0]) + 1'b1)<<1);
	       // for debug
	       REG_RKWC_BAK <= REG_RKWC;
	       REG_RKBA_BAK <= REG_RKBA;
	    end
	    case ( DAL[3:1] ) // REG_RKCS[13] is SCP(Search complete) bit
	      RKCS_CRESET: {REG_RKCS, REG_RKWC, REG_RKBA, REG_RKDA} <= 0;
	      RKCS_DRESET: REG_RKCS[13] <= 1'b1;
	      RKCS_SEEK:   REG_RKCS[13] <= 1'b1;
	      default:     REG_RKCS[13] <= 0;
	    endcase
	 end
      end
      else
	case (address)
	  ADRS_RKWC:   REG_RKWC   <= DAL;
	  ADRS_RKBA:   REG_RKBA   <= DAL;
	  ADRS_RKDA:   REG_RKDA   <= DAL;
	  default:;
	endcase	
  
//---------------------------------------------------------------------------
// Interrupt
//---------------------------------------------------------------------------
  // interrupt levels  
  parameter LV_IRQ0 = 3'd4;
  parameter LV_IRQ1 = 3'd5;
//  parameter LV_IRQ2 = 3'd6;
//  parameter LV_IRQ3 = 3'd7;

//---------------------------------------------------------------------------
// unimplemented IRQs
//---------------------------------------------------------------------------
//  assign IRQ2  = 0;
//  assign IRQ3  = 0;

// vector address for unimplemented IRQs
//  wire [15:0]	 VA_IRQ2 = 16'o0;
//  wire [15:0]	 VA_IRQ3 = 16'o0;

//---------------------------------------------------------------------------
// Interrupt by TTY I/O
// IRQ0 (IRQ level=4)
//---------------------------------------------------------------------------
  reg IRQ_ttyi;
  reg IRQ_ttyo;
  assign      IRQ0 = IRQ_ttyi | IRQ_ttyo;

  parameter   VA_ttyi  = 16'o000060; // Interrupt vector address
  parameter   VA_ttyo  = 16'o000064; // Interrupt vector address
  reg [15:0]  VA_IRQ0;
  always @(posedge sys_clk)
    if(negedge_ALE_n)
      VA_IRQ0 <= IRQ_ttyi ? VA_ttyi : VA_ttyo;

  wire	 ack_IRQ_tty = (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ0);

  reg [2:0] ack_IRQ_ttys;
  wire	 posedge_ack_IRQ_tty = ack_IRQ_ttys[1] & ~ack_IRQ_ttys[2];
  always @( negedge sys_clk )
    ack_IRQ_ttys[2:0] <= {ack_IRQ_ttys[1:0], ack_IRQ_tty};

  reg [2:0] tx_readys;
  wire posedge_tx_ready = tx_readys[1] & ~tx_readys[2];
  always @( posedge sys_clk )
    tx_readys[2:0] <= {tx_readys[1:0], tx_ready};

  reg [2:0] rx_data_readys;
  wire posedge_rx_data_ready = rx_data_readys[1] & ~rx_data_readys[2];
  always @( posedge sys_clk )
    rx_data_readys[2:0] <= {rx_data_readys[1:0], rx_data_ready};
  
  always @( posedge sys_clk or negedge INIT_n)
    if( ~INIT_n)
      IRQ_ttyo <= 0;
    else if( posedge_tx_ready)
      IRQ_ttyo <= XCSR_ID;
    else if( posedge_ack_IRQ_tty & (VA_IRQ0 == VA_ttyo))
      IRQ_ttyo <= 0;
// additional dirty clear logics
//    else if( (address == ADRS_XCSR) || (address == ADRS_XBUF))
//      IRQ_ttyo <= 0;   // clear by access tor tx registers
//    else if( ~tx_ready)
//      IRQ_ttyo <= 0;   // clear when tx is not ready

  always @( posedge sys_clk or negedge INIT_n)
    if( ~INIT_n)
      IRQ_ttyi <= 0;
    else if( posedge_rx_data_ready)
      IRQ_ttyi <= RCSR_ID;
    else if( posedge_ack_IRQ_tty & (VA_IRQ0 == VA_ttyi))
      IRQ_ttyi <= 0;
    else if( ~rx_data_ready ) // additional dirty clear logic
      IRQ_ttyi <= 0;          // to clear IRQ when exiting console ODT

//---------------------------------------------------------------------------
// Interrupt by RF(drum)/RK(disk) ready
// IRQ1 (IRQ level=5)
//---------------------------------------------------------------------------
  reg		 IRQ_RF;
  reg		 IRQ_RK;

  assign IRQ1           = IRQ_RF | IRQ_RK;

  parameter	 VA_RF  = 16'o000204; // RF(drum)
  parameter	 VA_RK  = 16'o000220; // RK(disk)
  reg [15:0]  VA_IRQ1;
  always @(posedge sys_clk)
    if(negedge_ALE_n)
      VA_IRQ1 <= IRQ_RF   ? VA_RF : VA_RK;

  wire	 ack_IRQ_RFRK = (aio_code == AIO_INTACK && irq_ack_level == LV_IRQ1);

  reg  [2:0] ack_IRQ_RFRKS;
  wire	     posedge_ack_IRQ_RFRK = ack_IRQ_RFRKS[0] & ~ack_IRQ_RFRKS[2];
  always @( negedge sys_clk ) 
    ack_IRQ_RFRKS[2:0] <= {ack_IRQ_RFRKS[1:0], ack_IRQ_RFRK};
  
  reg [2:0] RF_READYS;
//  wire	    posedge_RF_READY = (RF_READYS[0] & ~RF_READYS[2]) |
//                               (RF_READYS[0] & ~RF_READYS[1]);
  wire	 posedge_RF_READY = RF_READYS[0] & ~RF_READYS[2];
  always @( negedge sys_clk )
    RF_READYS[2:0] <= {RF_READYS[1:0], RF_READY};
  
  reg [2:0] RK_READYS;
//  wire	    posedge_RK_READY = (RK_READYS[0] & ~RK_READYS[2]) |
//                               (RK_READYS[0] & ~RK_READYS[1]);
  wire	 posedge_RK_READY = RK_READYS[0] & ~RK_READYS[2];
  always @( negedge sys_clk )
    RK_READYS[2:0] <= {RK_READYS[1:0], RK_READY};

  wire	 RF_INT_ENABLE = REG_RF_DCS[6];
  wire	 RK_INT_ENABLE = REG_RKCS[6];
  always @( posedge sys_clk )
    if( ~INIT_n )
      IRQ_RF <= 0;
    else if( posedge_RF_READY )
      IRQ_RF <= RF_INT_ENABLE;
    else if( posedge_ack_IRQ_RFRK & (VA_IRQ1 == VA_RF))
      IRQ_RF <= 0;
  
  always @( posedge sys_clk )
    if( ~INIT_n )
      IRQ_RK <= 0;
    else if( posedge_RK_READY )
      IRQ_RK <= RK_INT_ENABLE;
    else if( posedge_ack_IRQ_RFRK & (VA_IRQ1 == VA_RK))
      IRQ_RK <= 0;
  
//---------------------------------------------------------------------------
// EVENT (timer) 
// IRQ level=6
//---------------------------------------------------------------------------
  assign EVENT_n = ~IRQ_timer; // EVENT_n(level 6, address=0100)
  wire EVENT_ACK = (aio_code == AIO_GPWRITE) & (gpcode == GP_ACK_EVENT);

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
  reg	     negedge_clk_60Hz;
  always @(posedge sys_clk)
    if(cnt_8333us == SYS_CLK_FRQ/120) begin
       cnt_8333us       <= 0;
       clk_60Hz         <= ~clk_60Hz;
       negedge_clk_60Hz <= clk_60Hz; // == clk_60Hz ? 1'b1: 1'b0;
    end
    else begin
       cnt_8333us <= cnt_8333us + 1'b1;
       negedge_clk_60Hz <= 0;
    end

  reg EVENT_ACK0;
  reg EVENT_ACK1;
  wire posedge_EVENT_ACK = EVENT_ACK0 & ~EVENT_ACK1;
  always @(negedge sys_clk) begin
     EVENT_ACK0 <= EVENT_ACK;
     EVENT_ACK1 <= EVENT_ACK0;
  end
  
  always @( posedge sys_clk or negedge INIT_n)
    if( ~INIT_n ) begin
       REG_KW11L_INT_ENABLE <= 0;
       REG_KW11L_INT_MONITOR <= 1'b1; // set on processor INIT
    end
    else if( posedge_EVENT_ACK )
      REG_KW11L_INT_MONITOR <= 0;
    else if( negedge_SCTL_n & bus_write & (address == ADRS_KW11L)) begin
       REG_KW11L_INT_ENABLE  <= DAL[6];
       REG_KW11L_INT_MONITOR <= 0;
    end
    else if( negedge_clk_60Hz )
      REG_KW11L_INT_MONITOR <= 1'b1; // set interrupt flag
  
//---------------------------------------------------------------------------
// UART
//---------------------------------------------------------------------------
  uart_rx#
    (
     .CLK_FRQ(SYS_CLK_FRQ),
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
     .CLK_FRQ(SYS_CLK_FRQ),
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
  wire	      disk_busy = ~disk_ready;	      
  reg	      disk_read;
  reg	      disk_write;
  reg	      disk_seek;
//  reg [23:0]  disk_block_address;
  reg [15:0]  disk_block_address;
  wire [9:0]  disk_buf_address;
  wire [15:0] dma_address;
  reg [15:0]  dma_start_address;
  reg [15:0]  dma_wordcount;
  wire [5:0]  sd_state;
  wire [3:0]  sd_error;

  sdhd #(
	      .SYS_FRQ(SDHD_CLK_FRQ),
	      .MEM_FRQ(400_000)
    ) sdhd_inst
  (
   .i_clk                (sdhd_clk),
   .i_reset_n            (RESET_n),
   .i_sd_miso            (sd_miso),
   .o_sd_mosi            (sd_mosi),
   .o_sd_cs_n            (sd_cs_n),
   .o_sd_clk             (sd_clk),
   .o_disk_ready         (disk_ready),
   .i_disk_read          (disk_read),
   .i_disk_write         (disk_write),
   .i_disk_seek          (disk_seek),
   .i_disk_block_address ({8'b0, disk_block_address[15:0]}),
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
  reg [7:0] LED_R;
  reg [7:0] LED_G;
  reg [7:0] LED_B;

  reg	    dbg_trg;
  assign HALT = dbg_trg;
  // connect dbg_trg to HALT with 1k registor (to avoid collision with HALT_SW)

  reg [15:0] REG_TRACE[23:0];
  parameter  ADRS_TRACE23 = 16'o177000;
  parameter  ADRS_TRACE22 = 16'o177002;
  parameter  ADRS_TRACE21 = 16'o177004;
  parameter  ADRS_TRACE20 = 16'o177006;
  parameter  ADRS_TRACE19 = 16'o177010;
  parameter  ADRS_TRACE18 = 16'o177012;
  parameter  ADRS_TRACE17 = 16'o177014;
  parameter  ADRS_TRACE16 = 16'o177016;
  parameter  ADRS_TRACE15 = 16'o177020;
  parameter  ADRS_TRACE14 = 16'o177022;
  parameter  ADRS_TRACE13 = 16'o177024;
  parameter  ADRS_TRACE12 = 16'o177026;
  parameter  ADRS_TRACE11 = 16'o177030;
  parameter  ADRS_TRACE10 = 16'o177032;
  parameter  ADRS_TRACE9  = 16'o177034;
  parameter  ADRS_TRACE8  = 16'o177036;
  parameter  ADRS_TRACE7  = 16'o177040;
  parameter  ADRS_TRACE6  = 16'o177042;
  parameter  ADRS_TRACE5  = 16'o177044;
  parameter  ADRS_TRACE4  = 16'o177046;
  parameter  ADRS_TRACE3  = 16'o177050;
  parameter  ADRS_TRACE2  = 16'o177052;
  parameter  ADRS_TRACE1  = 16'o177054;
  parameter  ADRS_TRACE0  = 16'o177056;

  always @(posedge sys_clk or negedge RESET_n)
    if( ~RESET_n ) begin
       {REG_TRACE[3], REG_TRACE[2], REG_TRACE[1], REG_TRACE[0]} <= 0;
       {REG_TRACE[7], REG_TRACE[6], REG_TRACE[5], REG_TRACE[4]} <= 0;
       {REG_TRACE[11], REG_TRACE[10], REG_TRACE[9], REG_TRACE[8]} <= 0;
       {REG_TRACE[15], REG_TRACE[14], REG_TRACE[13], REG_TRACE[12]} <= 0;
       {REG_TRACE[19], REG_TRACE[18], REG_TRACE[17], REG_TRACE[16]} <= 0;
       {REG_TRACE[23], REG_TRACE[22], REG_TRACE[21], REG_TRACE[20]} <= 0;
    end
    else if(posedge_ALE_n & aio_iread) begin
//    else if(negedge_ALE_n & aio_iread) begin
       // record @posedge_ALE_n as address is latched @negedge ALE_n
       {REG_TRACE[3] , REG_TRACE[2] , REG_TRACE[1] , REG_TRACE[0]}  <=
       {REG_TRACE[2] , REG_TRACE[1] , REG_TRACE[0] , address};
       {REG_TRACE[7] , REG_TRACE[6] , REG_TRACE[5] , REG_TRACE[4]}  <=
       {REG_TRACE[6] , REG_TRACE[5] , REG_TRACE[4] , REG_TRACE[3]};
       {REG_TRACE[11], REG_TRACE[10], REG_TRACE[9] , REG_TRACE[8]}  <=
       {REG_TRACE[10], REG_TRACE[9] , REG_TRACE[8] , REG_TRACE[7]};
       {REG_TRACE[15], REG_TRACE[14], REG_TRACE[13], REG_TRACE[12]} <=
       {REG_TRACE[14], REG_TRACE[13], REG_TRACE[12], REG_TRACE[11]};
       {REG_TRACE[19], REG_TRACE[18], REG_TRACE[17], REG_TRACE[16]} <=
       {REG_TRACE[18], REG_TRACE[17], REG_TRACE[16], REG_TRACE[15]};
       {REG_TRACE[23], REG_TRACE[22], REG_TRACE[21], REG_TRACE[20]} <=
       {REG_TRACE[22], REG_TRACE[21], REG_TRACE[20], REG_TRACE[19]};
    end

  reg [15:0] REG_DBG0;
  reg [15:0] REG_DBG1;
  reg [15:0] REG_DBG2;
  reg	     REG_DBG_CP;
  parameter  ADRS_DBG0   = 16'o177100;
  parameter  ADRS_DBG1   = 16'o177102;
  parameter  ADRS_DBG2   = 16'o177104;
  always @(posedge sys_clk or negedge RESET_n)
    if( ~RESET_n ) begin // set dummy addresses
       REG_DBG0 <= 16'o177775;
       REG_DBG1 <= 16'o177775;
       REG_DBG2 <= 16'o177775;
    end
    else if(negedge_SCTL_n & bus_write)
      case (address)
	ADRS_DBG0: REG_DBG0 <= DAL;
	ADRS_DBG1: REG_DBG1 <= DAL;
	ADRS_DBG2: REG_DBG2 <= DAL;
	default:;
      endcase
  
  always @(posedge init_clk)
    if( (~RESET_n) | (~INIT_n))
      {REG_DBG_CP, dbg_trg} <= 0;
    else if( address == ADRS_XCSR) // negate HALT when console ODT starts
      dbg_trg <= 0; 
    else if( (address == REG_DBG0) & aio_iread )
      dbg_trg <= 1'b1;
    else if( (address == REG_DBG1) & aio_iread)
      REG_DBG_CP <= 1'b1;
    else if( (address == REG_DBG2) & aio_iread  & REG_DBG_CP)
      dbg_trg <= 1'b1;
//    else if( (address == 16'o001040) & aio_iread ) // trap at 'panic:'
//      dbg_trg <= 1'b1;
//  else if( (dpwa == (16'o25246 >> 1)) & (we0_lo | we0_hi |we1_lo | we1_hi))
//    dbg_trg <= 1'b1;
//  else if( (dpwa == (16'o1256 >> 1)) & bus_write)
//  else if ((REG_RF_DAR_BAK == 16'o117400) & disk_write & (devsel == DEV_RF))
//  else if ( REG_RKCS[11] ) // Inhibit incrementing RKBA

  ws2812 onboard_rgb_led(.clk(led_clk), .we(1'b1), .sout(LED_RGB),
			 .r(LED_R), .g(LED_G), .b(LED_B));

  reg [25:0]		cnt_500ms;
  reg			clk_1Hz;
  always @(posedge sys_clk)
    if(cnt_500ms == SYS_CLK_FRQ/2) begin
       cnt_500ms <= 0;
       clk_1Hz <= ~clk_1Hz;
    end else 
      cnt_500ms <= cnt_500ms + 1'b1;

  reg [5:0] event_count;
  reg	    event_monitor;
  always @(posedge sys_clk or negedge INIT_n)
    if( ~INIT_n )
      {event_count, event_monitor} <= 0;
    else if(posedge_EVENT_ACK)
      if(event_count == 6'd30) begin
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
//		diag_test2 ? 8'h20:
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
  reg [7:0]  dbg_pbuf[255:0];
  reg [6:0]  dbg_pcnt;
  parameter  DBG_PSTATE_IDLE  = 8'd255;
  parameter  DBG_PSTATE_PRINT = 8'd254;
  parameter  DBG_PSTATE_WAIT  = 8'd253;
  parameter  DBG_PSTATE_CLEAR = 8'd252;
  reg	     dbg_print;
  reg	     dbg_clear; // for hand shake
  always @(posedge sys_clk or negedge RESET_n)
    if(~RESET_n) begin
       dbg_pstate <= DBG_PSTATE_IDLE;
       dbg_clear <= 0;
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
	8'd44: {dbg_pbuf[44], dbg_pstate} <= {8'b0, DBG_PSTATE_CLEAR};
	DBG_PSTATE_CLEAR:
	  if( dbg_print )
	    dbg_clear <= 1'b1;
	  else if( ~dbg_print ) begin
	     dbg_clear <= 0;
	     dbg_pstate <= DBG_PSTATE_PRINT;
	  end
	DBG_PSTATE_PRINT:
	  if( dbg_pbuf[dbg_pcnt] == 8'b0)
	    dbg_pstate <= DBG_PSTATE_IDLE;
	  else if( dbg_tx_ready ) begin
	     dbg_tx_data <= dbg_pbuf[dbg_pcnt];
	     dbg_tx_send <= 1;
	     dbg_pcnt <= dbg_pcnt + 1'd1;
	     dbg_pstate <= DBG_PSTATE_WAIT;
	  end
	DBG_PSTATE_WAIT:
	  if( ~dbg_tx_ready ) begin
	     dbg_tx_send <= 0;
	     dbg_pstate <= DBG_PSTATE_PRINT;
	  end

	// dummy to avoid warning
	default: dbg_pbuf[dbg_pstate] <= 0;
      endcase
  
  reg [11:0] cnt_100us;
  reg [15:0] dbg_time;
  always @(posedge sys_clk or negedge INIT_n)
    if(~INIT_n)
      {cnt_100us, dbg_time} <= 0;
    else if(cnt_100us == (SYS_CLK_FRQ / 1000 / 1000)*100 -1) begin // 100us
       cnt_100us <= 0;
       dbg_time <= dbg_time + 1'd1;
    end
    else
      cnt_100us <= cnt_100us + 1'd1;

  wire [15:0] REG_RF_DCS_R ={8'b0, RF_READY, REG_RF_DCS[6:1], 1'b0};
  wire [15:0] REG_RKCS_R   ={2'b00, REG_RKCS[13:8], RK_READY, REG_RKCS[6:0]};
  wire [15:0] REG_RKDS_R   ={8'b000_01001, RK_READY, RK_READY,
			     2'b01, REG_RKDA[3:0]};
  
  wire [15:0] dbg_disk_address = disk_block_address[15:0];
  always @(posedge sys_clk)
    if ( dbg_clear )
      dbg_print <= 0;
    else if ( (dbg_print == 1'b0) & (dbg_regt != dbg_time) )
      if ((address == 16'o173000) & aio_iread ) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "bt";
	 dbg_reg0 <= address;
	 dbg_reg1 <= 0;
	 dbg_reg2 <= 0;
	 dbg_reg3 <= 0;
	 dbg_reg4 <= 0;
	 dbg_print<= 1'b1;
      end
      else if ((DAL == VA_RF) & vec_read ) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "Fi";
	 dbg_reg0 <= REG_RF_DCS_R;
	 dbg_reg1 <= REG_TRACE[3];
	 dbg_reg2 <= REG_TRACE[2];
	 dbg_reg3 <= REG_TRACE[1];
	 dbg_reg4 <= REG_TRACE[0];
	 dbg_print<= 1'b1;
      end
      else if ((DAL == VA_RK) & vec_read ) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "Ki";
	 dbg_reg0 <= REG_RKCS_R;
	 dbg_reg1 <= REG_TRACE[3];
	 dbg_reg2 <= REG_TRACE[2];
	 dbg_reg3 <= REG_TRACE[1];
	 dbg_reg4 <= REG_TRACE[0];
	 dbg_print<= 1'b1;
      end
      else if ( bus_error ) begin
	 dbg_regw <= "be"; // bus error
//      else if (~ABORT_n ) begin
//	 dbg_regw <= "ab"; // Abort
//      else if ((address == 16'o000320) & aio_iread ) begin
//	 dbg_regw <= "tr"; // trap (UNIX V6)
	 dbg_regt <= dbg_time;
	 dbg_reg0 <= address;
	 dbg_reg1 <= REG_TRACE[3];
	 dbg_reg2 <= REG_TRACE[2];
	 dbg_reg3 <= REG_TRACE[1];
	 dbg_reg4 <= REG_TRACE[0];
	 dbg_print<= 1'b1;
      end
      else if ((devsel == DEV_RF) & disk_read) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "FR";
	 dbg_reg0 <= REG_RF_DCS;
	 dbg_reg1 <= REG_RF_WC_BAK;
	 dbg_reg2 <= REG_RF_CMA_BAK;
	 dbg_reg3 <= REG_RF_DAR_BAK;
	 dbg_reg4 <= dbg_disk_address;
	 dbg_print<= 1'b1;
      end
      else if ((devsel == DEV_RF) & disk_write) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "FW";
	 dbg_reg0 <= REG_RF_DCS;
	 dbg_reg1 <= REG_RF_WC_BAK;
	 dbg_reg2 <= REG_RF_CMA_BAK;
	 dbg_reg3 <= REG_RF_DAR_BAK;
	 dbg_reg4 <= dbg_disk_address;
	 dbg_print<= 1'b1;
      end
      else if ((devsel == DEV_RK) & disk_read) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "KR";
	 dbg_reg0 <= REG_RKCS;
	 dbg_reg1 <= REG_RKWC_BAK;
	 dbg_reg2 <= REG_RKBA_BAK;
	 dbg_reg3 <= REG_RKDA;
	 dbg_reg4 <= dbg_disk_address;
	 dbg_print<= 1'b1;
      end
      else if ((devsel == DEV_RK) & disk_write) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "KW";
	 dbg_reg0 <= REG_RKCS;
	 dbg_reg1 <= REG_RKWC_BAK;
	 dbg_reg2 <= REG_RKBA_BAK;
	 dbg_reg3 <= REG_RKDA;
	 dbg_reg4 <= dbg_disk_address;
	 dbg_print<= 1'b1;
      end
      else if ((devsel == DEV_RK) & disk_seek) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "KS";
	 dbg_reg0 <= REG_RKCS_R;
	 dbg_reg1 <= REG_RKWC_BAK;
	 dbg_reg2 <= REG_RKBA_BAK;
	 dbg_reg3 <= REG_RKDA;
	 dbg_reg4 <= dbg_disk_address;
	 dbg_print<= 1'b1;
      end
      else if((DAL == VA_ttyi) & vec_read) begin
//      else if ((address == 16'o007614) & aio_iread ) begin
//      else if ((address == 16'o000060) & bus_read ) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "ti";
	 dbg_reg0 <= REG_TRACE[4];
	 dbg_reg1 <= REG_TRACE[3];
	 dbg_reg2 <= REG_TRACE[2];
	 dbg_reg3 <= REG_TRACE[1];
	 dbg_reg4 <= REG_TRACE[0];
	 dbg_print<= 1'b1;
      end
      else if((DAL == VA_ttyo) & vec_read) begin
//      else if ((address == 16'o010000) & aio_iread ) begin
//      else if ((address == 16'o000064) & bus_read) begin
	 dbg_regt <= dbg_time;
	 dbg_regw <= "to";
	 dbg_reg0 <= REG_TRACE[4];
	 dbg_reg1 <= REG_TRACE[3];
	 dbg_reg2 <= REG_TRACE[2];
	 dbg_reg3 <= REG_TRACE[1];
	 dbg_reg4 <= REG_TRACE[0];
//	 dbg_print<= 1'b1;
      end

  
  parameter	 UART_BPS_DBG    =       115_200; // (for TeraTerm)
// the followings are for oscilloscope
//  parameter	 UART_BPS_DBG    =     1_700_000; // (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     2_700_000; // (27_000_000 / 10)
//  parameter	 UART_BPS_DBG    =     6_750_000; // (27_000_000 / 4)
//  parameter	 UART_BPS_DBG    =    13_500_000; // (27_000_000 / 2)
  reg [7:0]	 dbg_tx_data;
  reg		 dbg_tx_send;
  wire		 dbg_tx_ready;
  wire		 dbg_tx;
  
  uart_tx#
    (
     .CLK_FRQ(SYS_CLK_FRQ),
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
