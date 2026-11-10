# Reset Architecture & Strategy

## 1. The Dual-Clock FIFO Reset Hazard

In a dual-clock asynchronous FIFO, resetting only one side while the other side continues operating corrupts pointer comparison: resetting `wr_ptr` to 0 while `rd_ptr` remains non-zero causes `wr_occupancy = 0 - rd_ptr` (wrapping modulo $2^{N+1}$) to look falsely large or `full`, and allows stale words to be read.

## 2. Implemented Reset Solution (`rtl/reset_controller.sv`)

1. **Coordinated Asynchronous Assertion:**
   - `comb_rst_n = src_rst_n & dst_rst_n`.
   - Asserting either domain's external active-low reset immediately forces both domains into reset asynchronously (`negedge comb_rst_n`), clearing FIFO pointers, synchronizer pipes, FSM state, and valid/ready outputs.
2. **Independent Synchronous Deassertion:**
   - Each domain releases its internal reset tree (`src_rst_sync_n`, `dst_rst_sync_n`) through a `SYNC_STAGES`-deep flip-flop chain clocked by its own clock (`src_clk` / `dst_clk`), eliminating recovery/removal metastability on reset release.
3. **Cross-Domain Release Handshaking (`reset_busy_src`, `reset_busy_dst`):**
   - Separate `src_rst_done` and `dst_rst_done` flags are cross-synchronized into the opposite domain.
   - Until both domains have exited reset and observed the peer's release, `reset_busy_src` holds `src_ready = 0` and `reset_busy_dst` holds `dst_valid = 0`.
   - This prevents a fast source clock from pushing beats into the FIFO while a slower destination clock is still held in reset.

## 3. Mid-Packet Reset Behavior

- In `packet_controller.sv`, `in_packet` resets synchronously/asynchronously back to `1'b0` on reset, clearing partial-packet state.
- Any partial packet beats still inside `async_fifo` when reset asserts are flushed by resetting `wr_ptr_bin`, `rd_ptr_bin`, and egress `skid_count` to 0.
- Dedicated reset tests (`reset_test`, `reset_during_packet_test`) verify both independent `src_rst_n`/`dst_rst_n` assertions and mid-packet reset recovery without post-reset corruption.

