module vga_top(
    input ClkPort,
    input BtnC,  // Reset
    input BtnU,
    input BtnD,
    input BtnL,
    input BtnR,
    // VGA outputs
    output hSync, vSync,
    output [3:0] vgaR, vgaG, vgaB,
    // 8 SSDs
    output An7, An6, An5, An4, An3, An2, An1, An0,  // All 8 anodes
    output Ca, Cb, Cc, Cd, Ce, Cf, Cg,
    output Dp,
    // Flash memory (if needed)
    output QuadSpiFlashCS
);

    wire bright;
    wire[9:0] hc, vc;
    wire[15:0] score;
    wire [11:0] rgb;
    wire clk, digclk;
    
    reg [3:0] SSD;
    wire [3:0] SSD0, SSD1, SSD2, SSD3, SSD4, SSD5, SSD6, SSD7;
    reg [7:0] SSD_CATHODES;
    reg [26:0] DIV_CLK;
    
    // Disable flash memory
    assign QuadSpiFlashCS = 1'b1;
    
    // Clock divider
    always @(posedge ClkPort) begin
        DIV_CLK <= DIV_CLK + 1'b1;
    end
    
    assign clk = ClkPort;  // 100MHz
    assign digclk = DIV_CLK[19];  // ~190Hz for SSD refresh
    
    // VGA display controller
    display_controller dc(
        .clk(clk),
        .hSync(hSync),
        .vSync(vSync),
        .bright(bright),
        .hCount(hc),
        .vCount(vc)
    );
    
    // Block controller with game logic
    block_controller bc(
        .clk(clk),
        .mastClk(clk),
        .bright(bright),
        .rst(BtnC),
        .up(BtnU),
        .down(BtnD),
        .left(BtnL),
        .right(BtnR),
        .hCount(hc),
        .vCount(vc),
        .rgb(rgb),
        .background(),
        .score_out(score)
    );
    
    // VGA color output
    assign vgaR = rgb[11:8];
    assign vgaG = rgb[7:4];
    assign vgaB = rgb[3:0];
    
    // ===== 8-DIGIT DECIMAL SCORE DISPLAY =====
    
    // Convert 16-bit score to 8 decimal digits using BCD
    wire [3:0] digit0, digit1, digit2, digit3, digit4;
    
    // Binary to BCD conversion for 5 digits (max 65535)
    bin2bcd converter(
        .binary(score),
        .thousands(digit4),
        .hundreds(digit3),
        .tens(digit2),
        .ones(digit1)
    );
    
    // Assign to SSDs (right-aligned, leading zeros blank)
    assign SSD0 = digit1;           // Ones
    assign SSD1 = digit2;           // Tens
    assign SSD2 = digit3;           // Hundreds
    assign SSD3 = digit4;           // Thousands
    assign SSD4 = (score >= 10000) ? ((score / 10000) % 10) : 4'd10;  // Ten-thousands (blank if 0)
    assign SSD5 = 4'd10;            // Blank
    assign SSD6 = 4'd10;            // Blank
    assign SSD7 = 4'd10;            // Blank
    
    // SSD multiplexing (scan through all 8 displays)
    reg [2:0] ssd_select;
    always @(posedge digclk) begin
        ssd_select <= ssd_select + 1;
    end
    
    // Select which SSD to display
    always @(*) begin
        case(ssd_select)
            3'd0: SSD = SSD0;
            3'd1: SSD = SSD1;
            3'd2: SSD = SSD2;
            3'd3: SSD = SSD3;
            3'd4: SSD = SSD4;
            3'd5: SSD = SSD5;
            3'd6: SSD = SSD6;
            3'd7: SSD = SSD7;
            default: SSD = 4'd10;
        endcase
    end
    
    // Anode control (active low) - one at a time
    assign {An7, An6, An5, An4, An3, An2, An1, An0} = ~(8'b00000001 << ssd_select);
    
    // 7-segment decoder
    always @(*) begin
        case(SSD)
            4'd0: SSD_CATHODES = 8'b00000011;  // 0
            4'd1: SSD_CATHODES = 8'b10011111;  // 1
            4'd2: SSD_CATHODES = 8'b00100101;  // 2
            4'd3: SSD_CATHODES = 8'b00001101;  // 3
            4'd4: SSD_CATHODES = 8'b10011001;  // 4
            4'd5: SSD_CATHODES = 8'b01001001;  // 5
            4'd6: SSD_CATHODES = 8'b01000001;  // 6
            4'd7: SSD_CATHODES = 8'b00011111;  // 7
            4'd8: SSD_CATHODES = 8'b00000001;  // 8
            4'd9: SSD_CATHODES = 8'b00001001;  // 9
            default: SSD_CATHODES = 8'b11111111;  // Blank
        endcase
    end
    
    assign {Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp} = SSD_CATHODES;

endmodule
