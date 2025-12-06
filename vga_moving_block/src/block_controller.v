`timescale 1ns / 1ps

module block_controller(
    input clk,
    input mastClk,
    input bright,
    input rst,
    input up, input down, input left, input right,
    input [9:0] hCount, vCount,
    output reg [11:0] rgb,
    output reg [11:0] background,
    output wire [15:0] score_out
);
   
    parameter TILE_SIZE = 30;
    parameter GAP_SIZE = 4;
    parameter GRID_START_X = 400;
    parameter GRID_START_Y = 200;
    parameter BORDER_THICKNESS = 8;  // NEW: Border width in pixels
   
    wire [79:0] board_flat;
    wire [15:0] game_score;
    wire game_over;
    wire game_won;
    wire [1:0] cursor_col;
    wire [4:0] spawn_val;
    wire display_ready;
    
    reg [79:0] board_flat_sync;
    reg [79:0] board_flat_display;
    reg [15:0] game_score_sync;
    reg game_over_sync;
    reg game_won_sync;
    reg [1:0] cursor_col_sync;
    reg [4:0] spawn_val_sync;
    reg [4:0] spawn_val_display;
    reg display_ready_sync;
    
    always @(posedge mastClk or posedge rst) begin
        if (rst) begin
            board_flat_sync <= 80'd0;
            board_flat_display <= 80'd0;
            game_score_sync <= 16'd0;
            game_over_sync <= 1'b0;
            game_won_sync <= 1'b0;
            cursor_col_sync <= 2'd0;
            spawn_val_sync <= 5'd1;
            spawn_val_display <= 5'd1;
            display_ready_sync <= 1'b1;
        end else begin
            board_flat_sync <= board_flat;
            game_score_sync <= game_score;
            game_over_sync <= game_over;
            game_won_sync <= game_won;
            cursor_col_sync <= cursor_col;
            spawn_val_sync <= spawn_val;
            display_ready_sync <= display_ready;
            
            if (display_ready) begin
                board_flat_display <= board_flat_sync;
                spawn_val_display <= spawn_val_sync;
            end
        end
    end
   
    wire [4:0] grid [0:3][0:3];
    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : row_gen
            for (c = 0; c < 4; c = c + 1) begin : col_gen
                assign grid[r][c] = board_flat_display[((r*4 + c)*5) +: 5];
            end
        end
    endgenerate
   
    tetris_2048_core game_core (
        .clk(mastClk),
        .rst(rst),
        .btn_l(left),
        .btn_r(right),
        .btn_drop(down),
        .board_flat(board_flat),
        .score(game_score),
        .game_over(game_over),
        .game_won(game_won),
        .cursor_col(cursor_col),
        .spawn_val(spawn_val),
        .display_ready(display_ready)
    );
   
    assign score_out = game_score_sync;
   
    wire [11:0] rom_data_2, rom_data_4, rom_data_8, rom_data_16;
    wire [11:0] rom_data_32, rom_data_64, rom_data_128, rom_data_256;
    wire [11:0] rom_data_512, rom_data_1024, rom_data_2048;
    wire [4:0] rom_row, rom_col;

    tile_rom_2    tile_2    (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_2));
    tile_rom_4    tile_4    (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_4));
    tile_rom_8    tile_8    (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_8));
    tile_rom_16   tile_16   (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_16));
    tile_rom_32   tile_32   (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_32));
    tile_rom_64   tile_64   (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_64));
    tile_rom_128  tile_128  (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_128));
    tile_rom_256  tile_256  (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_256));
    tile_rom_512  tile_512  (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_512));
    tile_rom_1024 tile_1024 (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_1024));
    tile_rom_2048 tile_2048 (.clk(mastClk), .row(rom_row), .col(rom_col), .color_data(rom_data_2048));

    // Grid dimensions
    wire [9:0] GRID_WIDTH = 4*TILE_SIZE + 5*GAP_SIZE;
    wire [9:0] GRID_HEIGHT = 4*TILE_SIZE + 5*GAP_SIZE;
    
    // NEW: Border detection
    wire in_border;
    assign in_border = (hCount >= GRID_START_X - BORDER_THICKNESS && 
                       hCount < GRID_START_X + GRID_WIDTH + BORDER_THICKNESS &&
                       vCount >= GRID_START_Y - BORDER_THICKNESS && 
                       vCount < GRID_START_Y + GRID_HEIGHT + BORDER_THICKNESS) &&
                      !(hCount >= GRID_START_X && 
                        hCount < GRID_START_X + GRID_WIDTH &&
                        vCount >= GRID_START_Y && 
                        vCount < GRID_START_Y + GRID_HEIGHT);

    // Pipeline stage
    wire [9:0] rel_x, rel_y;
    reg [1:0] grid_col_stage1, grid_row_stage1;
    reg [9:0] cell_pos_x_stage1, cell_pos_y_stage1;
    reg in_grid_area_stage1;
    reg in_border_stage1;  // NEW: Register border signal
    reg [9:0] hCount_stage1, vCount_stage1;
    
    assign rel_x = hCount - GRID_START_X;
    assign rel_y = vCount - GRID_START_Y;
    
    wire in_grid_area_comb;
    assign in_grid_area_comb = (hCount >= GRID_START_X) &&
                               (hCount < GRID_START_X + GRID_WIDTH) &&
                               (vCount >= GRID_START_Y) &&
                               (vCount < GRID_START_Y + GRID_HEIGHT);
    
    always @(posedge mastClk) begin
        grid_col_stage1 <= (rel_x) / (TILE_SIZE + GAP_SIZE);
        grid_row_stage1 <= (rel_y) / (TILE_SIZE + GAP_SIZE);
        cell_pos_x_stage1 <= rel_x % (TILE_SIZE + GAP_SIZE);
        cell_pos_y_stage1 <= rel_y % (TILE_SIZE + GAP_SIZE);
        in_grid_area_stage1 <= in_grid_area_comb;
        in_border_stage1 <= in_border;  // NEW: Register border
        hCount_stage1 <= hCount;
        vCount_stage1 <= vCount;
    end
    
    wire [1:0] grid_col_use, grid_row_use;
    wire [5:0] tile_x, tile_y;
    wire in_gap, in_tile;
    
    assign grid_col_use = grid_col_stage1;
    assign grid_row_use = grid_row_stage1;
    assign in_gap = (cell_pos_x_stage1 < GAP_SIZE) || (cell_pos_y_stage1 < GAP_SIZE);
    assign in_tile = in_grid_area_stage1 && !in_gap;
    assign tile_x = cell_pos_x_stage1 - GAP_SIZE;
    assign tile_y = cell_pos_y_stage1 - GAP_SIZE;
   
    wire [4:0] current_tile;
    assign current_tile = grid[grid_row_use][grid_col_use];
   
    // Spawn tile preview
    wire in_cursor_area;
    wire [9:0] preview_offset_x, preview_offset_y;
    wire [5:0] preview_tile_x, preview_tile_y;
    wire in_preview_tile;

    assign in_cursor_area = (grid_col_use == cursor_col_sync) && 
                            (vCount_stage1 >= GRID_START_Y - 40) &&
                            (vCount_stage1 < GRID_START_Y - 10) &&
                            (hCount_stage1 >= GRID_START_X + GAP_SIZE + cursor_col_sync * (TILE_SIZE + GAP_SIZE)) &&
                            (hCount_stage1 < GRID_START_X + GAP_SIZE + cursor_col_sync * (TILE_SIZE + GAP_SIZE) + TILE_SIZE);

    assign preview_offset_x = hCount_stage1 - (GRID_START_X + GAP_SIZE + cursor_col_sync * (TILE_SIZE + GAP_SIZE));
    assign preview_offset_y = vCount_stage1 - (GRID_START_Y - 40);
    assign preview_tile_x = preview_offset_x[5:0];
    assign preview_tile_y = preview_offset_y[5:0];

    assign in_preview_tile = in_cursor_area && 
                             (preview_tile_y < TILE_SIZE) && 
                             (preview_tile_x < TILE_SIZE) &&
                             display_ready_sync;
   
    wire [4:0] active_rom_row, active_rom_col;
    assign active_rom_row = in_preview_tile ? preview_tile_y[4:0] : tile_y[4:0];
    assign active_rom_col = in_preview_tile ? preview_tile_x[4:0] : tile_x[4:0];
    assign rom_row = active_rom_row;
    assign rom_col = active_rom_col;
   
    reg [11:0] selected_tile_color;
    always @(*) begin
        case(current_tile)
            5'd0:  selected_tile_color = 12'hCCC;
            5'd1:  selected_tile_color = rom_data_2;
            5'd2:  selected_tile_color = rom_data_4;
            5'd3:  selected_tile_color = rom_data_8;
            5'd4:  selected_tile_color = rom_data_16;
            5'd5:  selected_tile_color = rom_data_32;
            5'd6:  selected_tile_color = rom_data_64;
            5'd7:  selected_tile_color = rom_data_128;
            5'd8:  selected_tile_color = rom_data_256;
            5'd9:  selected_tile_color = rom_data_512;
            5'd10: selected_tile_color = rom_data_1024;
            5'd11: selected_tile_color = rom_data_2048;
            default: selected_tile_color = 12'h000;
        endcase
    end
    
    reg [11:0] preview_tile_color;
    always @(*) begin
        case(spawn_val_display)
            5'd1:  preview_tile_color = rom_data_2;
            5'd2:  preview_tile_color = rom_data_4;
            5'd3:  preview_tile_color = rom_data_8;
            5'd4:  preview_tile_color = rom_data_16;
            5'd5:  preview_tile_color = rom_data_32;
            5'd6:  preview_tile_color = rom_data_64;
            5'd7:  preview_tile_color = rom_data_128;
            5'd8:  preview_tile_color = rom_data_256;
            5'd9:  preview_tile_color = rom_data_512;
            5'd10: preview_tile_color = rom_data_1024;
            5'd11: preview_tile_color = rom_data_2048;
            default: preview_tile_color = 12'h000;
        endcase
    end
   
    // RGB output with border support
    always @(*) begin
        if (~bright)
            rgb = 12'h000;
        else if (in_border_stage1 && game_won_sync)  // NEW: Green border for win
            rgb = 12'h0F0;
        else if (in_border_stage1 && game_over_sync)  // NEW: Red border for lose
            rgb = 12'hF00;
        else if (in_preview_tile)
            rgb = preview_tile_color;
        else if (in_gap && in_grid_area_stage1)
            rgb = 12'hFFF;
        else if (in_tile)
            rgb = selected_tile_color;
        else
            rgb = background;
    end
   
    always @(posedge mastClk or posedge rst) begin
        if (rst)
            background <= 12'h000;
        else
            background <= 12'h000;
    end

endmodule
