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

    integer start_time;
    integer end_time;

    initial begin
        $dumpfile("mlp_simulation.vcd");
        $dumpvars(0, tb_mlp); [cite: 4]

        // 1. Initialize
        clk = 0;
        reset = 1;
        start = 0;
        #100;
        reset = 0;
        #20;

        // 2. Start & Capture Time
        $display("--- Starting Inference ---");
        start = 1; [cite: 5]
        start_time = $time; // <--- CAPTURE START TIME HERE
        #10;
        start = 0;

        // 3. Wait for Hardware
        wait(done == 1);
        end_time = $time;   // <--- CAPTURE END TIME HERE
        #50;

        // 4. Report Results
        $display("--------------------------");
        $display("Inference Complete.");
        $display("Predicted Class: %d", predicted_class);
        $display("Total Cycles:    %0d", (end_time - start_time) / 10); // Divide by Period (10ns)
        $display("Total Time:      %0d ns", end_time - start_time);
        $display("--------------------------");
        
        $finish; [cite: 6]
    end
    
  /*  initial begin
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
    end*/
endmodule