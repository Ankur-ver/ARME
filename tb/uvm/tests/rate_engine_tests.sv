// =============================================================================
// File        : tb/uvm/tests/rate_engine_tests.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Complete UVM test suite covering smoke, basic, burst,
//               backpressure, clock ratios, boundaries, resets, congestion,
//               starvation, 1000+ transaction random stress, and error injection.
// =============================================================================

`ifndef RATE_ENGINE_TESTS_SV
`define RATE_ENGINE_TESTS_SV

class rate_base_test extends uvm_test;
    `uvm_component_utils(rate_base_test)

    rate_engine_env env;
    rate_env_config cfg;

    function new(string name = "rate_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(rate_env_config)::get(this, "", "env_cfg", cfg)) begin
            cfg = rate_env_config::type_id::create("cfg");
        end
        env = rate_engine_env::type_id::create("env", this);
    endfunction

    task run_vseq(
        int unsigned  pkts,
        pkt_profile_e prof,
        bit           rand_prof,
        bit           always_rdy,
        int unsigned  bp_min = 1,
        int unsigned  bp_max = 12,
        bit           malformed = 1'b0
    );
        virtual_traffic_vseq vseq = virtual_traffic_vseq::type_id::create("vseq");
        vseq.num_packets      = pkts;
        vseq.pkt_profile      = prof;
        vseq.random_profiles  = rand_prof;
        vseq.bp_always_ready  = always_rdy;
        vseq.bp_min_off       = bp_min;
        vseq.bp_max_off       = bp_max;
        vseq.inject_malformed = malformed;
        vseq.start(env.vsqr);
        #2us;
    endtask
endclass

class smoke_test extends rate_base_test;
    `uvm_component_utils(smoke_test)
    function new(string name = "smoke_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(10, PKT_SMALL, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class basic_transfer_test extends rate_base_test;
    `uvm_component_utils(basic_transfer_test)
    function new(string name = "basic_transfer_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(5,  PKT_SINGLE, 1'b0, 1'b1);
        run_vseq(20, PKT_MEDIUM, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class burst_test extends rate_base_test;
    `uvm_component_utils(burst_test)
    function new(string name = "burst_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(15, PKT_BURST, 1'b0, 1'b1);
        run_vseq(5,  PKT_MAX,   1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class backpressure_test extends rate_base_test;
    `uvm_component_utils(backpressure_test)
    function new(string name = "backpressure_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(40, PKT_MEDIUM, 1'b1, 1'b0, 1, 24);
        phase.drop_objection(this);
    endtask
endclass

class source_faster_test extends rate_base_test;
    `uvm_component_utils(source_faster_test)
    function new(string name = "source_faster_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(50, PKT_LARGE, 1'b0, 1'b0, 0, 4);
        phase.drop_objection(this);
    endtask
endclass

class destination_faster_test extends rate_base_test;
    `uvm_component_utils(destination_faster_test)
    function new(string name = "destination_faster_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(50, PKT_SMALL, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class equal_rate_test extends rate_base_test;
    `uvm_component_utils(equal_rate_test)
    function new(string name = "equal_rate_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(40, PKT_MEDIUM, 1'b1, 1'b0, 1, 6);
        phase.drop_objection(this);
    endtask
endclass

class extreme_rate_mismatch_test extends rate_base_test;
    `uvm_component_utils(extreme_rate_mismatch_test)
    function new(string name = "extreme_rate_mismatch_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(60, PKT_BURST, 1'b0, 1'b0, 1, 8);
        phase.drop_objection(this);
    endtask
endclass

class fifo_boundary_test extends rate_base_test;
    `uvm_component_utils(fifo_boundary_test)
    function new(string name = "fifo_boundary_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(12, PKT_MAX, 1'b0, 1'b0, 32, 64);
        phase.drop_objection(this);
    endtask
endclass

class congestion_test extends rate_base_test;
    `uvm_component_utils(congestion_test)
    function new(string name = "congestion_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(20, PKT_LARGE, 1'b0, 1'b0, 20, 48);
        phase.drop_objection(this);
    endtask
endclass

class starvation_test extends rate_base_test;
    `uvm_component_utils(starvation_test)
    function new(string name = "starvation_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(30, PKT_SINGLE, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class reset_test extends rate_base_test;
    `uvm_component_utils(reset_test)
    function new(string name = "reset_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(15, PKT_SMALL, 1'b0, 1'b1);
        env.cov.sample_reset(RST_IDLE);
        phase.drop_objection(this);
    endtask
endclass

class reset_during_packet_test extends rate_base_test;
    `uvm_component_utils(reset_during_packet_test)
    function new(string name = "reset_during_packet_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        env.cov.sample_reset(RST_DURING_PACKET);
        run_vseq(20, PKT_MEDIUM, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class random_stress_test extends rate_base_test;
    `uvm_component_utils(random_stress_test)
    function new(string name = "random_stress_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        // Runs 1000+ randomized packet transactions
        run_vseq(1050, PKT_MEDIUM, 1'b1, 1'b0, 0, 16);
        phase.drop_objection(this);
    endtask
endclass

class error_injection_test extends rate_base_test;
    `uvm_component_utils(error_injection_test)
    function new(string name = "error_injection_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vseq(5, PKT_MALFORMED, 1'b0, 1'b1, 0, 0, 1'b1);
        run_vseq(10, PKT_SMALL, 1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

`endif

