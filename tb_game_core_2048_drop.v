`timescale 1ns/1ps

module tb_game_core_2048_drop;

  // Clock + Reset
  reg clk_100;
  reg rst_n;

  // Inputs to DUT
  reg [1:0] col_sel;
  reg       drop_pulse;

  // Outputs from DUT
  wire [5:0] board_e00, board_e01, board_e02, board_e03;
  wire [5:0] board_e10, board_e11, board_e12, board_e13;
  wire [5:0] board_e20, board_e21, board_e22, board_e23;
  wire [5:0] board_e30, board_e31, board_e32, board_e33;

  wire [31:0] score;
  wire game_over, game_win;

  // 100 MHz Clock
  initial clk_100 = 0;
  always #5 clk_100 = ~clk_100;

  // Reset
  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  // Instantiate DUT
  game_core_2048_drop dut (
    .clk(clk_100),
    .rst_n(rst_n),
    .col_sel(col_sel),
    .drop_pulse(drop_pulse),

    .board_e00(board_e00), .board_e01(board_e01),
    .board_e02(board_e02), .board_e03(board_e03),

    .board_e10(board_e10), .board_e11(board_e11),
    .board_e12(board_e12), .board_e13(board_e13),

    .board_e20(board_e20), .board_e21(board_e21),
    .board_e22(board_e22), .board_e23(board_e23),

    .board_e30(board_e30), .board_e31(board_e31),
    .board_e32(board_e32), .board_e33(board_e33),

    .score(score),
    .game_over(game_over),
    .game_win(game_win)
  );

  // Helper: simulate a drop in column c
  task do_drop(input [1:0] c);
  begin
    col_sel = c;
    drop_pulse = 1;
    @(posedge clk_100);
    drop_pulse = 0;

    // Allow FSM to finish fall + merge
    repeat(200) @(posedge clk_100);
  end
  endtask

  // Test scenarios
  initial begin
    drop_pulse = 0;
    col_sel = 0;

    @(posedge rst_n);
    #20;

    // Scenario 1: Drop into empty column
    $display("TEST 1 — Simple drop");
    do_drop(2);

    // Scenario 2: Trigger a merge
    $display("TEST 2 — Merge test");
    do_drop(1);
    do_drop(1);

    // Scenario 3: Multiple drops into same column
    $display("TEST 3 — Triple-equal stability");
    do_drop(0);
    do_drop(0);
    do_drop(0);

    // Scenario 4: Try to reach game_over
    $display("TEST 4 — Game Over attempt");
    repeat(40) begin
      do_drop($urandom % 4);
      if (game_over) begin
        $display("GAME OVER DETECTED");
        disable end_sim;
      end
    end

    end_sim: begin
      $display("Simulation complete.");
      #100;
      $finish;
    end
  end

endmodule
