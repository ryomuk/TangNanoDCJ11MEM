// sdhd.v
// Hard disk drive emulator using SD/SDHC memory
// - emulating very limited functions of RF11 and RK11
//
// by Ryo Mukai
// 2024/06/08: initial version
// 2024/06/27: short(less than 512byte) block write implemented

module sdhd
  #(
    parameter SYS_FRQ = 27_000_000, // system clock frequency(Hz)
    parameter MEM_FRQ =    400_000  // memory clock frequency(Hz)(106k to 1M)
    )
  (
   input	 i_clk, // system clock input
   input	 i_reset_n, // synchronous reset input, low active 
   input	 i_sd_miso,
   output	 o_sd_mosi,
   output	 o_sd_cs_n,
   output	 o_sd_clk,

   output	 o_disk_ready,
   input	 i_disk_read,  // disk_read
   input	 i_disk_write, // disk_write
   input	 i_disk_seek , // disk_seek (dummy function)
   input [23:0]	 i_disk_block_address,
   output [15:0] o_dma_address,
   input [15:0]	 i_dma_start_address,
   input [15:0]	 i_dma_wordcount,
   output reg	 o_dma_write,
   input [7:0]	 i_dma_data,
   output [7:0]	 o_dma_data,
   output [5:0]	 o_sd_state,
   output [3:0]	 o_sd_error
   );

  reg [23:0]	 disk_block_address;

  reg [15:0]	 dma_start_address;
  reg [16:0]	 dma_bytecount; // 2's complement of the number of bytes
  reg [9:0]	 this_bytecount;
  
  reg [7:0]	disk_read_buf;
  reg [7:0]	disk_write_buf;

  assign o_disk_ready = (state == S_IDLE);
