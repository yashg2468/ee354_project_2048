module bin2bcd(
    input [15:0] binary,
    output reg [3:0] thousands,
    output reg [3:0] hundreds,
    output reg [3:0] tens,
    output reg [3:0] ones
);

    integer i;
    always @(*) begin
        thousands = 0;
        hundreds = 0;
        tens = 0;
        ones = 0;
        
        for (i = 15; i >= 0; i = i - 1) begin
            // Shift left
            thousands = thousands << 1;
            thousands[0] = hundreds[3];
            hundreds = hundreds << 1;
            hundreds[0] = tens[3];
            tens = tens << 1;
            tens[0] = ones[3];
            ones = ones << 1;
            ones[0] = binary[i];
            
            // Add 3 if >= 5 (BCD correction)
            if (ones >= 5) ones = ones + 3;
            if (tens >= 5) tens = tens + 3;
            if (hundreds >= 5) hundreds = hundreds + 3;
            if (thousands >= 5) thousands = thousands + 3;
        end
    end

endmodule
