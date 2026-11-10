# Clock-Domain Crossing (CDC) Strategy

## 1. Explicit CDC Boundary Inventory

Every asynchronous boundary in the design is explicitly enumerated below:

| # | Signal / Path | Source Domain | Dest Domain | CDC Mechanism | Justification |
|---|---|---|---|---|---|
| 1 | `wr_ptr_gray[N:0]` | `src_clk` | `dst_clk` | 2-FF (configurable `SYNC_STAGES`) synchronizer in `async_fifo` | Single-bit Gray code transitions prevent multi-bit skew corruption |
| 2 | `rd_ptr_gray[N:0]` | `dst_clk` | `src_clk` | 2-FF (configurable `SYNC_STAGES`) synchronizer in `async_fifo` | Single-bit Gray code transitions prevent multi-bit skew corruption |
| 3 | `{sop, eop, keep, data}` | `src_clk` | `dst_clk` | Dual-port FIFO RAM written on `src_clk`, read on `dst_clk` only after `wr_ptr_gray` synchronizes | Data word is quiescent before `rd_empty` deasserts |
| 4 | `clr_toggle_wr` | `src_clk` | `dst_clk` | Toggle-pulse synchronizer in `fifo_monitor` | Transfers single-bit clear event safely across domains |
| 5 | `src_rst_done` / `dst_rst_done` | Cross-domain | Cross-domain | 2-FF level synchronizer in `reset_controller` | Prevents traffic while opposite domain is still in reset |
| 6 | `comb_rst_n` -> `*_rst_sync_n` | Async | `src_clk` / `dst_clk` | Async-assert, sync-deassert reset synchronizer | Eliminates reset recovery/removal metastability |

## 2. Why Gray Coding & Synchronizers Are Required

1. **Multi-bit binary skew hazard:** Incrementing a binary pointer (e.g., `0111 -> 1000`) flips multiple bits simultaneously. Because wire delays and sampling skew differ per bit, an unsynchronized destination clock edge can latch a hybrid bogus value (e.g., `1111` or `0000`), corrupting `full`/`empty` detection.
2. **Gray-code invariant:** `g = b ^ (b >> 1)` guarantees Hamming distance = 1 between every pair of consecutive pointer values. Even if a bit transition violates setup/hold at the first synchronizer flop, the synchronizer resolves to *either* the previous pointer *or* the new pointer—never an out-of-order value.
3. **Why simulation cannot prove metastability safety:** Standard RTL simulators (`iverilog`, `verilator`, `questa`) resolve 0/1 transitions deterministically and do not model transistor-level metastable decay time constants ($\tau$). Metastability MTBF must be verified by physical cell characterization, `ASYNC_REG`/don't-touch placement constraints, and static CDC/timing signoff.

## 3. Conservative Occupancy Calculation (`fifo_monitor` + `async_fifo`)

We **never** transfer a multi-bit binary occupancy counter across clock domains. Instead, each domain converts its locally synchronized Gray pointer back to binary (`gray2bin`) and subtracts modulo $2^{N+1}$:

- **Source/write domain:** `wr_occupancy = wr_ptr_bin - rd_ptr_bin_sync`
  - Because `rd_ptr_bin_sync` lags the true read pointer by `SYNC_STAGES` `src_clk` cycles, `wr_occupancy >= true_occupancy`.
  - **Safety property:** The rate controller may throttle slightly early, never late—preventing overflow.
- **Destination/read domain:** `rd_occupancy = wr_ptr_bin_sync - rd_ptr_bin`
  - Because `wr_ptr_bin_sync` lags the true write pointer, `rd_occupancy <= true_occupancy`.
  - **Safety property:** Read logic never assumes data is present before it has safely landed in memory.
