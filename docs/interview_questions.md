# ASIC Design & Verification Interview Questions & Answers (52 Q&A)

All answers below are tied directly to the **Adaptive Rate-Matching Engine** RTL and verification environment in this repository.

---

## Section 1: Digital Design Fundamentals (Q1–Q8)

**1. What is the difference between synchronous and asynchronous logic?**
Synchronous logic updates state on active edges of a single shared clock with deterministic setup/hold windows. Asynchronous logic lacks a common clock relationship; in this project, `src_clk` and `dst_clk` are independent asynchronous domains bridged strictly at `async_fifo` and `reset_controller`.

**2. Define setup time ($t_{su}$) and hold time ($t_h$) and how they relate to CDC.**
$t_{su}$ is the minimum window data must remain stable *before* the capturing clock edge; $t_h$ is the minimum window it must remain stable *after*. Across asynchronous clocks (`src_clk` vs `dst_clk`), setup/hold violations inevitably occur periodically, which is why `rd_ptr_gray_sync_pipe` and `wr_ptr_gray_sync_pipe` use `SYNC_STAGES >= 2` flip-flops.

**3. What is metastability, and why does simulation not prove metastability safety?**
Metastability occurs when a setup/hold violation leaves a flip-flop's internal regenerative node near its threshold voltage, taking unbounded time to resolve. RTL simulators (`iverilog`, `verilator`) evaluate 0/1 events deterministically and do not model analog transistor $\tau$; safety is achieved via structural 2-FF/N-FF synchronizers, `ASYNC_REG` placement, and STA MTBF analysis.

**4. Why is `src_ready` in `stream_adapter.sv` driven without combinational dependence on `src_valid`?**
To avoid combinational timing loops across module boundaries (AXI-Stream rule: `ready` may depend on internal state like `!fifo_wr_full && flow_enable`, while `valid` must never wait for `ready` combinationally, nor should `ready` form a loop with external `valid`).

**5. Explain the 2-entry egress skid buffer in `stream_adapter.sv`.**
`async_fifo` uses a synchronous registered read (`always_ff @(posedge rd_clk)`) so synthesis infers a dual-port SRAM (`$mem_v2`). Because registered read has 1-cycle latency, `stream_adapter` maintains a 2-slot `skid_mem[0:1]` + `rd_pipe_valid` tracker, sustaining 1 beat/cycle peak throughput while holding `dst_valid` and `dst_data` registered and constant during `dst_valid && !dst_ready`.

**6. Why did we register `flow_enable`, `congestion`, and `starvation_warning` in `rate_controller.sv`?**
Registering FSM outputs eliminates combinational glitches on `src_ready` and status pins and cleanly breaks the comparator timing path (`occupancy >= crit_high_wm`) from downstream external `src_ready` routing.

**7. Why does `packet_controller.sv` use `DROP_MALFORMED_BEATS` as a parameter?**
Different ASIC blocks require different fault policies: ingress debug/monitoring ports want malformed packets flagged (`packet_error`) and forwarded for trace capture (`DROP_MALFORMED_BEATS=0`), whereas strict datapaths drop malformed beats (`DROP_MALFORMED_BEATS=1`).

**8. How does Yosys avoid synthesizing 75,776 flip-flops for `FIFO_DEPTH=1024`?**
By using a synchronous read (`always_ff @(posedge rd_clk) if (rd_inc) rd_data <= mem[rd_addr];`) instead of combinational array indexing (`assign rd_data = mem[rd_addr]`), Yosys's `memory_collect` infers a single dual-port `$mem_v2` macro (`1024 x 74`).

---

## Section 2: Asynchronous FIFO Design (Q9–Q17)

**9. Why do we need an asynchronous FIFO instead of a simple register stage?**
An async FIFO decouples `src_clk` and `dst_clk` while absorbing microbursts and short-term rate mismatches at 1 beat/cycle peak throughput.

**10. Why are FIFO pointers Gray-coded before crossing clock domains?**
In `g = b ^ (b >> 1)`, adjacent counts differ by exactly 1 bit. Thus, asynchronous sampling during a pointer increment can only resolve to either the old pointer or the new pointer—never a corrupted intermediate value from multi-bit skew.

**11. Why does the pointer have `(ADDR_WIDTH + 1)` bits instead of `ADDR_WIDTH` bits?**
The extra MSB distinguishes "full" from "empty" when `wr_addr == rd_addr` (`ADDR_WIDTH` lower bits match).

**12. Explain Cummings full detection in `async_fifo.sv`.**
In Gray code, wrapping halfway around the $(N+1)$-bit space inverts **both** the MSB and the second-MSB while keeping the lower $N-1$ bits identical: `wr_ptr_gray_next == {~rd_ptr_gray_sync[N:N-1], rd_ptr_gray_sync[N-2:0]}`.

