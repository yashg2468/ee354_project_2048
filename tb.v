`timescale 1ns / 1ps

module tetris_2048_tb;

    // --- Inputs to DUT ---
    reg clk;
    reg rst;
    reg btn_l;
    reg btn_r;
    reg btn_drop;

    // --- Outputs from DUT ---
    wire [79:0] board_flat;
    wire [15:0] score;
    wire game_over;
    wire [1:0] cursor_col;
    wire [4:0] spawn_val;

    // --- Helper for Waveform Viewing ---
    // We unpack the flat board back into a 2D array 
    // just so you can see it easily in the simulator waveform window.
    reg [4:0] debug_grid [0:3][0:3];
    integer r, c;
    always @(*) begin
        for (r=0; r<4; r=r+1) begin
            for (c=0; c<4; c=c+1) begin
                debug_grid[r][c] = board_flat[((r*4 + c)*5) +: 5];
            end
        end
    end

    // --- Instantiate the Core ---
    tetris_2048_core dut (
        .clk(clk),
        .rst(rst),
        .btn_l(btn_l),
        .btn_r(btn_r),
        .btn_drop(btn_drop),
        .board_flat(board_flat),
        .score(score),
        .game_over(game_over),
        .cursor_col(cursor_col),
        .spawn_val(spawn_val)
    );

    // --- Clock Generation (10ns period = 100MHz) ---
    always #5 clk = ~clk;

    // --- TASKS to make testing easy ---

    // Task 1: Press a button for one clock cycle
    task press_btn_drop;
        begin
            @(posedge clk);
            btn_drop = 1;
            @(posedge clk);
            btn_drop = 0;
            // Wait a few cycles for FSM to process
            repeat(5) @(posedge clk); 
        end
    endtask

    // Task 2: Smart Move Cursor
    // This looks at where the cursor IS, and pulses Left/Right
    // until it gets to where we WANT it.
    task move_to_col(input [1:0] target);
        // FIX: Variable declaration must be BEFORE 'begin'
        integer safety; 
        begin
            safety = 0;
            
            while (cursor_col != target && safety < 10) begin
                @(posedge clk);
                if (cursor_col < target) begin
                    btn_r = 1;
                    @(posedge clk);
                    btn_r = 0;
                end else begin
                    btn_l = 1;
                    @(posedge clk);
                    btn_l = 0;
                end
                safety = safety + 1;
                // Wait for FSM to update cursor state
                repeat(2) @(posedge clk);
            end
        end
    endtask

    // Task 3: Visualizer
    task print_board;
        integer i, j;
        reg [15:0] decoded_val;
        begin
            $display("\n    +----+----+----+----+");
            for (i=0; i<4; i=i+1) begin
                $write("    |");
                for (j=0; j<4; j=j+1) begin
                    // Decode power to actual number (0 remains 0)
                    if (debug_grid[i][j] == 0) 
                        decoded_val = 0;
                    else
                        decoded_val = 1 << debug_grid[i][j];
                        
                    $write(" %4d |", decoded_val);
                end
                $display("\n    +----+----+----+----+");
            end
            $display("    Score: %d  |  Game Over: %b", score, game_over);
            $display("");
        end
    endtask

    // Task 4: Combine Move, Drop, and Print
    task drop_in_col(input [1:0] c);
        begin
            $display("ACTION: Moving to Col %0d -> Dropping %0d", c, (1 << spawn_val));
            move_to_col(c);
            press_btn_drop;
            print_board; // Show result immediately
        end
    endtask


    // --- MAIN TEST SCENARIO ---
    initial begin
        // 1. Initialize
        clk = 0;
        rst = 1;
        btn_l = 0;
        btn_r = 0;
        btn_drop = 0;
        
        $display("--- SIMULATION START ---");

        // 2. Reset Sequence
        #50;
        rst = 0;
        #20;
        
        $display("Initial Board:");
        print_board;

        // 3. Play the Game
        // Note: spawn_val is random, so the exact merges depend on the LFSR.
        // But we can test the mechanics of stacking.

        // Drop in Col 0 (Bottom Row)
        drop_in_col(0);
        
        // Drop in Col 1 (Bottom Row)
        drop_in_col(1);

        // Drop in Col 0 (Row 2 - Stack or Merge)
        drop_in_col(0);

        // Drop in Col 0 (Row 1)
        drop_in_col(0);
        
        // Drop in Col 0 (Row 0 - Top)
        drop_in_col(0);
        
        // Drop in Col 0 (Overflow? Should trigger Game Over or ignore)
        drop_in_col(0);
        
        // Drop in Col 3 just to see movement across board
        drop_in_col(3);

        // Wait to see results
        #100;
        
        if (game_over) 
            $display("--- GAME OVER TRIGGERED ---");
        else 
            $display("--- BOARD STILL ALIVE ---");

        $finish;
    end

endmodule
