`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module: tetris_2048_core
// 
// STUDENT NOTE:
// This module implements the main game loop.
// 1. It holds the 4x4 Grid in registers.
// 2. It accepts Left/Right/Drop inputs to move the cursor.
// 3. It calculates where the block lands and updates the grid.
//
// Inputs: 
//    clk      : System clock (e.g., 100MHz)
//    rst      : High-active reset (clears board)
//    btn_l    : Pulse to move Left
//    btn_r    : Pulse to move Right
//    btn_drop : Pulse to Drop tile
//
// Outputs:
//    board_flat      : 80-bit vector (16 cells * 5 bits) for your display module
//    score           : 16-bit integer score
//    game_over       : 1 if board is full
//    cursor_col      : The column (0-3) currently selected
//    spawn_val       : The value (1 or 2) of the tile waiting to drop
//////////////////////////////////////////////////////////////////////////////////

module tetris_2048_core (
    input wire clk,
    input wire rst,
    input wire btn_l,
    input wire btn_r,
    input wire btn_drop,
    output reg [79:0] board_flat,
    output reg [15:0] score,
    output reg game_over,
    output reg [1:0] cursor_col,
    output reg [4:0] spawn_val
);

    // --- 1. GAME STATE DEFINITIONS ---
    // We use a Finite State Machine (FSM) to control the flow.
    localparam STATE_RESET      = 3'd0; // Clear board
    localparam STATE_SPAWN      = 3'd1; // Create new piece
    localparam STATE_INPUT      = 3'd2; // Wait for player buttons
    localparam STATE_CALC_DROP  = 3'd3; // Figure out where piece lands
    localparam STATE_UPDATE     = 3'd4; // Write new grid values
    localparam STATE_CHECK_LOSE = 3'd5; // Did we lose?

    reg [2:0] state;

    // --- 2. GRID STORAGE ---
    // 4 rows, 4 columns. Each cell is 5 bits wide.
    // 0 = Empty, 1 = "2", 2 = "4", 3 = "8" ... 11 = "2048"
    reg [4:0] grid [0:3][0:3]; 
    
    // --- 3. INTERNAL HELPER SIGNALS ---
    reg [1:0] target_row;   // Which row (0-3) will we write to?
    reg       should_merge; // Do we add values (2+2) or just place (0->2)?
    reg       col_is_full;  // If we can't place the block anywhere
    
    // --- 4. RANDOM NUMBER GENERATOR (LFSR) ---
    // A simple shift register to generate pseudo-random numbers
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (rst) 
            lfsr <= 16'hACE1; // Seed value (non-zero)
        else 
            // Taps at bits 15, 13, 12, 10
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // --- 5. BUTTON EDGE DETECTION ---
    // We only want to react to the *moment* a button is pressed, not hold it.
    reg last_btn_l, last_btn_r, last_btn_drop;
    wire do_left, do_right, do_drop;

    always @(posedge clk) begin
        last_btn_l <= btn_l;
        last_btn_r <= btn_r;
        last_btn_drop <= btn_drop;
    end
    
    // High only on the rising edge
    assign do_left  = btn_l & ~last_btn_l;
    assign do_right = btn_r & ~last_btn_r;
    assign do_drop  = btn_drop & ~last_btn_drop;


    // --- 6. FLATTEN GRID FOR OUTPUT ---
    // Verilog doesn't let you output 2D arrays easily, so we flatten it
    // into one giant 1D array for your display controller to read.
    integer r, c;
    always @(*) begin
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                // Formula: Index = (Row * 4 + Col) * 5_bits
                board_flat[((r*4 + c)*5) +: 5] = grid[r][c];
            end
        end
    end


    // --- 7. MAIN STATE MACHINE ---
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_RESET;
        end else begin
            
            case (state)
            
                // Step 0: Clear everything
                STATE_RESET: begin
                    score <= 0;
                    game_over <= 0;
                    cursor_col <= 1;
                    // Reset all cells to 0
                    for(r=0; r<4; r=r+1) for(c=0; c<4; c=c+1) grid[r][c] <= 0;
                    state <= STATE_SPAWN;
                end

                // Step 1: Create a new piece
                STATE_SPAWN: begin
                    // Reset cursor to middle-left
                    cursor_col <= 1; 
                    
                    // Generate new value:
                    // Take the last 4 bits of random number. If > 1, make it a "2" (val 1).
                    // Otherwise make it a "4" (val 2). This gives ~90% chance of a "2".
                    spawn_val <= (lfsr[3:0] > 1) ? 5'd1 : 5'd2; 
                    
                    state <= STATE_INPUT;
                end

                // Step 2: Let player move. Wait for Drop.
                STATE_INPUT: begin
                    // Move Left (Check boundary > 0)
                    if (do_left && cursor_col > 0) 
                        cursor_col <= cursor_col - 1;
                        
                    // Move Right (Check boundary < 3)
                    if (do_right && cursor_col < 3) 
                        cursor_col <= cursor_col + 1;
                        
                    // Drop?
                    if (do_drop)
                        state <= STATE_CALC_DROP;
                end

                // Step 3: Calculate Physics (Where does it land?)
                // We check the selected column from Bottom (Row 3) up to Top (Row 0).
                STATE_CALC_DROP: begin
                    col_is_full <= 0;
                    should_merge <= 0;
                    
                    // CHECK ROW 3 (BOTTOM)
                    if (grid[3][cursor_col] == 0) begin
                        target_row <= 3;
                    end
                    else if (grid[3][cursor_col] == spawn_val) begin
                        target_row <= 3;
                        should_merge <= 1;
                    end
                    
                    // CHECK ROW 2
                    else if (grid[2][cursor_col] == 0) begin
                        target_row <= 2;
                    end
                    else if (grid[2][cursor_col] == spawn_val) begin
                        target_row <= 2;
                        should_merge <= 1;
                    end
                    
                    // CHECK ROW 1
                    else if (grid[1][cursor_col] == 0) begin
                        target_row <= 1;
                    end
                    else if (grid[1][cursor_col] == spawn_val) begin
                        target_row <= 1;
                        should_merge <= 1;
                    end
                    
                    // CHECK ROW 0 (TOP)
                    else if (grid[0][cursor_col] == 0) begin
                        target_row <= 0;
                    end
                    else if (grid[0][cursor_col] == spawn_val) begin
                        target_row <= 0;
                        should_merge <= 1;
                    end
                    
                    // NO SPACE LEFT
                    else begin
                        col_is_full <= 1;
                    end
                    
                    state <= STATE_UPDATE;
                end

                // Step 4: Write to Grid Memory
                STATE_UPDATE: begin
                    if (col_is_full) begin
                        // If user tried to drop in full column, GAME OVER
                        game_over <= 1;
                        state <= STATE_CHECK_LOSE;
                    end else begin
                        if (should_merge) begin
                            // Example: 2+2=4. Stored as 1+1=2.
                            // We increment the stored power.
                            grid[target_row][cursor_col] <= grid[target_row][cursor_col] + 1;
                            
                            // Score formula: score += 2^(new_power)
                            // We use bit shifting: 1 << power
                            score <= score + (16'd1 << (grid[target_row][cursor_col] + 1));
                        end else begin
                            // Just placing into empty spot
                            grid[target_row][cursor_col] <= spawn_val;
                        end
                        state <= STATE_SPAWN;
                    end
                end
                
                // Step 5: Game Over State
                STATE_CHECK_LOSE: begin
                    // Stuck here until Reset is pressed
                    if (rst) state <= STATE_RESET;
                end

            endcase
        end
    end

endmodule