**13. Explain empty detection in `async_fifo.sv`.**
`rd_empty_next = (rd_ptr_gray_next == wr_ptr_gray_sync)`. Because `wr_ptr_gray_sync` lags the true write pointer, `rd_empty` may stay high for `SYNC_STAGES` extra `rd_clk` cycles (pessimistic empty), which is completely safe against underflow.

**14. Why are `wr_full` and `rd_empty` registered in `async_fifo.sv`?**
Registering `wr_full <= wr_full_next` and `rd_empty <= rd_empty_next` ensures glitch-free flags, clean static timing closure, and deterministic behavior right out of reset (`wr_full=0`, `rd_empty=1`).

**15. Can `async_fifo` lose or overwrite data if `wr_en` is asserted when `wr_full == 1`?**
No: `wr_inc = wr_en && !wr_full` blocks both `mem[wr_addr]` write and pointer increment, and asserts `wr_overflow <= 1'b1` for `fifo_monitor` to latch and count.

**16. What happens if `rd_en` is asserted when `rd_empty == 1`?**
`rd_inc = rd_en && !rd_empty` blocks `rd_ptr` advancement and `rd_data` overwrite, and asserts `rd_underflow <= 1'b1`.

**17. Why must `FIFO_DEPTH` be a power of 2 in this Gray-coded FIFO?**
Standard Gray code wraps cleanly across $2^{N+1}$ states with `~MSB, ~(MSB-1)` symmetry only when the depth is $2^N$. Non-power-of-2 depths break Gray symmetry on wrap-around unless offset-Gray or modular arithmetic is added.

---

## Section 3: CDC & Reset Architecture (Q18–Q26)

**18. Why is sampling a multi-bit binary occupancy counter across clock domains illegal?**
Multiple bits changing simultaneously (e.g. `511 -> 512`, 10 bits flipping) suffer skew and partial metastability across flops, producing wildly wrong occupancy spikes that could falsely trigger or suppress backpressure.

**19. How does `fifo_monitor` / `async_fifo` compute safe occupancy without a multi-bit CDC bus?**
Each side converts its *already synchronized* remote Gray pointer back to binary (`gray2bin`) and subtracts locally modulo $2^{N+1}$.

**20. Why is `wr_occupancy` conservative against overflow and `rd_occupancy` conservative against underflow?**
`rd_ptr_bin_sync` lags the true read pointer, so `wr_occupancy = wr_ptr_bin - rd_ptr_bin_sync >= true_occupancy` (throttles early, never late). Conversely, `wr_ptr_bin_sync` lags the true write pointer, so `rd_occupancy = wr_ptr_bin_sync - rd_ptr_bin <= true_occupancy`.

**21. How do packet boundaries (`packet_start`, `packet_end`) cross the CDC boundary safely?**
They are concatenated with `{keep, data}` into a single 74-bit FIFO word written into dual-port `mem`. Because the word is only read after `wr_ptr_gray` synchronizes to `rd_clk`, data and boundaries experience zero inter-signal skew.

**22. How does `clr_stats` cross from `wr_clk` to `rd_clk` in `fifo_monitor.sv`?**
Using a toggle-pulse synchronizer (`clr_toggle_wr` flipped on `clr_stats`, passed through `SYNC_STAGES` `rd_clk` flops `clr_sync_pipe`, and edge-detected via XOR `clr_sync_pipe[last] ^ clr_sync_prev`).

**23. Why does `reset_controller.sv` combine `src_rst_n & dst_rst_n`?**
Resetting only one side of an async FIFO leaves the other pointer non-zero, corrupting occupancy math and full/empty detection. Combining them guarantees symmetric FIFO reset whenever either domain resets.

**24. Explain async-assert, sync-deassert reset synchronization.**
Asserting `comb_rst_n = 0` immediately clears `src_rst_pipe` and `src_rst_sync_q` asynchronously (works even if a clock is gated). Deasserting `comb_rst_n = 1` shifts `1'b1` through `SYNC_STAGES` flops clocked by `src_clk`, releasing `src_rst_sync_n` cleanly synchronous to `src_clk` to prevent recovery/removal violations.

**25. Why did Verilator report `SYNCASYNCNET` initially, and how did we fix it cleanly?**
Using `src_rst_sync_n` both as a `negedge` async reset and as a synchronous data input to cross-domain observation triggered `SYNCASYNCNET`. Separating `src_rst_sync_q` (pure async-reset net) from `src_rst_done` (pure synchronous status flop) eliminated the structural conflict with zero waivers.

