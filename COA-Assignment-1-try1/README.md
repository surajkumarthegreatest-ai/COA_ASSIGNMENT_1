# DMA-Based Data Transfer System for an AI Accelerator

## Overview

This project contains a Verilog implementation designed to evaluate and compare CPU-controlled data transfers versus Direct Memory Access (DMA) based transfers for AI workloads (specifically, matrix multiplication and CNN inference). 

The architecture provides an original, ground-up implementation of the core concepts detailed in Kalagi et al., *"FPGA validated RISC-V system on chip with a custom systolic array accelerator for edge AI inference,"* Discover Artificial Intelligence, 2026.

## Repository Structure

| File | Description |
|---|---|
| `mac_pe.v` | One Multiply-Accumulate processing element (the primary compute node inside the accelerator). |
| `systolic_array.v` | A 4×4 output-stationary systolic array (the AI accelerator core). |
| `tile_feeder.v` | Streams a loaded memory tile into the systolic array in the required skewed timing order. |
| `shared_mem.v` | Simple synchronous RAM, functioning as a block RAM (BRAM) region. |
| `dma_engine.v` | **DMA Controller** — Autonomously moves blocks of data upon receiving a descriptor. |
| `cpu_transfer_fsm.v` | **Baseline (Scenario A)** — Simulates a CPU moving data word-by-word (load + store per word). |
| `ctrl_regs.v` | Simplified memory-mapped control registers (functioning similarly to an AXI4-Lite interface). |
| `tb_compare.v` | Testbench: Executes both transfer scenarios and calculates processor overhead percentage and throughput in GOPS. |

## Simulation and Execution

This project can be simulated using standard RTL simulation tools such as Icarus Verilog or Xilinx Vivado.

### Using Icarus Verilog
```bash
# Compile the design and testbench
iverilog -o sim.out mac_pe.v systolic_array.v tile_feeder.v shared_mem.v \
         dma_engine.v cpu_transfer_fsm.v ctrl_regs.v tb_compare.v

# Run the simulation
vvp sim.out