//  assign o_disk_done = (state == S_WAIT);
  
  localparam   CLK_DIV  = SYS_FRQ / MEM_FRQ;
  localparam   CLK_DIV2 = CLK_DIV / 2;

  localparam   S_INIT_RESET      = 5'd0;
  localparam   S_INIT_DUMMY      = 5'd1;
  localparam   S_INIT_CMD0       = 5'd2;
  localparam   S_INIT_CMD8       = 5'd3;
  localparam   S_INIT_CMD55      = 5'd4;
  localparam   S_INIT_ACMD41     = 5'd5;
  localparam   S_INIT_ACMD41_RTY = 5'd6;
  localparam   S_INIT_CMD58      = 5'd7;
  localparam   S_INIT_CMD16      = 5'd8;
  localparam   S_IDLE            = 5'd9;
  localparam   S_READ_START      = 5'd10;
  localparam   S_READ_CMD        = 5'd11; // CMD17
  localparam   S_READ_DATA       = 5'd12;
  localparam   S_READ_CONTINUE   = 5'd13;
  localparam   S_WRITE_START     = 5'd14;
  localparam   S_WRITE_CMD       = 5'd15; // CMD24
  localparam   S_WRITE_DATA      = 5'd16;
  localparam   S_WRITE_BUSY      = 5'd17;
  localparam   S_WRITE_CONTINUE  = 5'd18;
  localparam   S_WAIT            = 5'd19;
  localparam   S_SEEK            = 5'd20;
  localparam   S_ERROR           = 5'd31;

  reg [1:0]    sd_version;
  localparam   SD_VERSION1 = 2'd1;
  localparam   SD_VERSION2 = 2'd2;

  wire	       sd_read  = i_disk_read;
  wire	       sd_write = i_disk_write;

  reg	       sd_addressmode_block;
  wire [31:0]  sd_address = (sd_addressmode_block) ?
	       {8'h0000, disk_block_address[23:0]} :
	       {disk_block_address[22:0], 9'b0};
  
  reg [3:0]    sd_error;
  assign o_sd_error = sd_error;
  assign o_sd_state[5:0] = state;

  localparam   ERROR_NOERROR    = 4'd0;
  localparam   ERROR_CMD0       = 4'd1;
  localparam   ERROR_CMD8       = 4'd2;
  localparam   ERROR_ACMD41     = 4'd3;
  localparam   ERROR_CMD17      = 4'd4;
  localparam   ERROR_CMD24      = 4'd5;
  localparam   ERROR_WRITE_DATA = 4'd6;
  

// read_buf_address  is for the buffer from SD to memory
// write_buf_address is for the buffer from memory to SD
  
  assign o_dma_address = (state == S_READ_DATA)  ? read_buf_address :
			 (state == S_WRITE_DATA) ? write_buf_address :
			 0;
  
  wire	       clk = i_clk;
  wire	       reset_n = i_reset_n;
  wire	       newstate = (state != state_l); // this can occur when clk_cnt==0

  // state
  reg [4:0]    state;
  reg [4:0]    state_l;
  always@(posedge clk)
    state_l <= state;
  
  // reset_cnt
  reg [27:0]   reset_cnt = 0;
  localparam   WIDTH_RESET = (SYS_FRQ / 1000) * 200; // 200ms
  always@(posedge clk)
    if( ~reset_n )
      reset_cnt <= 0;
    else if(state == S_INIT_RESET && reset_cnt != WIDTH_RESET)
      reset_cnt <= reset_cnt + 1'd1;

  // seek_cnt
  reg [23:0]   seek_cnt = 0;
  wire	       seek_done = (seek_cnt == WIDTH_SEEK);
  localparam   WIDTH_SEEK = (SYS_FRQ / 1000) * 10; // 10ms
  always@(posedge clk )
    if( state == S_IDLE )
      seek_cnt <= 0;
    else if(seek_cnt != WIDTH_SEEK)
      seek_cnt <= seek_cnt + 1'd1;
  
  // clk_cnt
  reg [7:0]    clk_cnt;
  always@(posedge clk)
    if( ~reset_n )
      clk_cnt <= 0;
    else if(clk_cnt == CLK_DIV - 1)
      clk_cnt <= 0;
    else
      clk_cnt <= clk_cnt + 1'd1;

  // mem_clk
  reg	       mem_clk;	       
  always@(posedge clk)
    if( ~reset_n )
      mem_clk <= 1'b0;
    else if(clk_cnt == CLK_DIV2 - 1)
      mem_clk <= 1'b1;
    else if(clk_cnt == CLK_DIV - 1)
      mem_clk <= 1'b0;

  // dummy_bit_cnt
  reg [9:0]    dummy_bit_cnt;
  localparam   NUM_DUMMY_CLK = 10'd100;
  always@(posedge clk)
    if( newstate )
      dummy_bit_cnt <= 0;
    else if(clk_cnt == CLK_DIV2)
      dummy_bit_cnt <= dummy_bit_cnt + 1'd1;

  // o_sd_clk
  assign o_sd_clk = ( state == S_INIT_RESET
		      || state == S_IDLE
		      || state == S_WAIT
		      )   ? 1'b0 :    mem_clk;

  // send command
  reg [55:0]   send_buf;
  reg [47:0]   command_buf;
  reg	       command_load;
  always@(posedge clk)
    if( ~reset_n )
      command_load <= 0;
    else if( newstate )
      command_load <= 1;
    else if((clk_cnt == 1) & command_load) begin
       send_buf <= {8'hff, command_buf};
       command_load <= 0;
    end
    else if(clk_cnt == CLK_DIV - 1) begin
       send_buf[55:0] <= {send_buf[54:0], 1'b1};
    end
  
  // o_sd_cs_n
  assign o_sd_cs_n = (state == S_INIT_RESET
		      || state == S_INIT_DUMMY
		      || state == S_IDLE
		      || state == S_WAIT
		      || state == S_ERROR
		      ) ? 1'b1 : 1'b0;

  // r1
  reg [7:0]    r1_buf;
  reg [3:0]    r1_bit_cnt;
  wire	       r1_received  = r1_bit_cnt[3];
  always@(posedge clk)
    if( newstate )
      r1_bit_cnt <= 0;
    else if(clk_cnt == CLK_DIV2)
      if( ~r1_received )
	if( (r1_bit_cnt != 0) || (i_sd_miso == 0)) begin
	   r1_buf <= {r1_buf[6:0], i_sd_miso};
	   r1_bit_cnt <= r1_bit_cnt + 1'd1;
	end

  // r3, r7
  reg [39:0]   r3_buf;
  reg [5:0]    r3_bit_cnt;
  wire	       r3_received  = (r3_bit_cnt == 6'd40);
  wire [39:0]  r7_buf       = r3_buf;
  wire	       r7_received  = r3_received;
  always@(posedge clk)
    if( newstate )
      r3_bit_cnt <= 0;
    else if(clk_cnt == CLK_DIV2)
      if( ~r3_received )
	if( (r3_bit_cnt != 0) || (i_sd_miso == 0)) begin
	   r3_buf <= {r3_buf[38:0], i_sd_miso};
	   r3_bit_cnt <= r3_bit_cnt + 1'd1;
	end

  assign o_dma_data = read_buf;

  reg [9:0] read_dma_cnt;
  // receive data packet
  reg [15:0] read_buf_address;
  reg [9:0] read_byte_cnt;
  reg [2:0] read_bit_cnt;
  reg [7:0] read_buf;
  reg	    read_data_done;
  reg	    read_start;
  reg	    read_before_write;
  reg [7:0] read_before_write_buf[511:0];
  always@(posedge clk)
    if( state == S_READ_DATA )
      if( newstate ) begin
	 read_buf_address <= dma_start_address;
	 read_byte_cnt <= 0;
	 read_bit_cnt  <= 0;
	 read_start <= 0;
	 read_data_done <= 0;
	 o_dma_write <= 0;
	 read_dma_cnt <= this_bytecount;
      end
      else if( read_start ) begin
	 if(clk_cnt == CLK_DIV2)
	   read_buf <= {read_buf[6:0], i_sd_miso};
	 else if(clk_cnt == CLK_DIV2 +1)
   	   if( read_bit_cnt == 3'd7 ) begin
	      read_bit_cnt <= 0;
	      if( ~read_byte_cnt[9] & read_dma_cnt[9]) begin
		 if( read_before_write )
		   read_before_write_buf[read_dma_cnt[8:0]] <= read_buf;
		 else 
		   o_dma_write <= 1'b1;
		 read_dma_cnt <= read_dma_cnt + 1'd1;
	      end
	      if(read_byte_cnt == 10'd514) // data(512byte)+CRC(2byte)
		read_data_done <= 1;
	      else
		read_byte_cnt <= read_byte_cnt + 1'd1;
	   end
	   else
	     read_bit_cnt <= read_bit_cnt + 1'd1;
//	 else if(clk_cnt == CLK_DIV2 + 3)
	 else if(clk_cnt == CLK_DIV2 + 8)
	   if( o_dma_write ) begin
	      read_buf_address <= read_buf_address + 1'd1;
	      o_dma_write <= 1'b0;
	   end
      end
      else if(clk_cnt == CLK_DIV2 +1) // wait for miso==0
	if( i_sd_miso == 0)
	  read_start <= 1'b1;

  // send data packet
  reg [9:0] write_dma_cnt;
  reg [9:0] write_byte_cnt;
  reg [8:0] write_data_cnt;
  reg [15:0] write_buf_address;
  reg [3:0] write_bit_cnt;
  reg [7:0] write_buf;
  reg	    write_data_done;
  reg [7:0] write_data_response;
  always@(posedge clk)
    if( state == S_WRITE_DATA)
      if( newstate ) begin // this can occur when clk_cnt == 0
	 write_buf_address <= dma_start_address;
	 write_byte_cnt  <= 0;
	 write_data_cnt  <= 0;
	 write_bit_cnt   <= 0;
	 write_data_done <= 0;
	 write_dma_cnt   <= this_bytecount;
      end
      else if(clk_cnt == 1)
	if( write_bit_cnt == 0)
	  case (write_byte_cnt) 
  	    10'd0: write_buf <= 8'b1111_1111;
	    10'd1: write_buf <= 8'b1111_1111;
	    10'd2: write_buf <= 8'b1111_1110;
	    10'd515: write_buf <= 8'b0000_0000; // dummy CRC
	    10'd516: write_buf <= 8'b0000_0000; // dummy CRC
	    10'd517: write_buf <= 8'b1111_1111;
	    10'd518: write_data_done <= 1'b1;
	    default: // byte_cnt = 3..514
	      if(~write_data_done) begin
//		 write_buf <= mem_writebuf[write_buf_address];
		 if(write_dma_cnt[9]) begin
		    write_buf <= i_dma_data;
		    write_dma_cnt <= write_dma_cnt +1'b1;
		 end
		 else  // write back buffer for short sector write
		   write_buf <= read_before_write_buf[write_data_cnt];
		 write_buf_address <= write_buf_address + 1'd1;
		 write_data_cnt    <= write_data_cnt + 1'd1;
	      end
	  endcase
	else
	  write_buf <= {write_buf[6:0], 1'b1};
      else if( clk_cnt == CLK_DIV2) begin
	 if(write_byte_cnt == 10'd517) // receive data response
	   write_data_response  <= {write_data_response[6:0], i_sd_miso};
      end
      else if( clk_cnt == CLK_DIV - 1)
	if(write_bit_cnt == 7) begin
	   write_bit_cnt <= 0;
	   write_byte_cnt <= write_byte_cnt + 1'd1;
	end
	else
	  write_bit_cnt <= write_bit_cnt + 1'd1;
  
  // o_sd_mosi
  assign o_sd_mosi = (state == S_WRITE_DATA) ?
		     write_buf[7]:  // data packet
		     send_buf[55];  // command

// command_buf at newstate (clk_cnt == 0)
  always@(posedge clk)
    if( ~reset_n )
      command_buf <= 48'hff_ffff_ffff_ff;
    else if( newstate )
      case(state)
	S_INIT_CMD0: command_buf <=  {2'b01, 6'd0,  32'h0,   7'b1001010, 1'b1};
	S_INIT_CMD8: command_buf <=  {2'b01, 6'd8,  32'h1aa, 7'b1000011, 1'b1};
	S_INIT_CMD16: command_buf <= {2'b01, 6'd16, 32'h200, 8'h01};
	S_INIT_CMD55: command_buf <= {2'b01, 6'd55, 32'h0,   8'h01};
	S_INIT_ACMD41:
	  command_buf <= (sd_version == SD_VERSION1) ?
			 {2'b01, 6'd41, 32'h00000000, 8'h01} :
			 {2'b01, 6'd41, 32'h40000000, 8'h01};
	S_INIT_CMD58:  command_buf <= {2'b01, 6'd58, 32'h0, 8'h01};
	S_READ_CMD:    command_buf <= {2'b01, 6'd17, sd_address, 8'h01};
	S_WRITE_CMD:   command_buf <= {2'b01, 6'd24, sd_address, 8'h01};
	default:
	  command_buf <= 48'hff_ffff_ffff_ff;
      endcase

  always@(posedge clk)
    if( ~reset_n ) begin
       state <= S_INIT_RESET;
       sd_version <= SD_VERSION1;
       sd_error <= ERROR_NOERROR;
       sd_addressmode_block <= 0;
    end
    else if(clk_cnt == CLK_DIV -1) // state change at (clk_cnt=CLK_DIV -1)
      case(state)
	S_INIT_RESET: // wait on reset
	  if(reset_cnt == WIDTH_RESET)
	    state <= S_INIT_DUMMY;

	S_INIT_DUMMY: // send dummy clock
	  if(dummy_bit_cnt == NUM_DUMMY_CLK)
	    state <= S_INIT_CMD0;

	S_INIT_CMD0: // send CMD0
	  if( r1_received )
	    if(r1_buf == 8'b1)
	      state <= S_INIT_CMD8;
	    else
	      {state, sd_error} <= {S_ERROR, ERROR_CMD0};

	S_INIT_CMD8:
	  if( r7_received ) begin
	     state <= S_INIT_CMD55;
	     if(r7_buf[11:0] == 12'h1aa)
	       sd_version <= SD_VERSION2;
	  end
	       
	S_INIT_CMD55:
	  if( r1_received )
	    state <= S_INIT_ACMD41;

	S_INIT_ACMD41:
	  if( r1_received )
	    if( r1_buf == 8'b0 )
	      if( sd_version == SD_VERSION1)
		 state <= S_INIT_CMD16;
	      else // version 2
		state <= S_INIT_CMD58;
	    else if( r1_buf == 8'b1 )
	      state <= S_INIT_ACMD41_RTY;
	    else 
	      {state, sd_error} <= {S_ERROR, ERROR_ACMD41};
	
	S_INIT_ACMD41_RTY:
	   state <= S_INIT_CMD55;
	
	S_INIT_CMD58:
	  if( r3_received )
	    if( r3_buf[30] == 1'b1 ) begin // sdhc and sdxc
	       sd_addressmode_block <= 1'b1;
	       state <= S_IDLE;
	    end
	    else  // sdsc
	      state <= S_INIT_CMD16;

	S_INIT_CMD16:
	  if( r1_received )
	    if( r1_buf == 8'b0 )
	       state <= S_IDLE;

	S_IDLE:
	  if( sd_read ) begin
	     state <= S_READ_START;
	     disk_block_address <= i_disk_block_address;
	     dma_start_address  <= i_dma_start_address;
	     dma_bytecount      <= {i_dma_wordcount, 1'b0};
	  end
	  else if( sd_write ) begin
	     state <= S_WRITE_START;
	     disk_block_address <= i_disk_block_address;
	     dma_start_address  <= i_dma_start_address;
	     dma_bytecount      <= {i_dma_wordcount, 1'b0};
	  end
	  else if( i_disk_seek )  // dummy function
	    state <= S_SEEK;
	
	S_READ_START:
	  if( dma_bytecount[16] ) begin
	     state <= S_READ_CMD;
	     if( dma_bytecount[15:9] == 8'b1111_111) begin
		dma_bytecount <= 17'h0_0000;
		this_bytecount <= {1'b1, dma_bytecount[8:0]};
	     end
	     else begin
		dma_bytecount[16:9] <= dma_bytecount[16:9] + 1'b1;
		this_bytecount <= 10'h200;
		// 10'h200=2's complement of 10'h200(=512byte)
	     end
	  end
	  else
	    state <= S_WAIT;

	S_READ_CMD:
	  if( r1_received )
	    if( r1_buf == 8'b0 )
	      state <= S_READ_DATA;
	    else
	      {state, sd_error} <= {S_ERROR, ERROR_CMD17};
	
	S_READ_DATA:
	  if( read_data_done )
	    if( read_before_write )
	      state <= S_WRITE_START;
	    else
	      state <= S_READ_CONTINUE;

	S_READ_CONTINUE: begin
	   dma_start_address <= dma_start_address + 10'd512;
	   disk_block_address <= disk_block_address + 1'd1;
	   state <= S_READ_START;
	end

	S_WRITE_START:
	  if( dma_bytecount[16] ) begin
	     if( dma_bytecount[15:9] == 8'b1111_111) begin
		if( dma_bytecount[8:0] == 9'b0  // wc==512byte
		    | read_before_write         // or buffer prepared
		    ) begin
		   dma_bytecount     <= 17'h0_0000;
		   this_bytecount    <= {1'b1, dma_bytecount[8:0]};
		   read_before_write <= 0;
		   state             <= S_WRITE_CMD;
		end
		else begin  // read block when wc < 512byte
		   read_before_write <= 1'b1;
		   this_bytecount    <= 10'h200;
		   state             <= S_READ_CMD;
		end
	     end
	     else begin
		dma_bytecount[16:9] <= dma_bytecount[16:9] + 1'b1;
		this_bytecount <= 10'h200;
		// 10'h200=2's complement of 10'h200(=512byte)
		read_before_write  <= 0;
		state <= S_WRITE_CMD;
	     end
	  end
	  else
	    state <= S_WAIT;

	S_WRITE_CMD:
	  if( r1_received )
	    if( r1_buf == 8'b0 )
	       state <= S_WRITE_DATA;
	    else
	       {state, sd_error} <= {S_ERROR, ERROR_CMD24};
	
	S_WRITE_DATA:
	  if( write_data_done )
	    if( write_data_response[4:0] == 5'b0_010_1)
	      state <= S_WRITE_BUSY;
	    else
	      {state, sd_error} <= {S_ERROR, ERROR_WRITE_DATA};

	S_WRITE_BUSY:
	  if( i_sd_miso )
	    state <= S_WRITE_CONTINUE;
	
	S_WRITE_CONTINUE: begin
	   dma_start_address <= dma_start_address + 10'd512;
	   disk_block_address <= disk_block_address + 1'd1;
	   state <= S_WRITE_START;
	end

	S_SEEK:
	  if( seek_done)
	    state <= S_WAIT;

	S_WAIT:
	  if( ~sd_read & ~sd_write & ~i_disk_seek)
	    state <= S_IDLE;

	S_ERROR:;

	default:;
      endcase

endmodule 
