
module rom_memory #(
    parameter FILENAME = "", 
    parameter DEPTH = 784, 
    parameter WIDTH = 4
)(
    input clk,
    input [$clog2(DEPTH)-1:0] addr,
    output reg signed [WIDTH-1:0] data_out
);
    reg signed [WIDTH-1:0] memory [0:DEPTH-1];
	
integer k;
    initial begin
        // Initialize memory to 0 
        for ( k = 0; k < DEPTH; k = k + 1) memory[k] = 0;

        if (FILENAME != "") begin
            $readmemh(FILENAME, memory);
            $display("DEBUG: rom_memory loaded %s", FILENAME);
        end
    end

    always @(posedge clk) begin
        data_out <= memory[addr];
    end
endmodule

module ram_memory #(
    parameter FILENAME = "",
    parameter DEPTH = 784, 
    parameter WIDTH = 4
)(
    input clk,
    input wen,                   
    input [$clog2(DEPTH)-1:0] addr,
    input [WIDTH-1:0] data_in,
    output reg [WIDTH-1:0] data_out
);
    reg [WIDTH-1:0] memory [0:DEPTH-1];
	
 integer i;
    initial begin
        // Initialize memory 
       
        for (i = 0; i < DEPTH; i = i + 1) memory[i] = 0;

        if (FILENAME != "") begin
            $readmemh(FILENAME, memory);
            $display("DEBUG: ram_memory loaded %s (Depth: %d)", FILENAME, DEPTH);
        end
    end

    always @(posedge clk) begin
        if (wen) begin
            memory[addr] <= data_in;
        end
        data_out <= memory[addr];
    end
endmodule