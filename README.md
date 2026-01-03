# MNIST AI Hardware Implementation

This project implements a Multi-Layer Perceptron (MLP) neural network in Verilog for MNIST digit recognition. It includes a complete flow from training a PyTorch model to hardware simulation.

## Project Overview

The system is designed to perform inference on handwritten digits (MNIST dataset) using a custom hardware accelerator.

- **Architecture:** 3-Layer MLP (Fully Connected)
  - Input Layer: 784 nodes (28x28 pixel image)
  - Hidden Layer 1: 64 neurons
  - Hidden Layer 2: 32 neurons
  - Output Layer: 10 neurons (Digits 0-9)
- **Features:**
  - 4-bit quantized weights and activations (HW friendly).
  - No bias terms used in layers (simplified MAC units).
  - ReLU activation functions.
  - Pipelined Multiply-Accumulate (MAC) operations.
##  Quantization Details

To deploy the model on FPGA with minimal resource usage, we converted the 32-bit floating-point model to **4-bit Integers (Int4)**. This compression reduces memory usage by **8x** and allows the arithmetic logic to fit entirely within on-chip Block RAM.

### Methodology: Post-Training Static Symmetric Quantization

We utilize a symmetric quantization scheme that maps the floating-point range to a fixed integer range centered around zero (for weights) or starting at zero (for activations).

* **Weights:** Quantized to **Signed 4-bit Integers**.
    * Range: `[-8, +7]`
    * Scaling: Per-layer symmetric scaling based on the absolute maximum weight value.
    * *Note: Floating-point 0.0 is exactly mapped to Integer 0 to simplify hardware multiplication.*

* **Activations:** Quantized to **Unsigned 4-bit Integers**.
    * Range: `[0, 15]`
    * Logic: Since all layers use **ReLU** (Rectified Linear Unit), negative values are zeroed out, effectively allowing us to use the full 4-bit unsigned range for positive values.

### Hardware Arithmetic Handling
The hardware performs mixed-sign arithmetic to maintain accuracy:
1.  **Input Padding:** Unsigned 4-bit inputs (`0..15`) are zero-padded to be treated as positive signed numbers.
2.  **Accumulation:** Intermediate sums are stored in a **20-bit Signed Accumulator** to prevent overflow during the summation of 784 products.
3.  **Scale Management:** The quantization scale factors are baked into the weights during the export process, meaning the hardware does not need to perform complex floating-point division at runtime.
## Directory Structure

```
.
├── MNIST_AI_HARDWARE.ipynb   # Jupyter Notebook for training and generating .mem files
├── VERILOG/                  # Verilog source code and simulation files
│   ├── mlp_full_top.v        # Top-level hardware implementation
│   ├── memory.v              # RAM/ROM memory modules
│   ├── tp_mltp.v             # Testbench for simulation
│   ├── input1.mem            # Example input image (generated)
│   ├── w1.mem                # Layer 1 weights (generated)
│   ├── w2.mem                # Layer 2 weights (generated)
│   ├── w3.mem                # Layer 3 weights (generated)
│   └── ...                   # Simulation artifacts (ModelSim/Questa)
└── README.md                 # This file
```

## Hardware Design (`mlp_full_top.v`)

The hardware logic implements a state machine to process the neural network layers sequentially:
1. **Layer 1:** Reads inputs from `input1.mem` and weights from `w1.mem`. Performs MAC operations and writes results to internal RAM.
2. **Layer 2:** Reads results from Layer 1 and weights from `w2.mem`. Writes results to internal RAM.
3. **Layer 3:** Reads results from Layer 2 and weights from `w3.mem`. Computes the final logits.
4. **Argmax:** Identifies the neuron with the highest value to determine the predicted class.

## Getting Started

### Prerequisites

- **Software:**
  - Python 3.x (with PyTorch, torchvision, numpy)
  - Verilog Simulator (ModelSim, QuestaSim, Vivado, or Icarus Verilog)

### 1. Train the Model

Open `MNIST_AI_HARDWARE.ipynb` and run all cells. This will:
1. Download the MNIST dataset.
2. Train a simplified MLP model (bias=False).
3. Quantize the weights and inputs.
4. Export the following files to the `VERILOG/` directory:
   - `input1.mem` (Test image pixel data)
   - `w1.mem`, `w2.mem`, `w3.mem` (Quantized weights)

### 2. Run Simulation

1. Open your Verilog simulator.
2. Compile the source files:
   - `VERILOG/memory.v`
   - `VERILOG/mlp_full_top.v`
   - `VERILOG/tp_mltp.v`
3. Run the simulation using `tp_mltp` as the top-level module.
4. Check the console output for the prediction result:
   ```
   --- Starting Inference ---
   ...
   Inference Complete.
   Predicted Class: X
   ```
   *(Where X is the predicted digit)*

## Simulation Output

The testbench generates a VCD file (`mlp_simulation.vcd`) which can be viewed in waveform viewers like GTKWave or ModelSim to analyze signal transitions and timing.

## Notes

- Ensure the generated `.mem` files are in the same directory where the simulation runs, or update the paths in `mlp_full_top.v` if necessary.
- The hardware uses integer arithmetic (scaled) to approximate floating-point operations performed during training.

