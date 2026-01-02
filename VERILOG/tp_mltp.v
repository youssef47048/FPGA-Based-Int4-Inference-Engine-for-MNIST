// ============================================================================
// File: tb_mlp.v
// ============================================================================
`timescale 1ns / 1ps

module tb_mlp;

    reg clk;
    reg reset;
    reg start;
    wire done;
    wire [3:0] predicted_class;

    mlp_top uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .predicted_class(predicted_class)
    );

    always #5 clk = ~clk;

    initial begin
        // For GTKWave or other waveform viewers
        $dumpfile("mlp_simulation.vcd");
        $dumpvars(0, tb_mlp);

        clk = 0;
        reset = 1;
        start = 0;

        #100;
        reset = 0;
        #20;

        $display("--- Starting Inference ---");
        start = 1;
        #10;
        start = 0;

        wait(done == 1);
        #50;

        $display("--------------------------");
        $display("Inference Complete.");
        $display("Predicted Class: %d", predicted_class);
        $display("--------------------------");
        
        $finish;
    end
endmodule