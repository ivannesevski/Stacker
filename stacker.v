// Stacker

module stacker
	(
		CLOCK_50,						//	On Board 50 MHz
		// Inputs and outputs
        KEY,
        SW,
		HEX0,
		HEX1,
		// The ports below are for the VGA output.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK,					    //	VGA BLANK
		VGA_SYNC,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B   						//	VGA Blue[9:0]
	);

	input			CLOCK_50;				//	50 MHz
	input   [9:0]   SW;
	input   [3:0]   KEY;
	output  [6:0]	HEX0, HEX1;

    // VGA outputs
	output			VGA_CLK;   				//	VGA Clock
	output			VGA_HS;					//	VGA H_SYNC
	output			VGA_VS;					//	VGA V_SYNC
	output			VGA_BLANK;				//	VGA BLANK
	output			VGA_SYNC;				//	VGA SYNC
	output	[9:0]	VGA_R;   				//	VGA Red[9:0]
	output	[9:0]	VGA_G;	 				//	VGA Green[9:0]
	output	[9:0]	VGA_B;   				//	VGA Blue[9:0]
	
	wire resetn;
	assign resetn = KEY[0];
	
	// Create the colour, x, y and writeEn wires that are inputs to the controller.
	wire [2:0] colour;
	wire [7:0] x;
	wire [6:0] y;
	wire writeEn;

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(resetn),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(writeEn),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK),
			.VGA_SYNC(VGA_SYNC),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "black.mif";
	
    // Keys for loading colours and dropping blocks
	wire go;
	assign go = ~KEY[1];
    wire drop;
    assign drop = ~KEY[2];
    
    // Counters
    wire [4:0] counter;
	wire [14:0] bg_counter;
    wire [1:0] counter_block;
    wire [1:0] counter_erase;
    
    // Variables
	wire ld_c;
    wire ld_m;
    wire mode;
	wire enable;
	wire bg_enable;
    wire bg_erase;
	wire draw;
	wire stack;
	wire erase;
    wire erase_missed;
	wire start;
	wire base;
	wire reset_x;
	wire top;
    wire [1:0] blocks_remaining;
    wire [1:0] blocks_missed;
	wire [7:0] score;
	
    // Instansiate datapath
	datapath d0(
        .clk(CLOCK_50),
        .resetn(resetn),
        .data_c(SW[9:7]),
        .data_m(SW[0]),
        .ld_c(ld_c),
        .ld_m(ld_m),
		.enable(enable),
        .base(base),
        .draw(draw),
        .erase(erase),
        .erase_missed(erase_missed),
        .stack(stack),
        .reset_x(reset_x),        
		.bg_enable(bg_enable),
		.bg_erase(bg_erase),
        
        .counter(counter),
		.bg_counter(bg_counter),
        .mode(mode),
		.top(top),
		.x_pos(x),
		.y_pos(y),
		.colour(colour),
        .blocks_remaining(blocks_remaining),
        .blocks_missed(blocks_missed),
        .counter_block(counter_block),
        .counter_erase(counter_erase),
        .score(score)
    );
	
    // Instansiate FSM control
    control c0(
        .clk(CLOCK_50),
        .resetn(resetn),
        .go(go),
        .drop(drop),
        .mode(mode),
        .top(top),
        .blocks_remaining(blocks_remaining),
        .blocks_missed(blocks_missed),
		.score(score),
		.bg_counter(bg_counter),
        .counter_block(counter_block),
        .counter_erase(counter_erase),
		
        .draw(draw),
        .ld_c(ld_c),
        .ld_m(ld_m),
        .enable(enable),
		.base(base),
        .start(start),
        .plot(writeEn),
        .erase(erase),
        .erase_missed(erase_missed),
        .stack(stack),
		.reset_x(reset_x),
		.bg_enable(bg_enable),
		.bg_erase(bg_erase)
    );
	
    // Instantiate Hex displays for score
	hex_decoder h0(.hex_digit(score[3:0]), .segments(HEX0));
	hex_decoder h1(.hex_digit(score[7:4]), .segments(HEX1));
    
endmodule

