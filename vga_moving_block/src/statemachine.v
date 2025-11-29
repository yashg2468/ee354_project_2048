`timescale 1ns / 1ps

module tetris_2048_core (
    input wire clk,
    input wire rst,
    input wire btn_l,
    input wire btn_r,
    input wire btn_drop,
    output reg [79:0] board_flat,
    output reg [15:0] score,
    output reg game_over,
    output reg game_won,
    output reg [1:0] cursor_col,
    output reg [4:0] spawn_val,
    output reg display_ready
);

    localparam STATE_RESET      = 3'd0;
    localparam STATE_SPAWN      = 3'd1;
    localparam STATE_INPUT      = 3'd2;
    localparam STATE_CALC_DROP  = 3'd3;
    localparam STATE_UPDATE     = 3'd4;
    localparam STATE_RECHECK    = 3'd5;
    localparam STATE_CHECK_LOSE = 3'd6;

    reg [2:0] state;
    reg [4:0] grid [0:3][0:3];

    reg [1:0] target_row;
    reg [1:0] target_col;
    reg should_merge;
    reg col_is_full;
    reg [4:0] merge_value;
   
    reg [4:0] max_power_on_board_comb;
    reg [4:0] max_power_on_board;
    reg [4:0] base_spawn_power;
    reg [2:0] rand_select;
   
    integer r_scan, c_scan;
    always @(*) begin
        max_power_on_board_comb = 0;
        for (r_scan=0; r_scan<4; r_scan=r_scan+1) begin
            for (c_scan=0; c_scan<4; c_scan=c_scan+1) begin
                if (grid[r_scan][c_scan] > max_power_on_board_comb)
                    max_power_on_board_comb = grid[r_scan][c_scan];
            end
        end
    end
   
    always @(posedge clk) begin
        if (rst)
            max_power_on_board <= 0;
        else
            max_power_on_board <= max_power_on_board_comb;
    end

    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (rst)
            lfsr <= 16'hACE1;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // Timer-based debouncing (10ms)
    parameter DEBOUNCE_TIME = 20'd1_000_000;
    
    reg [19:0] debounce_counter_l, debounce_counter_r, debounce_counter_drop;
    reg btn_l_stable, btn_r_stable, btn_drop_stable;
    reg btn_l_stable_last, btn_r_stable_last, btn_drop_stable_last;
    wire btn_l_edge, btn_r_edge, btn_drop_edge;
    
    always @(posedge clk) begin
        if (rst) begin
            debounce_counter_l <= 0;
            btn_l_stable <= 0;
            btn_l_stable_last <= 0;
        end else begin
            if (btn_l == btn_l_stable) begin
                debounce_counter_l <= 0;
            end else begin
                debounce_counter_l <= debounce_counter_l + 1;
                if (debounce_counter_l >= DEBOUNCE_TIME) begin
                    btn_l_stable <= btn_l;
                    debounce_counter_l <= 0;
                end
            end
            btn_l_stable_last <= btn_l_stable;
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            debounce_counter_r <= 0;
            btn_r_stable <= 0;
            btn_r_stable_last <= 0;
        end else begin
            if (btn_r == btn_r_stable) begin
                debounce_counter_r <= 0;
            end else begin
                debounce_counter_r <= debounce_counter_r + 1;
                if (debounce_counter_r >= DEBOUNCE_TIME) begin
                    btn_r_stable <= btn_r;
                    debounce_counter_r <= 0;
                end
            end
            btn_r_stable_last <= btn_r_stable;
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            debounce_counter_drop <= 0;
            btn_drop_stable <= 0;
            btn_drop_stable_last <= 0;
        end else begin
            if (btn_drop == btn_drop_stable) begin
                debounce_counter_drop <= 0;
            end else begin
                debounce_counter_drop <= debounce_counter_drop + 1;
                if (debounce_counter_drop >= DEBOUNCE_TIME) begin
                    btn_drop_stable <= btn_drop;
                    debounce_counter_drop <= 0;
                end
            end
            btn_drop_stable_last <= btn_drop_stable;
        end
    end
    
    assign btn_l_edge = btn_l_stable & ~btn_l_stable_last;
    assign btn_r_edge = btn_r_stable & ~btn_r_stable_last;
    assign btn_drop_edge = btn_drop_stable & ~btn_drop_stable_last;

    integer r, c;
    always @(posedge clk) begin
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                board_flat[((r*4 + c)*5) +: 5] <= grid[r][c];
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_RESET;
            display_ready <= 1;
        end else begin
           
            case (state)
           
                STATE_RESET: begin
                    score <= 0;
                    game_over <= 0;
                    game_won <= 0;
                    cursor_col <= 1;
                    for(r=0; r<4; r=r+1) for(c=0; c<4; c=c+1) grid[r][c] <= 0;
                    display_ready <= 1;
                    state <= STATE_SPAWN;
                end
               
                STATE_SPAWN: begin
                    cursor_col <= 1;
               
                    // UPDATED: Adjusted spawning probabilities
                    if (max_power_on_board < 4) begin
                        // Early game: 75% = 2, 25% = 4
                        rand_select = lfsr[2:0];
                        if (rand_select < 6)
                            spawn_val <= 1;  // 75% chance of 2
                        else
                            spawn_val <= 2;  // 25% chance of 4
                    end
                    else begin
                        // Mid/Late game: Reduced low tile frequency
                        rand_select = lfsr[2:0];  // 0-7
                       
                        if (rand_select < 5) begin
                            // 62.5%: High tiles [max-3, max-2, max-1]
                            base_spawn_power = max_power_on_board - 3;
                            spawn_val <= base_spawn_power + (lfsr[4:3] % 3);
                        end
                        else if (rand_select < 7) begin
                            // 25%: Mid tiles [max-5, max-4]
                            if (max_power_on_board >= 5)
                                spawn_val <= (max_power_on_board - 5) + (lfsr[5] ? 1 : 0);
                            else
                                spawn_val <= 1;
                        end
                        else begin
                            // 12.5%: Low tiles (2 or 4) - REDUCED from 25%
                            spawn_val <= (lfsr[6] ? 2 : 1);
                        end
                    end
               
                    display_ready <= 1;
                    state <= STATE_INPUT;
                end

                STATE_INPUT: begin
                    if (btn_l_edge && cursor_col > 0) begin
                        cursor_col <= cursor_col - 1;
                        display_ready <= 1;
                    end
                    else if (btn_r_edge && cursor_col < 3) begin
                        cursor_col <= cursor_col + 1;
                        display_ready <= 1;
                    end
                    else if (btn_drop_edge) begin
                        merge_value <= spawn_val;
                        target_col <= cursor_col;
                        display_ready <= 0;
                        state <= STATE_CALC_DROP;
                    end
                    else begin
                        display_ready <= 1;
                    end
                end

                STATE_CALC_DROP: begin
                    col_is_full <= 0;
                    should_merge <= 0;
                    display_ready <= 0;
                   
                    // Search from TOP DOWN for first landing position (no jumping)
                    if (grid[0][target_col] != 0) begin
                        if (grid[0][target_col] == merge_value) begin
                            target_row <= 0;
                            should_merge <= 1;
                        end else begin
                            col_is_full <= 1;
                        end
                    end
                    else if (grid[1][target_col] != 0) begin
                        if (grid[1][target_col] == merge_value) begin
                            target_row <= 1;
                            should_merge <= 1;
                        end else begin
                            target_row <= 0;
                            should_merge <= 0;
                        end
                    end
                    else if (grid[2][target_col] != 0) begin
                        if (grid[2][target_col] == merge_value) begin
                            target_row <= 2;
                            should_merge <= 1;
                        end else begin
                            target_row <= 1;
                            should_merge <= 0;
                        end
                    end
                    else if (grid[3][target_col] != 0) begin
                        if (grid[3][target_col] == merge_value) begin
                            target_row <= 3;
                            should_merge <= 1;
                        end else begin
                            target_row <= 2;
                            should_merge <= 0;
                        end
                    end
                    else begin
                        target_row <= 3;
                        should_merge <= 0;
                    end
                   
                    state <= STATE_UPDATE;
                end

                STATE_UPDATE: begin
                    display_ready <= 0;
                   
                    if (col_is_full) begin
                        game_over <= 1;
                        display_ready <= 1;
                        state <= STATE_CHECK_LOSE;
                    end else begin
                        if (should_merge) begin
                            grid[target_row][target_col] <= grid[target_row][target_col] + 1;
                            score <= score + (16'd1 << (grid[target_row][target_col] + 1));
                            merge_value <= grid[target_row][target_col] + 1;
                           
                            // Check for 2048 win
                            if (grid[target_row][target_col] + 1 == 11) begin
                                game_won <= 1;
                            end
                           
                            state <= STATE_RECHECK;
                        end else begin
                            grid[target_row][target_col] <= merge_value;
                            state <= STATE_RECHECK;
                        end
                    end
                end
               
                STATE_RECHECK: begin
                    should_merge <= 0;
                    display_ready <= 0;
                   
                    // Check ONLY vertical cascade (downward adjacent tile)
                    if (target_row < 3) begin
                        if (grid[target_row + 1][target_col] == merge_value) begin
                            // Adjacent tile below matches - cascade down
                            grid[target_row][target_col] <= 0;
                            target_row <= target_row + 1;
                            should_merge <= 1;
                            state <= STATE_UPDATE;
                        end else begin
                            // No match below - done cascading
                            display_ready <= 1;
                            if (game_won)
                                state <= STATE_CHECK_LOSE;
                            else
                                state <= STATE_SPAWN;
                        end
                    end else begin
                        // At bottom row - done cascading
                        display_ready <= 1;
                        if (game_won)
                            state <= STATE_CHECK_LOSE;
                        else
                            state <= STATE_SPAWN;
                    end
                end
               
                STATE_CHECK_LOSE: begin
                    display_ready <= 1;
                    if (rst) state <= STATE_RESET;
                end

            endcase
        end
    end

endmodule
