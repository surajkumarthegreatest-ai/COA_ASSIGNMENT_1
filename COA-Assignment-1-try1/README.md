# DMA-Based Data Transfer System for an AI Accelerator

Verilog implementation for the assignment:
**"Design a DMA-Based Data Transfer System for an AI Accelerator. Compare
CPU-controlled data transfer with DMA-based transfer for matrix
multiplication / CNN inference and calculate processor overhead and
throughput."**

This is an original, simplified implementation of the same concepts
described in Kalagi et al., *"FPGA validated RISC-V system on chip with a
custom systolic array accelerator for edge AI inference,"* Discover
Artificial Intelligence, 2026 (the paper you shared). It does **not** copy
that paper's RTL (which was never published, only described in prose/
diagrams) — every module here is written from scratch at a scope
appropriate for a course assignment.

## Files

| File | What it is |
|---|---|
| `mac_pe.v` | One Multiply-Accumulate processing element (the "worker" inside the accelerator) |
| `systolic_array.v` | 4×4 output-stationary systolic array (the AI accelerator itself) |
| `tile_feeder.v` | Streams a loaded tile into the array in the correct skewed order |
| `shared_mem.v` | Simple synchronous RAM, standing in for a BRAM region |
| `dma_engine.v` | **The DMA "assistant"** — moves a block of words autonomously once given a descriptor |
| `cpu_transfer_fsm.v` | **Baseline / Scenario A** — CPU moves every word itself (load+store per word) |
| `ctrl_regs.v` | Simplified memory-mapped control registers (stand-in for AXI4-Lite) |
| `tb_compare.v` | Testbench: runs both scenarios, prints overhead % and throughput (GOPS) |

## Bug fix log (v2)

The first version had two bugs, found by actually running it:

1. **Wrong matrix values.** `tile_feeder.v` and `systolic_array.v` were
   both started from the same pulse, but the accelerator needs one cycle
   to clear its accumulators before it's ready for real data. The feeder's
   first column was landing on that clear cycle and getting thrown away,
   shifting every subsequent value by one step. **Fix:** the feeder is now
   started from the accelerator's own `clear_pulse` output (exposed as a
   new port on `systolic_array.v`), which lands exactly one cycle later —
   precisely when the array is ready. `tile_feeder.v` also had a smaller
   bug where its very first column got emitted twice before advancing;
   that's fixed too.
2. **Compute cycle count read as 13 instead of 11.** The testbench was
   reading `done`/`busy` signals in the same simulation instant as the
   `@(posedge clk)` that updates them — a classic Verilog race that can
   read the pre-edge value instead of the post-edge one, silently adding
   an extra loop iteration. **Fix:** a `#1` delay after every such edge
   in `tb_compare.v` before checking the signal.

With both fixes, the sample tile (A(i,k) = row-major 1..16, B(k,j) = 1)
should now print `C(i,j) = 10, 26, 42, 58` per row, and the compute phase
should measure exactly `3N − 1 = 11` cycles for N = 4.

## How to run

This environment has no internet access, so I could not install a
simulator to test-compile it here. Please run it yourself with whatever
your course uses, e.g.:

```
# Icarus Verilog
iverilog -o sim.out mac_pe.v systolic_array.v tile_feeder.v shared_mem.v \
         dma_engine.v cpu_transfer_fsm.v ctrl_regs.v tb_compare.v
vvp sim.out
```

or open all the files as sources in Vivado, set `tb_compare` as the
simulation top module, and run behavioural simulation (this is the same
tool the reference paper used). If Vivado/Icarus flags a small syntax
issue, it's most likely a minor port-width or bit-slice nit — fix it
locally and re-run; the architecture and formulas below don't change.

## What the testbench measures

It moves a 32-word tile (a 4×4 matrix A + a 4×4 matrix B) two ways:

- **Scenario A (no DMA):** `cpu_transfer_fsm` copies every word itself —
  one LOAD cycle + one STORE cycle per word. `cpu_busy` stays HIGH for the
  entire transfer.
- **Scenario B (with DMA):** the CPU only writes a few descriptor
  registers and pulses START (`ctrl_regs.v` / modelled as ~4 cycles);
  `dma_engine.v` then bursts all 32 words in the background while the CPU
  is free.

It also runs `systolic_array.v` once (via `tile_feeder.v`) on a small
sample tile to confirm the accelerator itself finishes a 4×4 tile in
`3N − 1 = 11` cycles, matching the closed-form result from the paper.

At the end it prints, for each scenario:

- **Processor overhead** = (cycles the CPU is stuck moving data) ÷ (total
  end-to-end cycles) × 100%
- **Throughput** = (useful operations, `2·N³` for one N×N multiply) ÷
  (total time), reported in GOPS assuming a 100 MHz clock — the same
  definitions and clock rate used in the reference paper's Eqs. 7–9.

## For your report / slides

You can quote the printed numbers directly, and also cite the closed-form
formulas they're built on:

- CPU-controlled transfer cycles ≈ `2·N²` (one load + one store per
  matrix element)
- DMA descriptor cost ≈ a small constant, independent of `N`
- Compute latency = `3N − 1` cycles (proved formally in the paper's
  Proposition 1)
- Throughput = `2·N³ / T` operations per second, where `T` is whichever
  end-to-end time you're evaluating (CPU-controlled vs DMA-based)

The relative gap between the two scenarios grows with `N`, since the
CPU-controlled cost scales as `N²` per transfer while the DMA's CPU-side
cost stays constant — this is the core point your slides should make.