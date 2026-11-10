// =============================================================================
// File        : tb/uvm/agents/destination_agent.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : UVM destination agent (backpressure driver & egress monitor).
// =============================================================================

`ifndef DESTINATION_AGENT_SV
`define DESTINATION_AGENT_SV

class destination_sequencer extends uvm_sequencer #(backpressure_transaction);
    `uvm_component_utils(destination_sequencer)
    function new(string name = "destination_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

class destination_driver extends uvm_driver #(backpressure_transaction);
    `uvm_component_utils(destination_driver)

    virtual stream_if #(64) vif;

    function new(string name = "destination_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual stream_if #(64))::get(this, "", "dst_vif", vif)) begin
            `uvm_fatal("NO_VIF", "destination_driver failed to retrieve dst_vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        backpressure_transaction req;
        vif.sink_cb.ready <= 1'b1;
        wait (vif.rst_n === 1'b1);

        forever begin
            seq_item_port.get_next_item(req);
            vif.sink_cb.ready <= 1'b1;
            repeat (req.ready_on_cycles) @(vif.sink_cb);
            if (req.ready_off_cycles > 0) begin
                vif.sink_cb.ready <= 1'b0;
                repeat (req.ready_off_cycles) @(vif.sink_cb);
            end
            seq_item_port.item_done();
        end
    endtask
endclass

class destination_monitor extends uvm_monitor;
    `uvm_component_utils(destination_monitor)

    virtual stream_if #(64) vif;
    uvm_analysis_port #(stream_beat_item) ap;
    longint dst_cycle = 0;
    int     cur_pkt_id = 1;
    int     cur_beat_idx = 0;

    function new(string name = "destination_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual stream_if #(64))::get(this, "", "dst_vif", vif)) begin
            `uvm_fatal("NO_VIF", "destination_monitor failed to retrieve dst_vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(vif.mon_cb);
            dst_cycle++;
            if (!vif.mon_cb.rst_n) begin
                cur_beat_idx = 0;
            end else if (vif.mon_cb.valid && vif.mon_cb.ready) begin
                stream_beat_item item = stream_beat_item::type_id::create("dst_beat");
                if (vif.mon_cb.packet_start) cur_beat_idx = 0;
                item.data         = vif.mon_cb.data;
                item.keep         = vif.mon_cb.keep;
                item.packet_start = vif.mon_cb.packet_start;
                item.packet_end   = vif.mon_cb.packet_end;
                item.packet_id    = cur_pkt_id;
                item.beat_idx     = cur_beat_idx;
                item.cycle_stamp  = dst_cycle;
                item.time_stamp   = $realtime;
                ap.write(item);

                if (vif.mon_cb.packet_end) begin
                    cur_pkt_id++;
                    cur_beat_idx = 0;
                end else begin
                    cur_beat_idx++;
                end
            end
        end
    endtask
endclass

class destination_agent extends uvm_agent;
    `uvm_component_utils(destination_agent)

    destination_sequencer sqr;
    destination_driver    drv;
    destination_monitor   mon;

    function new(string name = "destination_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = destination_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = destination_sequencer::type_id::create("sqr", this);
            drv = destination_driver::type_id::create("drv", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif

