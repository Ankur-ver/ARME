// =============================================================================
// File        : tb/uvm/agents/source_agent.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : UVM source agent (sequencer, valid/ready driver, monitor).
// =============================================================================

`ifndef SOURCE_AGENT_SV
`define SOURCE_AGENT_SV

class source_sequencer extends uvm_sequencer #(stream_transaction);
    `uvm_component_utils(source_sequencer)
    function new(string name = "source_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

class source_driver extends uvm_driver #(stream_transaction);
    `uvm_component_utils(source_driver)

    virtual stream_if #(64) vif;
    int pkt_seq_num = 1;

    function new(string name = "source_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual stream_if #(64))::get(this, "", "src_vif", vif)) begin
            `uvm_fatal("NO_VIF", "source_driver failed to retrieve src_vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        stream_transaction req;
        vif.drv_cb.valid        <= 1'b0;
        vif.drv_cb.data         <= '0;
        vif.drv_cb.keep         <= '0;
        vif.drv_cb.packet_start <= 1'b0;
        vif.drv_cb.packet_end   <= 1'b0;

        wait (vif.rst_n === 1'b1);
        forever begin
            seq_item_port.get_next_item(req);
            drive_packet(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_packet(stream_transaction req);
        for (int i = 0; i < req.packet_length; i++) begin
            @(vif.drv_cb);
            vif.drv_cb.valid <= 1'b1;
            vif.drv_cb.data  <= req.data[i];
            vif.drv_cb.keep  <= req.keep[i];

            if (req.inject_malformed && req.malformed_orphan_eop) begin
                vif.drv_cb.packet_start <= 1'b0;
                vif.drv_cb.packet_end   <= (i == req.packet_length - 1);
            end else if (req.inject_malformed) begin
                // Trigger SOP twice mid-packet
                vif.drv_cb.packet_start <= (i == 0 || i == 1);
                vif.drv_cb.packet_end   <= (i == req.packet_length - 1);
            end else begin
                vif.drv_cb.packet_start <= (i == 0);
                vif.drv_cb.packet_end   <= (i == req.packet_length - 1);
            end

            // Hold valid & payload stable until ready sampled high
            do begin
                @(vif.drv_cb);
            end while (!vif.drv_cb.ready);
        end

        vif.drv_cb.valid        <= 1'b0;
        vif.drv_cb.packet_start <= 1'b0;
        vif.drv_cb.packet_end   <= 1'b0;
        repeat (req.inter_packet_gap) @(vif.drv_cb);
        pkt_seq_num++;
    endtask
endclass

class source_monitor extends uvm_monitor;
    `uvm_component_utils(source_monitor)

    virtual stream_if #(64) vif;
    uvm_analysis_port #(stream_beat_item) ap;
    longint src_cycle = 0;
    int     cur_pkt_id = 1;
    int     cur_beat_idx = 0;

    function new(string name = "source_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual stream_if #(64))::get(this, "", "src_vif", vif)) begin
            `uvm_fatal("NO_VIF", "source_monitor failed to retrieve src_vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(vif.mon_cb);
            src_cycle++;
            if (!vif.mon_cb.rst_n) begin
                cur_beat_idx = 0;
            end else if (vif.mon_cb.valid && vif.mon_cb.ready) begin
                stream_beat_item item = stream_beat_item::type_id::create("src_beat");
                if (vif.mon_cb.packet_start) cur_beat_idx = 0;
                item.data         = vif.mon_cb.data;
                item.keep         = vif.mon_cb.keep;
                item.packet_start = vif.mon_cb.packet_start;
                item.packet_end   = vif.mon_cb.packet_end;
                item.packet_id    = cur_pkt_id;
                item.beat_idx     = cur_beat_idx;
                item.cycle_stamp  = src_cycle;
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

class source_agent extends uvm_agent;
    `uvm_component_utils(source_agent)

    source_sequencer sqr;
    source_driver    drv;
    source_monitor   mon;

    function new(string name = "source_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = source_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = source_sequencer::type_id::create("sqr", this);
            drv = source_driver::type_id::create("drv", this);
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

