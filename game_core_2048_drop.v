//needs adhish state machine 
`timescale 1ns/1ps

module game_core_2048_drop(
    input         clk,
    input         rst_n,
    input  [1:0]  col_sel,
    input         drop_pulse,

    output reg [5:0] board_e00, output reg [5:0] board_e01,
    output reg [5:0] board_e02, output reg [5:0] board_e03,

    output reg [5:0] board_e10, output reg [5:0] board_e11,
    output reg [5:0] board_e12, output reg [5:0] board_e13,

    output reg [5:0] board_e20, output reg [5:0] board_e21,
    output reg [5:0] board_e22, output reg [5:0] board_e23,

    output reg [5:0] board_e30, output reg [5:0] board_e31,
    output reg [5:0] board_e32, output reg [5:0] board_e33,

    output reg [31:0] score,
    output reg        game_over,
    output reg        game_win
);

  // LFSR for pseudo-random spawn (16-bit maximal)
  reg [15:0] lfsr;
  wire       lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

  // FSM state
  localparam S_IDLE      = 3'd0;
  localparam S_SPAWN     = 3'd1;
  localparam S_FALL      = 3'd2;
  localparam S_MERGE     = 3'd3;
  localparam S_CHECK_END = 3'd4;
  localparam S_GAMEOVER  = 3'd5;

  reg [2:0] state;
  reg [1:0] cur_col;
  reg [1:0] r_pos;      // current falling row (0=top .. 3=bottom)
  reg [31:0] add_score;

  // Temporaries for merge/compress on one column
  reg [5:0] v0, v1, v2, v3;   // top -> bottom

  // Helpers to read / write board cells by row/col index
  function [5:0] get_cell;
    input [1:0] r;
    input [1:0] c;
    begin
      case ({r,c})
        4'h0: get_cell = board_e00;
        4'h1: get_cell = board_e01;
        4'h2: get_cell = board_e02;
        4'h3: get_cell = board_e03;

        4'h4: get_cell = board_e10;
        4'h5: get_cell = board_e11;
        4'h6: get_cell = board_e12;
        4'h7: get_cell = board_e13;

        4'h8: get_cell = board_e20;
        4'h9: get_cell = board_e21;
        4'hA: get_cell = board_e22;
        4'hB: get_cell = board_e23;

        4'hC: get_cell = board_e30;
        4'hD: get_cell = board_e31;
        4'hE: get_cell = board_e32;
        4'hF: get_cell = board_e33;

        default: get_cell = 6'd0;
      endcase
    end
  endfunction

  task set_cell;
    input [1:0] r;
    input [1:0] c;
    input [5:0] val;
    begin
      case ({r,c})
        4'h0: board_e00 <= val;
        4'h1: board_e01 <= val;
        4'h2: board_e02 <= val;
        4'h3: board_e03 <= val;

        4'h4: board_e10 <= val;
        4'h5: board_e11 <= val;
        4'h6: board_e12 <= val;
        4'h7: board_e13 <= val;

        4'h8: board_e20 <= val;
        4'h9: board_e21 <= val;
        4'hA: board_e22 <= val;
        4'hB: board_e23 <= val;

        4'hC: board_e30 <= val;
        4'hD: board_e31 <= val;
        4'hE: board_e32 <= val;
        4'hF: board_e33 <= val;
      endcase
    end
  endtask

  // Sequential logic: LFSR + FSM
  integer pass;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset everything
      lfsr      <= 16'h1ACE;
      state     <= S_IDLE;
      cur_col   <= 2'd0;
      r_pos     <= 2'd0;
      add_score <= 32'd0;
      score     <= 32'd0;
      game_over <= 1'b0;
      game_win  <= 1'b0;

      board_e00 <= 6'd0; board_e01 <= 6'd0; board_e02 <= 6'd0; board_e03 <= 6'd0;
      board_e10 <= 6'd0; board_e11 <= 6'd0; board_e12 <= 6'd0; board_e13 <= 6'd0;
      board_e20 <= 6'd0; board_e21 <= 6'd0; board_e22 <= 6'd0; board_e23 <= 6'd0;
      board_e30 <= 6'd0; board_e31 <= 6'd0; board_e32 <= 6'd0; board_e33 <= 6'd0;
    end else begin
      // Advance LFSR every cycle
      lfsr <= {lfsr[14:0], lfsr_fb};

      case (state)
        // -------------------------------------------------------------------
        S_IDLE: begin
          add_score <= 32'd0;
          if (drop_pulse && !game_over) begin
            cur_col <= col_sel;
            state   <= S_SPAWN;
          end
        end

        // Spawn new tile at top of selected column
        S_SPAWN: begin
          // If top cell is occupied -> cannot spawn -> game over
          if (get_cell(2'd0, cur_col) != 6'd0) begin
            game_over <= 1'b1;
            state     <= S_GAMEOVER;
          end else begin
            //  ~87.5% chance 2, ~12.5% chance 4 using top 4 bits
            if (lfsr[15:12] < 4'd14)
              set_cell(2'd0, cur_col, 6'd1);   // exponent 1 = value 2
            else
              set_cell(2'd0, cur_col, 6'd2);   // exponent 2 = value 4

            r_pos <= 2'd0;
            state <= S_FALL;
          end
        end

        // Gravity: let tile fall down until it hits something or bottom
        S_FALL: begin
          if (r_pos < 2'd3 && get_cell(r_pos + 2'd1, cur_col) == 6'd0) begin
            // Move tile down one row
            set_cell(r_pos + 2'd1, cur_col, get_cell(r_pos, cur_col));
            set_cell(r_pos,         cur_col, 6'd0);
            r_pos <= r_pos + 2'd1;
          end else begin
            // Landed
            state <= S_MERGE;
          end
        end

        // Compress–merge–compress downward along cur_col
        S_MERGE: begin
          // Load current column into v0..v3 (top -> bottom)
          case (cur_col)
            2'd0: begin
              v0 = board_e00; v1 = board_e10; v2 = board_e20; v3 = board_e30;
            end
            2'd1: begin
              v0 = board_e01; v1 = board_e11; v2 = board_e21; v3 = board_e31;
            end
            2'd2: begin
              v0 = board_e02; v1 = board_e12; v2 = board_e22; v3 = board_e32;
            end
            2'd3: begin
              v0 = board_e03; v1 = board_e13; v2 = board_e23; v3 = board_e33;
            end
          endcase

          // First compress toward bottom (bubble zeros up)
          for (pass = 0; pass < 3; pass = pass + 1) begin
            if (v3 == 0 && v2 != 0) begin v3 = v2; v2 = 0; end
            if (v2 == 0 && v1 != 0) begin v2 = v1; v1 = 0; end
            if (v1 == 0 && v0 != 0) begin v1 = v0; v0 = 0; end
          end

          // Merge bottom-up, one pass, skip-on-merge
          add_score <= 32'd0;

          // pair (v3,v2)
          if (v3 != 0 && v3 == v2) begin
            v3 = v3 + 6'd1;
            v2 = 6'd0;
            add_score <= add_score + (32'd1 << v3);
          end else begin
            // pair (v2,v1)
            if (v2 != 0 && v2 == v1) begin
              v2 = v2 + 6'd1;
              v1 = 6'd0;
              add_score <= add_score + (32'd1 << v2);
            end else begin
              // pair (v1,v0)
              if (v1 != 0 && v1 == v0) begin
                v1 = v1 + 6'd1;
                v0 = 6'd0;
                add_score <= add_score + (32'd1 << v1);
              end
            end
          end

          // Second compress toward bottom
          for (pass = 0; pass < 3; pass = pass + 1) begin
            if (v3 == 0 && v2 != 0) begin v3 = v2; v2 = 0; end
            if (v2 == 0 && v1 != 0) begin v2 = v1; v1 = 0; end
            if (v1 == 0 && v0 != 0) begin v1 = v0; v0 = 0; end
          end

          // Write back updated column
          case (cur_col)
            2'd0: begin
              board_e00 <= v0; board_e10 <= v1; board_e20 <= v2; board_e30 <= v3;
            end
            2'd1: begin
              board_e01 <= v0; board_e11 <= v1; board_e21 <= v2; board_e31 <= v3;
            end
            2'd2: begin
              board_e02 <= v0; board_e12 <= v1; board_e22 <= v2; board_e32 <= v3;
            end
            2'd3: begin
              board_e03 <= v0; board_e13 <= v1; board_e23 <= v2; board_e33 <= v3;
            end
          endcase

          // Update score next cycle in CHECK_END
          state <= S_CHECK_END;
        end

        // Update score, check win / game over
        S_CHECK_END: begin
          score <= score + add_score;

          // Win if any cell exponent >= 11 (value 2048)
          if (board_e00 >= 6'd11 || board_e01 >= 6'd11 ||
              board_e02 >= 6'd11 || board_e03 >= 6'd11 ||
              board_e10 >= 6'd11 || board_e11 >= 6'd11 ||
              board_e12 >= 6'd11 || board_e13 >= 6'd11 ||
              board_e20 >= 6'd11 || board_e21 >= 6'd11 ||
              board_e22 >= 6'd11 || board_e23 >= 6'd11 ||
              board_e30 >= 6'd11 || board_e31 >= 6'd11 ||
              board_e32 >= 6'd11 || board_e33 >= 6'd11)
            game_win <= 1'b1;

          // Game over: top row all non-zero
          if (board_e00 != 0 && board_e01 != 0 &&
              board_e02 != 0 && board_e03 != 0) begin
            game_over <= 1'b1;
            state     <= S_GAMEOVER;
          end else begin
            state <= S_IDLE;
          end
        end

        S_GAMEOVER: begin
          // Stay here until reset
          state <= S_GAMEOVER;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
