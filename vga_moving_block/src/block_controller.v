`timescale 1ns / 1ps

module block_controller(
	input clk, //this clock must be a slow enough clock to view the changing positions of the objects
	//input mastclk; // ASK SHRI IF THIS IS REQUIRED? 
	input bright,
	input rst,
	input up, input down, input left, input right,
	input [9:0] hCount, vCount,
	output reg [11:0] rgb,
	output reg [11:0] background
   );
	wire block_fill;
	
	//these two values dictate the center of the block, incrementing and decrementing them leads the block to move in certain directions
	reg [9:0] xpos, ypos;
	
	parameter RED   = 12'b1111_0000_0000;
	// instantiate the various blocks
	// ROM instances for each tile
	
	wire [11:0] rom_data_2, rom_data_4, rom_data_8, rom_data_16;
	wire [11:0] rom_data_32, rom_data_64, rom_data_128, rom_data_256;
	wire [11:0] rom_data_512, rom_data_1024, rom_data_2048;

	// Assuming each tile is 30x30 pixels
	wire [9:0] rom_addr;

	// Instantiate all tile ROM modules
    tile_rom_2 rom_inst_2 (
        .addr(rom_addr),
        .data(rom_data_2)
    );
    
    tile_rom_4 rom_inst_4 (
        .addr(rom_addr),
        .data(rom_data_4)
    );
    
    tile_rom_8 rom_inst_8 (
        .addr(rom_addr),
        .data(rom_data_8)
    );
    
    tile_rom_16 rom_inst_16 (
        .addr(rom_addr),
        .data(rom_data_16)
    );
    
    tile_rom_32 rom_inst_32 (
        .addr(rom_addr),
        .data(rom_data_32)
    );
    
    tile_rom_64 rom_inst_64 (
        .addr(rom_addr),
        .data(rom_data_64)
    );
    
    tile_rom_128 rom_inst_128 (
        .addr(rom_addr),
        .data(rom_data_128)
    );
    
    tile_rom_256 rom_inst_256 (
        .addr(rom_addr),
        .data(rom_data_256)
    );
    
    tile_rom_512 rom_inst_512 (
        .addr(rom_addr),
        .data(rom_data_512)
    );
    
    tile_rom_1024 rom_inst_1024 (
        .addr(rom_addr),
        .data(rom_data_1024)
    );
    
    tile_rom_2048 rom_inst_2048 (
        .addr(rom_addr),
        .data(rom_data_2048)
    );


    // Grid parameters
    parameter TILE_SIZE = 30;
    parameter TILE_GAP = 5;
    parameter GRID_START_X = 200;
    parameter GRID_START_Y = 100;
    
    // Determine which grid cell (0-3 for x and y)
    wire [1:0] grid_x, grid_y;
    wire [4:0] pixel_x, pixel_y;  // Position within the tile (0-29)
    wire in_tile;
    
    // Calculate grid position
    assign grid_x = (hCount - GRID_START_X) / (TILE_SIZE + TILE_GAP);
    assign grid_y = (vCount - GRID_START_Y) / (TILE_SIZE + TILE_GAP);
    
    // Calculate position within current tile
    assign pixel_x = (hCount - GRID_START_X) % (TILE_SIZE + TILE_GAP);
    assign pixel_y = (vCount - GRID_START_Y) % (TILE_SIZE + TILE_GAP);
    
    // Check if we're inside a tile (not in gap)
    assign in_tile = (pixel_x < TILE_SIZE) && (pixel_y < TILE_SIZE);
    
    // ROM address: row * width + column
    assign rom_addr = pixel_y * TILE_SIZE + pixel_x;

	    // Game state: 4x4 grid of tile values
    reg [3:0] grid [0:3][0:3];  // 0=empty, 1=2, 2=4, 3=8, etc.
    
    // Get current tile value at this grid position
    wire [3:0] current_tile_value;
    assign current_tile_value = grid[grid_y][grid_x];
    
    // Multiplexer: select ROM data based on tile value
    reg [11:0] selected_rom_data;
    always @(*) begin
        case(current_tile_value)
            4'd0:  selected_rom_data = 12'hCDC1B4;  // Empty tile color - modify? to black?
            4'd1:  selected_rom_data = rom_data_2;
            4'd2:  selected_rom_data = rom_data_4;
            4'd3:  selected_rom_data = rom_data_8;
            4'd4:  selected_rom_data = rom_data_16;
            4'd5:  selected_rom_data = rom_data_32;
            4'd6:  selected_rom_data = rom_data_64;
            4'd7:  selected_rom_data = rom_data_128;
            4'd8:  selected_rom_data = rom_data_256;
            4'd9:  selected_rom_data = rom_data_512;
            4'd10: selected_rom_data = rom_data_1024;
            4'd11: selected_rom_data = rom_data_2048;
            default: selected_rom_data = 12'h000;
        endcase
    end

	// Final RGB output
	/*when outputting the rgb value in an always block like this, make sure to include the if(~bright) statement, as this ensures the monitor 
	will output some data to every pixel and not just the images you are trying to display*/
    always @(*) begin
        if (~bright)
            rgb = 12'h000;  // Black outside display area
        else if (in_tile && (hCount >= GRID_START_X) && 
                 (hCount < GRID_START_X + 4*(TILE_SIZE + TILE_GAP)) &&
                 (vCount >= GRID_START_Y) && 
                 (vCount < GRID_START_Y + 4*(TILE_SIZE + TILE_GAP)))
            rgb = selected_rom_data;  // Display tile from ROM
        else
            rgb = background;  // Background color
    end

		//the +-5 for the positions give the dimension of the block (i.e. it will be 10x10 pixels)
	assign block_fill=vCount>=(ypos-15) && vCount<=(ypos+15) && hCount>=(xpos-15) && hCount<=(xpos+15); // changed to be 30*30 block at the centre for now 
	// for a certain (xpos, ypos) , a certain radius is assigned 1: effectively selecting the block

	// ACTUAL MOVEMENT
	always@(posedge clk, posedge rst) 
	begin
		if(rst)
		begin 
			//rough values for center of screen
			xpos<=450;
			ypos<=250;
		end
		else if (clk) begin
		
		/* Note that the top left of the screen does NOT correlate to vCount=0 and hCount=0. The display_controller.v file has the 
			synchronizing pulses for both the horizontal sync and the vertical sync begin at vcount=0 and hcount=0. Recall that after 
			the length of the pulse, there is also a short period called the back porch before the display area begins. So effectively, 
			the top left corner corresponds to (hcount,vcount)~(144,35). Which means with a 640x480 resolution, the bottom right corner 
			corresponds to ~(783,515).  
		*/
			if(right) begin
				xpos<=xpos+2; //change the amount you increment to make the speed faster 
				if(xpos==800) //these are rough values to attempt looping around, you can fine-tune them to make it more accurate- refer to the block comment above
					xpos<=150;
			end
			else if(left) begin
				xpos<=xpos-2;
				if(xpos==150)
					xpos<=800;
			end
			else if(up) begin
				ypos<=ypos-2;
				if(ypos==34)
					ypos<=514;
			end
			else if(down) begin
				ypos<=ypos+2;
				if(ypos==514)
					ypos<=34;
			end
		end
	end
	
	//the background color reflects the most recent button press
	always@(posedge clk, posedge rst) begin
		if(rst)
			background <= 12'b1111_1111_1111;
		else 
			if(right)
				background <= 12'b1111_1111_0000;
			else if(left)
				background <= 12'b0000_1111_1111;
			else if(down)
				background <= 12'b0000_1111_0000;
			else if(up)
				background <= 12'b0000_0000_1111;
	end

	
	
endmodule
