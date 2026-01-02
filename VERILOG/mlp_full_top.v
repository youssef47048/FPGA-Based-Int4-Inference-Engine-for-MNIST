`timescale 1ns / 1ps

module mlp_top (
    input clk,
    input reset,
    input start,
    output reg done,
    output reg [3:0] predicted_class
);

    // 1. CONFIGURATION
    parameter L1_IN = 784, L1_NEURONS = 64;
    parameter L2_IN = 64,  L2_NEURONS = 32;
    parameter L3_IN = 32,  L3_NEURONS = 10;

    // ADDED: INC states to prevent address race conditions
    localparam IDLE = 0, 
               LAYER_1 = 1, L1_WRITE = 2, L1_INC = 3,
               LAYER_2 = 4, L2_WRITE = 5, L2_INC = 6,
               LAYER_3 = 7, FINISH = 8;
               
    reg [3:0] state; // Increased width for more states

    // 2. INTERNAL SIGNALS
    reg [9:0] input_cnt;   
    reg [6:0] neuron_cnt; 
    
    reg [15:0] addr_w1, addr_w2, addr_w3; 
    
    // PIPELINE SIGNALS
    reg pipeline_valid;      
    reg pipeline_valid_d;    
    
    reg signed [19:0] accumulator; 
    reg signed [19:0] temp_quant;
    reg [3:0] quantized_result;
    reg signed [19:0] max_logit;
    
    // 3. MEMORY INSTANTIATIONS
    wire signed [3:0] r_w1, r_w2, r_w3;
    wire [3:0] r_data_in, r_data_l1, r_data_l2;
    reg [3:0] w_data_val;
    reg wen_l1, wen_l2; 
    
    // ROM INSTANTIATIONS 
    rom_memory #("w1.mem", L1_IN*L1_NEURONS, 4) rom1 (.clk(clk), .addr(addr_w1), .data_out(r_w1));
    rom_memory #("w2.mem", L2_IN*L2_NEURONS, 4) rom2 (.clk(clk), .addr(addr_w2), .data_out(r_w2));
    rom_memory #("w3.mem", L3_IN*L3_NEURONS, 4) rom3 (.clk(clk), .addr(addr_w3), .data_out(r_w3));

    ram_memory #("input1.mem", L1_IN, 4) ram_in (.clk(clk), .wen(1'b0), .addr(input_cnt < L1_IN ? input_cnt[9:0] : 10'd0), .data_in(4'd0), .data_out(r_data_in));
    
    // RAM L1 (With Address Slicing Fix)
    ram_memory #("", L1_NEURONS, 4) ram_l1 (
        .clk(clk), .wen(wen_l1), 
        .addr(wen_l1 ? neuron_cnt[5:0] : input_cnt[5:0]), 
        .data_in(w_data_val), .data_out(r_data_l1)
    );
    
    // RAM L2 (With Address Slicing Fix)
    ram_memory #("", L2_NEURONS, 4) ram_l2 (
        .clk(clk), .wen(wen_l2), 
        .addr(wen_l2 ? neuron_cnt[4:0] : input_cnt[4:0]), 
        .data_in(w_data_val), .data_out(r_data_l2)
    );

    // 4. DATA MUX
    reg signed [3:0] current_weight;
    reg [3:0] current_input;

    always @(*) begin
        case (state)
            LAYER_1: begin
                current_weight = r_w1;
                current_input  = r_data_in;
            end
            LAYER_2: begin
                current_weight = r_w2;
                current_input  = r_data_l1;
            end
            LAYER_3: begin
                current_weight = r_w3;
                current_input  = r_data_l2;
            end
            default: begin
                current_weight = 0;
                current_input  = 0;
            end
        endcase
    end

    // 5. MATH CORE
    wire signed [19:0] product;
    assign product = (current_input === 4'bx || current_weight === 4'bx) ? 0 : $signed({1'b0, current_input}) * $signed(current_weight);

    always @(*) begin
        // Standard Scale: Divide by 64
        temp_quant = accumulator >>> 6; //arithmetic shift right
        if (temp_quant < 0) quantized_result = 0;       
        else if (temp_quant > 15) quantized_result = 15; 
        else quantized_result = temp_quant[3:0];
    end

    // 6. STATE MACHINE
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            input_cnt <= 0;
            neuron_cnt <= 0;
            addr_w1 <= 0; addr_w2 <= 0; addr_w3 <= 0;
            accumulator <= 0;
            pipeline_valid <= 0;
            pipeline_valid_d <= 0; 
            wen_l1 <= 0; wen_l2 <= 0;
            predicted_class <= 0;
            max_logit <= -20'd262144;
        end else begin
            wen_l1 <= 0; 
            wen_l2 <= 0;
            
            pipeline_valid_d <= pipeline_valid;

            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= LAYER_1;
                        input_cnt <= 0;
                        neuron_cnt <= 0;
                        accumulator <= 0;
                        pipeline_valid <= 0;
                        pipeline_valid_d <= 0;
                        // Reset control signal to avoid latching bad state
                        wen_l1 <= 0;
                    end
                end

                // --- LAYER 1 ---
                LAYER_1: begin
                    if (input_cnt < L1_IN) begin
                        input_cnt <= input_cnt + 1;
                        pipeline_valid <= 1; 
                        addr_w1 <= addr_w1 + 1; 
                    end else begin
                        pipeline_valid <= 0;
                        // Keep input_cnt valid to avoid out-of-bounds read
                        input_cnt <= L1_IN; 
                    end

                    if (pipeline_valid_d) accumulator <= accumulator + product;

                    if (input_cnt == L1_IN && pipeline_valid == 0 && pipeline_valid_d == 0) begin
                        state <= L1_WRITE;
                    end
                end

                L1_WRITE: begin
                    // Step 1: Write result to CURRENT neuron_cnt
                    wen_l1 <= 1; 
                    w_data_val <= quantized_result;
                    state <= L1_INC; // Move to Increment State
                end

                L1_INC: begin
                    // Step 2: Increment neuron count and reset for next loop
                    accumulator <= 0;
                    input_cnt <= 0;
                    
                    if (neuron_cnt < L1_NEURONS - 1) begin
                        neuron_cnt <= neuron_cnt + 1;
                        state <= LAYER_1;
                    end else begin
                        neuron_cnt <= 0;
                        state <= LAYER_2; 
                    end
                end

                // --- LAYER 2 ---
                LAYER_2: begin
                    if (input_cnt < L2_IN) begin
                        input_cnt <= input_cnt + 1;
                        pipeline_valid <= 1;
                        addr_w2 <= addr_w2 + 1;
                    end else begin
                        pipeline_valid <= 0;
                    end

                    if (pipeline_valid_d) accumulator <= accumulator + product;

                    if (input_cnt == L2_IN && pipeline_valid == 0 && pipeline_valid_d == 0) begin
                        state <= L2_WRITE;
                    end
                end

                L2_WRITE: begin
                    wen_l2 <= 1; 
                    w_data_val <= quantized_result;
                    state <= L2_INC;
                end

                L2_INC: begin
                    accumulator <= 0;
                    input_cnt <= 0;
                    
                    if (neuron_cnt < L2_NEURONS - 1) begin
                        neuron_cnt <= neuron_cnt + 1;
                        state <= LAYER_2;
                    end else begin
                        neuron_cnt <= 0;
                        max_logit <= -20'd262144; 
                        state <= LAYER_3;
                    end
                end

                // --- LAYER 3 ---
                LAYER_3: begin
                    if (input_cnt < L3_IN) begin
                        input_cnt <= input_cnt + 1;
                        pipeline_valid <= 1;
                        addr_w3 <= addr_w3 + 1;
                    end else begin
                        pipeline_valid <= 0;
                    end

                    if (pipeline_valid_d) accumulator <= accumulator + product;

                    if (input_cnt == L3_IN && pipeline_valid == 0 && pipeline_valid_d == 0) begin
                        // Argmax
                        if (accumulator > max_logit) begin
                            max_logit <= accumulator;
                            predicted_class <= neuron_cnt[3:0];
                        end
                        accumulator <= 0;
                        input_cnt <= 0;
                        
                        if (neuron_cnt < L3_NEURONS - 1) begin
                            neuron_cnt <= neuron_cnt + 1;
                        end else begin
                            state <= FINISH;
                        end
                    end
                end

                FINISH: begin
                    done <= 1;
                end
            endcase
        end
    end

    // ========================================================================
    // DEBUG: Trace Execution
    // ========================================================================
    always @(posedge clk) begin
        // 1. Trace accumulation for the first neuron (Neuron 0) in Layer 1
        // We only print if product is non-zero to avoid spamming 700+ lines of zeros
        if (state == LAYER_1 && neuron_cnt == 0 && pipeline_valid_d) begin
            if (product != 0) begin
                $display("DEBUG: L1_N0 | Idx: %3d | In: %2d | W: %2d | Prod: %4d | Acc: %d", 
                         input_cnt-1, current_input, current_weight, product, accumulator);
            end
            if (^product === 1'bx || ^accumulator === 1'bx) begin
                 $display("ERROR: X Detected! Idx: %d | In: %h | W: %h | Prod: %h | Acc: %h", 
                         input_cnt-1, current_input, current_weight, product, accumulator);
            end
        end

        // 2. Trace Final Output of First 5 Neurons in Layer 1
        if (state == L1_WRITE && neuron_cnt < 5) begin
            $display("DEBUG: L1 Neuron %2d | Final Acc: %d | Scaled: %d | Output: %d", 
                     neuron_cnt, accumulator, temp_quant, quantized_result);
        end

        // 2b. Trace Final Output of First 5 Neurons in Layer 2
        if (state == L2_WRITE && neuron_cnt < 5) begin
             $display("DEBUG: L2 Neuron %2d | Final Acc: %d | Scaled: %d | Output: %d", 
                      neuron_cnt, accumulator, temp_quant, quantized_result);
        end

        // 3. Trace Final Prediction Logits (Layer 3)
        if (state == LAYER_3 && input_cnt == L3_IN && pipeline_valid == 0 && pipeline_valid_d == 0) begin
             $display("DEBUG: L3 Neuron %2d | Logit: %d | Current Max: %d", 
                      neuron_cnt, accumulator, max_logit);
        end
    end

    // DEBUG PRINTS (Now checking center pixel to ensure input1.mem is valid)
    initial begin
        #50;
        $display("-----------------------------------------");
        $display("DEBUG: Checking Memory Contents...");
        $display("DEBUG: Weight[46] = %h", rom1.memory[46]);
        // Check pixel 658 (known non-zero) instead of 406
        $display("DEBUG: Pixel[658] = %h", ram_in.memory[658]); 
        
        if (ram_in.memory[658] == 0) begin
             $display("WARNING: Pixel 658 is 0. 'input1.mem' might be empty or blank!");
        end else begin
             $display("SUCCESS: Input image data detected.");
        end
        $display("-----------------------------------------");
    end

endmodule