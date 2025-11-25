`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module: tetris_2048_core
// Description: Core logic with Dynamic Spawning based on Board Max
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

    // --- 1. STATE & GRID DEFINITIONS ---
    localparam STATE_RESET      = 3'd0;
    localparam STATE_SPAWN      = 3'd1;
    localparam STATE_INPUT      = 3'd2;
    localparam STATE_CALC_DROP  = 3'd3;
    localparam STATE_UPDATE     = 3'd4;
    localparam STATE_CHECK_LOSE = 3'd5;

    reg [2:0] state;
    
    // Grid: 0=Empty, 1=2, 2=4, 3=8 ... 5=32 ...
    reg [4:0] grid [0:3][0:3]; 

    // --- 2. INTERNAL SIGNALS ---
    reg [1:0] target_row;
    reg       should_merge;
    reg       col_is_full;
    
    // --- 3. DYNAMIC SPAWN LOGIC ---
    reg [4:0] max_power_on_board;
    reg [4:0] base_spawn_power;
    reg [2:0] rand_select; // To hold 3 bits of randomness
    
    // Combinational block to find the highest tile currently on board
    integer r_scan, c_scan;
    always @(*) begin
        max_power_on_board = 0;
        for (r_scan=0; r_scan<4; r_scan=r_scan+1) begin
            for (c_scan=0; c_scan<4; c_scan=c_scan+1) begin
                if (grid[r_scan][c_scan] > max_power_on_board) 
                    max_power_on_board = grid[r_scan][c_scan];
            end
        end
    end

    // --- 4. RANDOM NUMBER GENERATOR (LFSR) ---
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (rst) 
            lfsr <= 16'hACE1;
        else 
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // --- 5. BUTTON EDGE DETECTION ---
    reg last_btn_l, last_btn_r, last_btn_drop;
    wire do_left, do_right, do_drop;

    always @(posedge clk) begin
        last_btn_l <= btn_l;
        last_btn_r <= btn_r;
        last_btn_drop <= btn_drop;
    end
    
    assign do_left  = btn_l & ~last_btn_l;
    assign do_right = btn_r & ~last_btn_r;
    assign do_drop  = btn_drop & ~last_btn_drop;

    // --- 6. FLATTEN GRID FOR OUTPUT ---
    integer r, c;
    always @(*) begin
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
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
            
                STATE_RESET: begin
                    score <= 0;
                    game_over <= 0;
                    cursor_col <= 1;
                    for(r=0; r<4; r=r+1) for(c=0; c<4; c=c+1) grid[r][c] <= 0;
                    state <= STATE_SPAWN;
                end

                STATE_SPAWN: begin
                    cursor_col <= 1; 

                    // --- DYNAMIC SPAWNING LOGIC START ---
                    
                    // 1. Calculate Base Power (Lowest of the 3 candidates)
                    // If Max is 32 (val 5), we want 4(val 2), 8(val 3), 16(val 4).
                    // Base = 5 - 3 = 2.
                    // If Max is small (< 4), Base is always 1 (Value 2).
                    if (max_power_on_board < 4)
                        base_spawn_power = 1;
                    else
                        base_spawn_power = max_power_on_board - 3;

                    // 2. Select specific tile based on weights
                    // We use 3 bits of LFSR (Values 0 to 7)
                    rand_select = lfsr[2:0];

                    if (rand_select < 5) begin
                        // 0,1,2,3,4 (5/8 chance) -> Lowest Value
                        spawn_val <= base_spawn_power;
                    end 
                    else if (rand_select < 7) begin
                        // 5,6 (2/8 chance) -> Middle Value
                        spawn_val <= base_spawn_power + 1;
                    end 
                    else begin
                        // 7 (1/8 chance) -> Highest Value
                        spawn_val <= base_spawn_power + 2;
                    end
                    // --- DYNAMIC SPAWNING LOGIC END ---

                    state <= STATE_INPUT;
                end

                STATE_INPUT: begin
                    if (do_left && cursor_col > 0) cursor_col <= cursor_col - 1;
                    if (do_right && cursor_col < 3) cursor_col <= cursor_col + 1;
                    if (do_drop) state <= STATE_CALC_DROP;
                end

                STATE_CALC_DROP: begin
                    col_is_full <= 0;
                    should_merge <= 0;
                    
                    // Priority Logic: Check Bottom (3) up to Top (0)
                    if (grid[3][cursor_col] == 0) begin
                        target_row <= 3;
                    end
                    else if (grid[3][cursor_col] == spawn_val) begin
                        target_row <= 3; should_merge <= 1;
                    end
                    else if (grid[2][cursor_col] == 0) begin
                        target_row <= 2;
                    end
                    else if (grid[2][cursor_col] == spawn_val) begin
                        target_row <= 2; should_merge <= 1;
                    end
                    else if (grid[1][cursor_col] == 0) begin
                        target_row <= 1;
                    end
                    else if (grid[1][cursor_col] == spawn_val) begin
                        target_row <= 1; should_merge <= 1;
                    end
                    else if (grid[0][cursor_col] == 0) begin
                        target_row <= 0;
                    end
                    else if (grid[0][cursor_col] == spawn_val) begin
                        target_row <= 0; should_merge <= 1;
                    end
                    else begin
                        col_is_full <= 1;
                    end
                    state <= STATE_UPDATE;
                end

                STATE_UPDATE: begin
                    if (col_is_full) begin
                        game_over <= 1;
                        state <= STATE_CHECK_LOSE;
                    end else begin
                        if (should_merge) begin
                            grid[target_row][cursor_col] <= grid[target_row][cursor_col] + 1;
                            score <= score + (16'd1 << (grid[target_row][cursor_col] + 1));
                        end else begin
                            grid[target_row][cursor_col] <= spawn_val;
                        end
                        state <= STATE_SPAWN;
                    end
                end
                
                STATE_CHECK_LOSE: begin
                    if (rst) state <= STATE_RESET;
                end

            endcase
        end
    end

endmodule