**26. What is the purpose of `reset_busy_src` and `reset_busy_dst`?**
If `src_clk` is faster than `dst_clk`, `src_rst_sync_n` releases first. `reset_busy_src` masks `src_ready = 0` until `dst_rst_done` is observed in `src_clk`, preventing writes before the read side is operational.

---

## Section 4: Verification & UVM (Q27–Q36)

**27. Explain the UVM testbench hierarchy in `tb/uvm/`.**
`rate_base_test` -> `rate_engine_env` -> `{source_agent (sqr, drv, mon), destination_agent (sqr, drv, mon), virtual_sequencer, rate_reference_model, rate_scoreboard, rate_coverage}`.

**28. What is the role of `virtual_sequencer`?**
It holds handles to `src_sqr` and `dst_sqr`, allowing `virtual_traffic_vseq` to coordinate ingress packet bursts concurrently with egress backpressure profiles.

**29. Why should the `rate_reference_model` NOT duplicate the DUT's Gray-pointer/skid RTL?**
Duplicating RTL mirrors RTL bugs. Instead, `rate_reference_model` operates purely at the transaction/packet level: verifying SOP/EOP protocol rules, tracking `packet_id`/`beat_idx`, and predicting exact egress beats independently of FIFO pointer internals.

**30. How does `rate_scoreboard` detect dropped, duplicated, or reordered beats?**
It pushes cloned expected beats into `exp_q[$]` on `write_exp`, pops the front on `write_act` and checks exact `{data, keep, packet_start, packet_end}` equality (catching corruption/reordering/duplication), and verifies `exp_q.size() == 0` in `check_phase` (catching dropped beats).

**31. What is the difference between `uvm_driver` and `uvm_monitor`?**
`source_driver` actively toggles pins (`valid`, `data`, `packet_start`, `packet_end`) via `drv_cb` obeying `valid && !ready` stability; `source_monitor` passively observes `mon_cb` and broadcasts accepted transactions (`valid && ready`) on an `uvm_analysis_port`.

**32. Why do we use `uvm_config_db` and `rate_env_config`?**
To pass virtual interfaces (`src_vif`, `dst_vif`) and runtime test knobs cleanly from `tb_uvm_top` down to agents without hardcoded hierarchical paths inside reusable UVM components.

**33. What is the difference between functional coverage and code coverage?**
Code coverage (line, branch, toggle, FSM) measures what RTL structures executed; functional coverage (`rate_coverage.sv` covergroups) measures whether intended *architectural scenarios* (e.g., `CONGESTION` during `CLK_EXTREME_MISMATCH` with `PKT_MAX`) actually occurred.

**34. Why did `rate_coverage.sv` exclude `empty × CTRL_CONGESTION`?**
Entering `CTRL_CONGESTION` requires `occupancy >= CRIT_HIGH_WATERMARK (928)`. `occupancy == 0` and `CTRL_CONGESTION` cannot coexist synchronously, making it a legitimate architectural `ignore_bins` exclusion.

**35. What happens in `tb_top.sv` / `rate_scoreboard.sv` when a reset occurs mid-packet?**
Expected in-flight beats flushed by reset are explicitly tallied in `sb_discarded` / `discarded_count` so end-of-test balance checks `beats_in == beats_out + reset_discarded` accurately without masking genuine drops.

**36. Why did we build both Tier 1 (`tests/tb_top.sv`) and Tier 2 (`tb/uvm/`)?**
So every RTL change can be compiled, linted, and regression-tested locally on open-source Icarus Verilog 13.0 and Verilator 5.050 (`30/30` runs passing), while also providing a full IEEE 1800.2 UVM 1.2 environment for enterprise Questa/VCS/Xcelium flows.

---

## Section 5: SystemVerilog Assertions (SVA) (Q37–Q42)

**37. Explain `|->` (overlapping) vs `|=>` (non-overlapping) implication.**
`A |-> B` evaluates consequent `B` starting in the *same* clock cycle that antecedent `A` matches (e.g. `reset_busy_src |-> !src_ready`). `A |=> B` starts evaluating `B` on the *next* clock cycle (e.g. `(src_valid && !src_ready) |=> $stable(src_data)`).

**38. How does `ast_src_hold_stable` in `tb/assertions/assertions.sv` verify AXI-Stream-like stability?**
Using `(src_valid && !src_ready) |=> (src_valid && $stable(src_data) && $stable(src_keep) && $stable(src_packet_start) && $stable(src_packet_end))` with `disable iff (!src_rst_sync_n)`.

