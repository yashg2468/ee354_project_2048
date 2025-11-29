module vga_top(
    input ClkPort,
    input BtnC,
    input BtnU,
    input BtnR,
    input BtnL,
    input BtnD,
    //VGA signal
    output hSync, vSync,
    output [3:0] vgaR, vgaG, vgaB,
    
    //SSG signal 
    output An0, An1, An2, An3, An4, An5, An6, An7,
    output Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp,
    
    output QuadSpiFlashCS
);
    wire Reset;
    assign Reset=BtnC;
    wire bright;
    wire[9:0] hc, vc;
    wire[15:0] score;  // Now used for game score!
    wire up,down,left,right;
    wire [11:0] rgb;
    
    reg [3:0] SSD;
    wire [3:0] SSD3, SSD2, SSD1, SSD0;
    reg [7:0] SSD_CATHODES;
    wire [1:0] ssdscan_clk;
    
    reg [27:0] DIV_CLK;
    always @ (posedge ClkPort, posedge Reset)  
    begin : CLOCK_DIVIDER
      if (Reset)
            DIV_CLK <= 0;
      else
            DIV_CLK <= DIV_CLK + 1'b1;
    end
    
    wire move_clk;
    assign move_clk=DIV_CLK[19];
    wire [11:0] background;
    
    // Display controller
    display_controller dc(
        .clk(ClkPort), 
        .hSync(hSync), 
        .vSync(vSync), 
        .bright(bright), 
        .hCount(hc), 
        .vCount(vc)
    );
    
    // Block controller with game logic
    block_controller sc(
        .clk(move_clk), 
        .mastClk(ClkPort), 
        .bright(bright), 
        .rst(BtnC), 
        .up(BtnU), 
        .down(BtnD),
        .left(BtnL),
        .right(BtnR),
        .hCount(hc), 
        .vCount(vc), 
        .rgb(rgb), 
        .background(background),
        .score_out(score)  // ADD THIS LINE
    );
    
    assign vgaR = rgb[11 : 8];
    assign vgaG = rgb[7  : 4];
    assign vgaB = rgb[3  : 0];
    
    assign QuadSpiFlashCS = 1'b1;
    
    //------------
    // 7-Segment Display - Show Score in Decimal
    //------------
    
    // Display score in hex (4 digits can show up to 65535)
    assign SSD3 = score[15:12];
    assign SSD2 = score[11:8];
    assign SSD1 = score[7:4];
    assign SSD0 = score[3:0];

    assign ssdscan_clk = DIV_CLK[19:18];
    assign An0  = !(~(ssdscan_clk[1]) && ~(ssdscan_clk[0]));
    assign An1  = !(~(ssdscan_clk[1]) &&  (ssdscan_clk[0]));
    assign An2  =  !((ssdscan_clk[1]) && ~(ssdscan_clk[0]));
    assign An3  =  !((ssdscan_clk[1]) &&  (ssdscan_clk[0]));
    assign {An7, An6, An5, An4} = 4'b1111;
    
    always @ (ssdscan_clk, SSD0, SSD1, SSD2, SSD3)
    begin : SSD_SCAN_OUT
        case (ssdscan_clk) 
            2'b00: SSD = SSD0;
            2'b01: SSD = SSD1;
            2'b10: SSD = SSD2;
            2'b11: SSD = SSD3;
        endcase 
    end

    always @ (SSD) 
    begin : HEX_TO_SSD
        case (SSD)
            4'b0000: SSD_CATHODES = 8'b00000010; // 0
            4'b0001: SSD_CATHODES = 8'b10011110; // 1
            4'b0010: SSD_CATHODES = 8'b00100100; // 2
            4'b0011: SSD_CATHODES = 8'b00001100; // 3
            4'b0100: SSD_CATHODES = 8'b10011000; // 4
            4'b0101: SSD_CATHODES = 8'b01001000; // 5
            4'b0110: SSD_CATHODES = 8'b01000000; // 6
            4'b0111: SSD_CATHODES = 8'b00011110; // 7
            4'b1000: SSD_CATHODES = 8'b00000000; // 8
            4'b1001: SSD_CATHODES = 8'b00001000; // 9
            4'b1010: SSD_CATHODES = 8'b00010000; // A
            4'b1011: SSD_CATHODES = 8'b11000000; // B
            4'b1100: SSD_CATHODES = 8'b01100010; // C
            4'b1101: SSD_CATHODES = 8'b10000100; // D
            4'b1110: SSD_CATHODES = 8'b01100000; // E
            4'b1111: SSD_CATHODES = 8'b01110000; // F    
            default: SSD_CATHODES = 8'bXXXXXXXX;
        endcase
    end 
    
    assign {Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp} = {SSD_CATHODES};

endmodule