module control(
    input clk,
    input resetn,
    input go,
    input drop,
    input mode,
	input top,
    input [1:0] blocks_remaining,
    input [1:0] blocks_missed,
	input [7:0] score,
	input [14:0] bg_counter,
    input [1:0] counter_block,
    input [1:0] counter_erase,
	 
	output draw,
    output reg ld_c,
    output reg ld_m,
    output reg enable,
	output reg base,
    output reg start,
    output reg plot,
    output reg erase,
	output reg erase_missed,
    output reg stack,
	output reg reset_x,
	output reg bg_enable,
	output reg bg_erase
    );

    reg [5:0] current_state, next_state; 
    
    localparam  S_ERASE_SCREEN		= 5'd0,
                S_LOAD_C            = 5'd1,
                S_LOAD_C_WAIT   	= 5'd2,
                S_LOAD_M            = 5'd3,
                S_LOAD_M_WAIT       = 5'd4,
                S_DRAW_BASE			= 5'd5,
                S_FILL_PIXELS       = 5'd6,
                S_WAIT				= 5'd7,
				S_ERASE_PIXELS	    = 5'd8,
                S_STACK_WAIT		= 5'd9,
                S_STACK             = 5'd10,
                S_GAME_CHECK	    = 5'd11,
                S_ERASE_MISSED      = 5'd12,
				S_CONTINUE_STACK	= 5'd13,
                S_GAME_OVER         = 5'd14;
				
		
	ratedivider r0(.clock(clk), .resetn(resetn), .start_rate(start),  .mode(mode), .score(score), .draw(draw));
	 
    // Next state logic aka our state table
    always@(*)
    begin: state_table 
        case (current_state)
            S_ERASE_SCREEN: next_state = (bg_counter == 15'd16384) ? S_LOAD_C : S_ERASE_SCREEN;
            S_LOAD_C: next_state = go ? S_LOAD_C_WAIT : S_LOAD_C;
            S_LOAD_C_WAIT: next_state = go ? S_LOAD_C_WAIT : S_LOAD_M;
            S_LOAD_M: next_state = go ? S_LOAD_M_WAIT : S_LOAD_M;
            S_LOAD_M_WAIT: next_state = go ? S_LOAD_M_WAIT : S_DRAW_BASE;
            S_DRAW_BASE: next_state = (counter_block == blocks_remaining) ? S_FILL_PIXELS : S_DRAW_BASE;
            S_FILL_PIXELS: next_state = (counter_block == blocks_remaining) ? S_WAIT : S_FILL_PIXELS;
            S_WAIT: begin 
                if (draw)
                    next_state = S_ERASE_PIXELS;
                else if (drop)
                    next_state = S_STACK_WAIT;
                else
                    next_state = S_WAIT;
            end
            S_ERASE_PIXELS: next_state = (counter_block == blocks_remaining) ? S_FILL_PIXELS : S_ERASE_PIXELS;
            S_STACK_WAIT: next_state = drop ? S_STACK_WAIT : S_STACK;
            S_STACK: next_state = S_GAME_CHECK;
            S_GAME_CHECK: begin
                if (blocks_remaining == 2'b00)
                    next_state = S_GAME_OVER;
                else if (top)
                    next_state = S_CONTINUE_STACK;
                else 
                    next_state = S_ERASE_MISSED;
            end
            S_ERASE_MISSED: next_state = (counter_erase == blocks_missed) ? S_FILL_PIXELS : S_ERASE_MISSED;
            S_CONTINUE_STACK: next_state = (bg_counter == 15'd16384) ? S_DRAW_BASE : S_CONTINUE_STACK;
            S_GAME_OVER: next_state = S_GAME_OVER;					 
            default: next_state = S_ERASE_SCREEN;
        endcase
    end // state_table
   
    // Output logic aka all of our datapath control signals
    always @(*)
    begin: enable_signals
        // By default make all our signals 0
        ld_c = 1'b0;
        ld_m = 1'b0;
        enable = 1'b0;
        base = 1'b0;
		start = 1'b0;
		plot = 1'b0;
        erase = 1'b0;
        erase_missed = 1'b0;
        stack = 1'b0;
		reset_x = 1'b0;
		bg_enable = 1'b0;
		bg_erase = 1'b0;

         case (current_state)
            S_ERASE_SCREEN: begin
                plot = 1'b1;
                bg_enable = 1'b1;
                bg_erase = 1'b1;
            end
            S_LOAD_C: begin
                ld_c = 1'b1;
            end
            S_LOAD_M: begin
                ld_m = 1'b1;
            end
            S_DRAW_BASE: begin
                enable = 1'b1;
                base = 1'b1;
                plot = 1'b1;
            end
            S_FILL_PIXELS: begin
                enable = 1'b1;
                plot = 1'b1;
            end
            S_WAIT: begin
                start = 1'b1;
            end
            S_ERASE_PIXELS: begin
                enable = 1'b1;
                plot = 1'b1;
                erase = 1'b1;  
            end
            S_STACK: begin
                stack = 1'b1;
                reset_x = 1'b1;
            end
            S_ERASE_MISSED: begin
                enable = 1'b1;
                plot = 1'b1;
                erase_missed = 1'b1;
            S_CONTINUE_STACK: begin
            end
                plot = 1'b1;
                bg_enable = 1'b1;
                bg_erase = 1'b1;
            end
            // default:    // don't need default since we already made sure all of our outputs were assigned a value at the start of the always block
        endcase
    end // enable_signals
	
    // current_state registers
    always@(posedge clk)
    begin: state_FFs
        if(!resetn)
            current_state <= S_ERASE_SCREEN;
        else
            current_state <= next_state;
    end // state_FFS
endmodule

module datapath(
   input clk,
   input resetn,
   input [2:0] data_c,
   input data_m,
   input ld_c,
   input ld_m,
	input enable,
   input base,
   input draw,
   input erase,
	input erase_missed,
   input stack,
   input reset_x,
	input bg_enable,
	input bg_erase,
    
	output [4:0] counter,
	output [14:0] bg_counter,
   output reg mode,
	output reg top,
   output reg [7:0] x_pos,
	output reg [6:0] y_pos,
	output reg [2:0] colour,
   output reg [1:0] blocks_remaining,
   output reg [1:0] blocks_missed,
   output reg [1:0] counter_block,
   output reg [1:0] counter_erase,
   output reg [7:0] score
   );
	 
	block_counter k0(.clock(clk), .clear(resetn), .enable(enable), .q(counter)); 
   background_counter k1(.clock(clk), .clear(resetn), .enable(bg_enable), .q(bg_counter));
    
	reg [2:0] c;
	reg horizontal;
	
   always@(posedge clk) begin
        if(!resetn) begin
            c <= 3'b0;
            mode <= 1'b0;
				horizontal <= 1'b1;
        end
        else begin
            if (ld_c)
                c <= data_c;
            else if (ld_m)
                mode <= data_m;
					 
				if (counter_x == 8'd100)
                horizontal <= 1'b0;
            else if (counter_x == 8'd52)
                horizontal <= 1'b1;
        end
    end
 
    wire [7:0] counter_x;
    
	 reg prev_direction;
    reg [6:0] counter_y; 
    reg [7:0] x_edge;
    reg [7:0] erase_edge;
    
    xcordcounter k2(.clock(clk), .clear(resetn), .reset_x(reset_x), .enable(draw), .direction(horizontal), .blocks_remaining(blocks_remaining), .q(counter_x));
	 
    // Output coordinates and colour
    always@(posedge clk) begin
        if(!resetn) begin
            // Registers
            prev_direction <= 1'b1;
            counter_y <= 7'd112;
            x_edge <= 8'd76;
            erase_edge <= 8'd0;
            
            // Inputs/Outputs
            top <= 1'b0;
            x_pos <= 8'd0; 
				y_pos <= 7'd0;
				colour <= 3'd0;
            blocks_remaining <= 2'b11;
            blocks_missed <= 2'b00;
            counter_block <= 2'b00;
            counter_erase <= 2'b00;
				score <= 8'd0;	
        end
		  else begin
            if (base) begin // Draws multi-block base at start and when stack continued
                if (counter_block == blocks_remaining)
                    counter_block = 2'b00;
                if (counter != 5'd16) begin
                    colour <= c;
                    x_pos <= x_edge + counter[1:0] + (counter_block * 3'd4);
                    y_pos <= 7'd116 + counter[3:2];	
                end
                else
                    counter_block <= counter_block + 1'b1;
            end
            else if (erase) begin // Erases blocks from previous animation
                if (counter_block == blocks_remaining)
                    counter_block = 2'b00;
                if (counter != 5'd16) begin
                    colour <= 3'b0;
                    if (prev_direction == 1'b1) begin
                        x_pos <= counter_x + counter[1:0] - (3'd4 + (counter_block * 3'd4));
                        y_pos <= counter_y + counter[3:2];
                    end
                    else if (prev_direction == 1'b0) begin
                        x_pos <= counter_x + counter[1:0] + (3'd4 + (counter_block * 3'd4));
                        y_pos <= counter_y + counter[3:2];
                    end
                end
                else begin
                    counter_block = counter_block + 1'b1;
                    if (counter_block == blocks_remaining)
                        prev_direction <= horizontal;
                end
            end
            else if (stack) begin  // Checks where the block has been stacked (perfect or miss) and increases tower height
                if (counter_x < x_edge) begin
                    if ((counter_x == (x_edge - 3'd4)) && (blocks_remaining > 1'b1)) begin
                        blocks_remaining = blocks_remaining - 1'b1;
                        erase_edge <= counter_x;
                        blocks_missed <= 2'b01;
                    end
                    else if ((counter_x == (x_edge - 4'd8)) && (blocks_remaining == 2'b11)) begin
                        blocks_remaining = blocks_remaining - 2'b10;
                        erase_edge <= counter_x;
                        blocks_missed <= 2'b10;
                    end
                    else 
                        blocks_remaining = 2'b00;
                end
                else if (counter_x > x_edge) begin
                    if ((counter_x == (x_edge + 3'd4)) && (blocks_remaining == 2'b11)) begin
                        blocks_remaining = blocks_remaining - 1'b1;
                        x_edge <= x_edge + 3'd4;
                        erase_edge <= counter_x + 4'd8;
                         blocks_missed <= 2'b01;
                    end
                    else if ((counter_x == (x_edge + 3'd4)) && (blocks_remaining == 2'b10)) begin
                        blocks_remaining = blocks_remaining - 1'b1;
                        x_edge <= x_edge + 3'd4;
                        erase_edge <= counter_x + 3'd4;
                        blocks_missed <= 2'b01;
                    end
                    else if ((counter_x == (x_edge + 4'd8)) && (blocks_remaining == 2'b11)) begin
                        blocks_remaining = blocks_remaining - 2'b10;
                        x_edge <= x_edge + 4'd8;
                        erase_edge <= counter_x + 3'd4;
                        blocks_missed <= 2'b10;
                    end
                    else 
                        blocks_remaining = 2'b00;
                end
                if (blocks_remaining != 2'b00) begin
                    if (y_pos == 7'd0) begin
                        counter_y <= 7'd112;
                        top <= 1'b1;
                    end
                    else
                        counter_y <= counter_y - 3'd4; 
                    prev_direction <= 1'b1;
                    score <= score + 1'b1;
                end
            end
            else if (erase_missed) begin    // Erases missed blocks
                if (counter_erase == blocks_missed)
                    counter_erase = 2'b00;
                if (counter != 5'd16) begin
                    colour <= 3'd0;
                    x_pos <= erase_edge + counter[1:0] + (counter_erase * 3'd4);
                    y_pos <= counter_y + counter[3:2] + 3'd4;
                end
                else 
                    counter_erase = counter_erase + 1'b1;
            end
            else if (bg_erase) begin    // Erases all blocks that have been drawn
                top <= 1'b0;
                colour <= 3'd0;
                x_pos <= 8'b0 + bg_counter[6:0];
                y_pos <= 7'b0 + bg_counter[13:7]; 
            end
            else begin      // Draws the blocks
                if (counter_block == blocks_remaining)
                    counter_block = 2'b00;
                if (counter != 5'd16) begin
                    colour <= c; 
                    x_pos <= counter_x + counter[1:0] + (counter_block * 3'd4);
                    y_pos <= counter_y + counter[3:2];
                end
                else
                    counter_block <= counter_block + 1'b1;
            end
		end
    end
    
endmodule

// Increases the x and y values for drawing block pixels
module block_counter(clock, clear, enable, q);
	input clock;
	input clear;
	input enable;
    output reg [4:0] q;
	
	always @(posedge clock) 		    // triggered every time clock rises
	begin
		if (~clear) 			
			q <= 0;
      else if (q == 5'd16) 
         q <= 0;
		else if (enable == 1'b1) 	    // increment q only when enable is 1
			q <= q + 1'b1;			    // increment q
		else 
			q <= 0;
	end
	
endmodule

// Increases the x and y values for erasing all drawn block pixels
module background_counter(clock, clear, enable, q);
	input clock;
	input clear;
	input enable;
    output reg [14:0] q;
	
	always @(posedge clock) 		    // triggered every time clock rises
	begin
		if (~clear) 			
			q <= 0;
        else if (q == 15'd16384)
            q <= 0;
		else if (enable == 1'b1) 	    // increment q only when enable is 1
			q <= q + 1'b1;			    // increment q
	end
	
endmodule

// Increases the x value of the blocks being moved
module xcordcounter(clock, clear, reset_x, enable, direction, blocks_remaining, q);
	input clock;
	input clear;
    input reset_x;
	input enable;
	input direction;
    input [1:0] blocks_remaining;
    output reg [7:0] q;
	
	always @(posedge clock) 		// triggered every time clock rises
	begin
		if (~clear || reset_x) 			
			q <= 8'd52;					
		else if (enable == 1'b1) begin      // Increment q only when enable is 1
			if (direction)
				q <= q + 3'd4;              // Increment q by 4 if direction is right			
			else
				q <= q - 3'd4;              // Decrement q by 4 if direction is left
		end
	end
	
endmodule

// Rate divider for animation speed
module ratedivider(clock, resetn, start_rate, mode, score, draw);
	input clock;
	input resetn;
	input start_rate;
   input mode;
	input [7:0] score;
	output draw;
	
	reg [23:0] rate;
	
	always@(posedge clock)
	begin
		if (~resetn)
			rate <= 24'd12500000;
		else begin
			if (rate > 24'd2500000)
				rate <= 24'd12500000 - ((24'd200000 * (mode + 1'b1)) * score);     // Increases block movement speed as you get higher
		end
	end
	
	reg [23:0] count;
	
	always@(posedge clock)            				
	begin
		if (~resetn)
			count <= 24'd12500000;
		else if (start_rate) begin
			if (count > 0)
				count <= count - 1'b1;
			else 
				count <= rate;
		end
		else
			count <= rate;
	end
	
	assign draw = (count == 0) ? 1 : 0;
	
endmodule

module hex_decoder(hex_digit, segments);
    input [3:0] hex_digit;
    output reg [6:0] segments;
   
    always @(*)
        case (hex_digit)
            4'h0: segments = 7'b100_0000;
            4'h1: segments = 7'b111_1001;
            4'h2: segments = 7'b010_0100;
            4'h3: segments = 7'b011_0000;
            4'h4: segments = 7'b001_1001;
            4'h5: segments = 7'b001_0010;
            4'h6: segments = 7'b000_0010;
            4'h7: segments = 7'b111_1000;
            4'h8: segments = 7'b000_0000;
            4'h9: segments = 7'b001_1000;
            4'hA: segments = 7'b000_1000;
            4'hB: segments = 7'b000_0011;
            4'hC: segments = 7'b100_0110;
            4'hD: segments = 7'b010_0001;
            4'hE: segments = 7'b000_0110;
            4'hF: segments = 7'b000_1110;   
            default: segments = 7'h7f;
        endcase
endmodule 