**39. How does `$stable` work in SVA?**
`$stable(expr)` compares the sampled value of `expr` in the current clock tick against its sampled value in the previous clock tick and returns true if unchanged.

**40. Why is `disable iff (!src_rst_sync_n)` necessary on protocol assertions?**
Reset asynchronously clears `valid`, `ready`, and state registers; without `disable iff`, a reset asserting while `valid && !ready` would falsely fire a stability failure.

**41. How do assertions verify hysteresis in `rate_controller`?**
`ast_no_direct_congestion_to_normal` forbids `CTRL_CONGESTION |=> CTRL_NORMAL`, and `ast_congestion_hysteresis_hold` asserts that while `src_occupancy > HIGH_WATERMARK`, the FSM remains in `CTRL_CONGESTION`.

**42. Why use `bind top rate_engine_sva ...` instead of placing assertions inside synthesizable RTL?**
`bind` keeps `rtl/*.sv` 100% clean, tool-agnostic synthesizable RTL while still giving `assertions.sv` full visibility into internal signals (`fifo_wr_en`, `fifo_rd_en`, `src_rst_sync_n`).

---

## Section 6: Networking & Rate-Matching Architecture (Q43–Q52)

**43. Why is the phrase "adaptive rate-matching" NOT dynamically changing clock frequency?**
Changing physical PLL/clock frequencies inside a digital datapath introduces clock-glitch and timing-closure nightmares. Instead, the subsystem adapts *effective data throughput* via elastic buffering, occupancy feedback, and valid/ready flow control while remaining strictly synchronous to `src_clk` and `dst_clk`.

**44. How does the controller avoid threshold oscillation (chatter)?**
Through asymmetric entry/exit thresholds (hysteresis): `THROTTLE` enters at `768` and exits to `RECOVERY` below `640`; `RECOVERY` exits to `NORMAL` at `<= 512`; `CONGESTION` enters at `928` and steps down to `THROTTLE` at `<= 768`.

**45. What did Experiment D prove about hysteresis vs. fixed-threshold throttling?**
In real simulation (`135->75 MHz` with `6-on/10-off` backpressure), fixed single-threshold cutoff (`mode=1`) lost **10.9% throughput** (`2,245.75 Mbps`) compared to adaptive hysteresis (`2,519.87 Mbps`).

**46. What happens when the destination completely stops consuming data (`dst_ready == 0`)?**
`async_fifo` absorbs incoming beats; `rate_controller` steps `NORMAL -> THROTTLE -> CONGESTION`; once `wr_occupancy` reaches `FIFO_DEPTH (1024)`, `fifo_wr_full` asserts and `stream_adapter` holds `src_ready = 0` with zero dropped beats.

**47. What happens when the source clock is much faster than the destination clock (e.g. `150 vs 75 MHz`)?**
Occupancy rises until `rate_controller` paces `src_ready` (50% in `THROTTLE`, 25% in `CONGESTION`) and `fifo_wr_full` provides hard backpressure; sustained egress throughput matches the `dst_clk` ceiling (`~75 MHz × 64b`).

**48. What happens when the destination is faster than the source (`80 vs 100 MHz`)?**
FIFO occupancy stays near 0–5 beats, `rate_controller` enters `CTRL_STARVATION_WARNING` (`starvation_warning=1`) without throttling `src_ready`, and `rd_empty` safely stalls egress reads with zero underflows.

**49. Why does Experiment E show higher burst throughput at `FIFO_DEPTH=1024` vs `64`?**
Under a finite 1,500-beat burst with downstream backpressure, a 1,024-entry FIFO absorbs 932 beats internally before backpressuring the source, letting the ingress burst finish sooner (`3,148.70 Mbps` vs `1,991.65 Mbps`), trading off higher queueing latency (`11.88 us` vs `1.96 us`).

**50. How are single-beat packets represented on `stream_if`?**
`packet_start == 1` and `packet_end == 1` on the same accepted beat (`valid && ready`), verified in `basic_transfer_test` and `packet_controller.sv`.

**51. How would you support multi-channel QoS over this rate-matching engine?**
Instantiate per-class virtual channels (or separate ingress queues) sharing a Deficit Round-Robin (DRR) arbiter upstream of `async_fifo`—or separate per-QoS FIFOs to avoid Head-of-Line (HoL) blocking across traffic classes.

**52. What are the main limitations of this subsystem and future improvements?**
1. `FIFO_DEPTH` must be a power of 2 for standard Gray-code symmetry. 2. A shared single FIFO can suffer HoL blocking if multiple logical flows share it. 3. Adding an APB/AXI-Lite CSR slave for runtime watermark programming and cut-through vs. store-and-forward mode selection is a natural next step.
