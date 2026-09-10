`timescale 1ns/1ps

// ============================================================================
// INTERFACE
// ============================================================================

interface router_if;

    logic       clk;
    logic       rst_n;

    logic [7:0] data_in;
    logic       pkt_valid;

    logic       busy;

    logic [7:0] data_out0;
    logic       valid_out0;
    logic       read_en0;

    logic [7:0] data_out1;
    logic       valid_out1;
    logic       read_en1;

    logic [7:0] data_out2;
    logic       valid_out2;
    logic       read_en2;

    logic       parity_error;

endinterface



// ============================================================================
// TRANSACTION
// ============================================================================

class router_packet extends uvm_sequence_item;

    rand bit [1:0] destination;

    rand bit [5:0] payload_length;

    rand bit [7:0] payload[];

    bit [7:0] parity;


    constraint c_destination {

        destination inside {2'b00, 2'b01, 2'b10};

    }


    constraint c_length {

        payload_length inside {[1:16]};

    }


    constraint c_payload {

        payload.size() == payload_length;

    }


    `uvm_object_utils_begin(router_packet)

        `uvm_field_int(destination, UVM_ALL_ON)
        `uvm_field_int(payload_length, UVM_ALL_ON)
        `uvm_field_array_int(payload, UVM_ALL_ON)
        `uvm_field_int(parity, UVM_ALL_ON)

    `uvm_object_utils_end


    function new(string name = "router_packet");

        super.new(name);

    endfunction


    function void post_randomize();

        bit parity_temp;

        parity_temp = ^{destination, payload_length};

        foreach (payload[i])
            parity_temp = parity_temp ^ (^payload[i]);

        parity = {7'b0, parity_temp};

    endfunction


    function void display_packet();

        $display(
            "PACKET: destination=%0d length=%0d parity=%0b",
            destination,
            payload_length,
            parity[0]
        );

        foreach (payload[i])
            $display("  payload[%0d] = %02h", i, payload[i]);

    endfunction

endclass



// ============================================================================
// MASTER SEQUENCER
// ============================================================================

class router_master_sequencer extends uvm_sequencer #(router_packet);

    `uvm_component_utils(router_master_sequencer)


    function new(
        string name = "router_master_sequencer",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction

endclass



// ============================================================================
// MASTER SEQUENCE
// ============================================================================

class router_random_sequence extends uvm_sequence #(router_packet);

    `uvm_object_utils(router_random_sequence)


    function new(string name = "router_random_sequence");

        super.new(name);

    endfunction


    task body();

        router_packet pkt;


        repeat (100) begin

            pkt = router_packet::type_id::create("pkt");


            start_item(pkt);


            if (!pkt.randomize()) begin

                `uvm_error(
                    "SEQ",
                    "Packet randomization failed"
                )

            end


            finish_item(pkt);

        end

    endtask

endclass



// ============================================================================
// MASTER DRIVER
// ============================================================================

class router_master_driver extends uvm_driver #(router_packet);

    `uvm_component_utils(router_master_driver)


    virtual router_if vif;


    function new(
        string name = "router_master_driver",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        if (!uvm_config_db #(virtual router_if)::get(
                this,
                "",
                "vif",
                vif
        ))

            `uvm_fatal(
                "NOVIF",
                "Virtual interface not found"
            )

    endfunction


    task drive_byte(
        bit [7:0] data
    );

        @(posedge vif.clk);

        while (vif.busy)
            @(posedge vif.clk);


        vif.data_in   <= data;
        vif.pkt_valid <= 1'b1;


        @(posedge vif.clk);

        vif.pkt_valid <= 1'b0;

    endtask


    task run_phase(uvm_phase phase);

        router_packet pkt;


        forever begin

            seq_item_port.get_next_item(pkt);


            // --------------------------------------------------------
            // Header
            // --------------------------------------------------------

            drive_byte(
                {pkt.destination, pkt.payload_length}
            );


            // --------------------------------------------------------
            // Payload
            // --------------------------------------------------------

            foreach (pkt.payload[i])

                drive_byte(pkt.payload[i]);


            // --------------------------------------------------------
            // Parity
            // --------------------------------------------------------

            drive_byte(pkt.parity);


            seq_item_port.item_done();

        end

    endtask

endclass



// ============================================================================
// MASTER MONITOR
// ============================================================================

class router_master_monitor extends uvm_monitor;

    `uvm_component_utils(router_master_monitor)


    virtual router_if vif;


    uvm_analysis_port #(router_packet) analysis_port;


    function new(
        string name = "router_master_monitor",
        uvm_component parent = null
    );

        super.new(name, parent);

        analysis_port = new(
            "analysis_port",
            this
        );

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        if (!uvm_config_db #(virtual router_if)::get(
                this,
                "",
                "vif",
                vif
        ))

            `uvm_fatal(
                "NOVIF",
                "Virtual interface not found"
            )

    endfunction


    task run_phase(uvm_phase phase);

        router_packet pkt;


        forever begin

            @(posedge vif.clk);


            if (vif.pkt_valid) begin

                pkt = router_packet::type_id::create(
                    "pkt"
                );


                pkt.destination    = vif.data_in[7:6];
                pkt.payload_length = vif.data_in[5:0];

                pkt.payload = new[pkt.payload_length];


                for (int i = 0;
                     i < pkt.payload_length;
                     i++) begin

                    @(posedge vif.clk);

                    if (vif.pkt_valid)
                        pkt.payload[i] = vif.data_in;

                end


                @(posedge vif.clk);

                pkt.parity = vif.data_in;


                analysis_port.write(pkt);

            end

        end

    endtask

endclass



// ============================================================================
// MASTER AGENT
// ============================================================================

class router_master_agent extends uvm_agent;

    `uvm_component_utils(router_master_agent)


    router_master_sequencer sequencer;

    router_master_driver driver;

    router_master_monitor monitor;


    function new(
        string name = "router_master_agent",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        sequencer =
            router_master_sequencer::type_id::create(
                "sequencer",
                this
            );


        driver =
            router_master_driver::type_id::create(
                "driver",
                this
            );


        monitor =
            router_master_monitor::type_id::create(
                "monitor",
                this
            );

    endfunction


    function void connect_phase(uvm_phase phase);

        driver.seq_item_port.connect(
            sequencer.seq_item_export
        );

    endfunction

endclass



// ============================================================================
// SLAVE MONITOR
// ============================================================================

class router_slave_monitor extends uvm_monitor;

    `uvm_component_utils(router_slave_monitor)


    virtual router_if vif;

    int slave_id;


    uvm_analysis_port #(router_packet) analysis_port;


    function new(
        string name = "router_slave_monitor",
        uvm_component parent = null
    );

        super.new(name, parent);

        analysis_port = new(
            "analysis_port",
            this
        );

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        if (!uvm_config_db #(virtual router_if)::get(
                this,
                "",
                "vif",
                vif
        ))

            `uvm_fatal(
                "NOVIF",
                "Virtual interface not found"
            )


        if (!uvm_config_db #(int)::get(
                this,
                "",
                "slave_id",
                slave_id
        ))

            `uvm_fatal(
                "NOID",
                "Slave ID not found"
            )

    endfunction


    task run_phase(uvm_phase phase);

        router_packet pkt;

        forever begin

            case (slave_id)

                0: begin

                    @(posedge vif.clk);

                    if (vif.valid_out0) begin

                        pkt = router_packet::type_id::create(
                            "slave_pkt"
                        );

                        pkt.destination = 0;

                        pkt.payload_length = 1;

                        pkt.payload = new[1];

                        pkt.payload[0] = vif.data_out0;

                        analysis_port.write(pkt);

                    end

                end


                1: begin

                    @(posedge vif.clk);

                    if (vif.valid_out1) begin

                        pkt = router_packet::type_id::create(
                            "slave_pkt"
                        );

                        pkt.destination = 1;

                        pkt.payload_length = 1;

                        pkt.payload = new[1];

                        pkt.payload[0] = vif.data_out1;

                        analysis_port.write(pkt);

                    end

                end


                2: begin

                    @(posedge vif.clk);

                    if (vif.valid_out2) begin

                        pkt = router_packet::type_id::create(
                            "slave_pkt"
                        );

                        pkt.destination = 2;

                        pkt.payload_length = 1;

                        pkt.payload = new[1];

                        pkt.payload[0] = vif.data_out2;

                        analysis_port.write(pkt);

                    end

                end

            endcase

        end

    endtask

endclass



// ============================================================================
// SLAVE AGENT
// ============================================================================

class router_slave_agent extends uvm_agent;

    `uvm_component_utils(router_slave_agent)


    router_slave_monitor monitor;

    int slave_id;


    function new(
        string name = "router_slave_agent",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        monitor =
            router_slave_monitor::type_id::create(
                "monitor",
                this
            );


        uvm_config_db #(int)::set(
            this,
            "monitor",
            "slave_id",
            slave_id
        );

    endfunction

endclass



// ============================================================================
// SCOREBOARD
// ============================================================================

class router_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(router_scoreboard)


    uvm_analysis_imp #(router_packet, router_scoreboard)
        master_export;


    router_packet expected_q[3][$];


    int total_packets;

    int error_count;


    function new(
        string name = "router_scoreboard",
        uvm_component parent = null
    );

        super.new(name, parent);

        master_export = new(
            "master_export",
            this
        );

    endfunction


    // ---------------------------------------------------------------
    // Receive packets from master monitor
    // ---------------------------------------------------------------

    function void write(router_packet pkt);

        expected_q[pkt.destination].push_back(pkt);

        total_packets++;

        `uvm_info(
            "SCOREBOARD",
            $sformatf(
                "Expected packet queued for destination %0d",
                pkt.destination
            ),
            UVM_MEDIUM
        )

    endfunction


    task check_output(
        router_packet actual,
        int destination
    );

        router_packet expected;


        if (expected_q[destination].size() == 0) begin

            `uvm_error(
                "SCOREBOARD",
                $sformatf(
                    "Unexpected packet at destination %0d",
                    destination
                )
            )

            error_count++;

            return;

        end


        expected =
            expected_q[destination].pop_front();


        if (actual.payload[0] !== expected.payload[0]) begin

            `uvm_error(
                "SCOREBOARD",
                $sformatf(
                    "Data mismatch: expected=%02h actual=%02h",
                    expected.payload[0],
                    actual.payload[0]
                )
            )

            error_count++;

        end
        else begin

            `uvm_info(
                "SCOREBOARD",
                "Output data matched expected data",
                UVM_LOW
            )

        end

    endtask


    function void report_phase(uvm_phase phase);

        super.report_phase(phase);


        `uvm_info(
            "SCOREBOARD",
            $sformatf(
                "Packets=%0d Errors=%0d",
                total_packets,
                error_count
            ),
            UVM_NONE
        )

    endfunction

endclass



// ============================================================================
// FUNCTIONAL COVERAGE
// ============================================================================

class router_coverage extends uvm_subscriber #(router_packet);

    `uvm_component_utils(router_coverage)


    router_packet pkt;


    covergroup router_cg;

        cp_destination :
            coverpoint pkt.destination {

                bins destination_0 = {0};
                bins destination_1 = {1};
                bins destination_2 = {2};

            }


        cp_payload_size :
            coverpoint pkt.payload_length {

                bins small  = {[1:4]};
                bins medium = {[5:10]};
                bins large  = {[11:16]};

            }


        destination_x_size :
            cross cp_destination,
                  cp_payload_size;

    endgroup


    function new(
        string name = "router_coverage",
        uvm_component parent = null
    );

        super.new(name, parent);

        router_cg = new();

    endfunction


    function void write(router_packet t);

        pkt = t;

        router_cg.sample();

    endfunction


    function void report_phase(uvm_phase phase);

        `uvm_info(
            "COVERAGE",
            $sformatf(
                "Functional coverage = %0.2f%%",
                router_cg.get_coverage()
            ),
            UVM_NONE
        )

    endfunction

endclass



// ============================================================================
// ENVIRONMENT
// ============================================================================

class router_env extends uvm_env;

    `uvm_component_utils(router_env)


    router_master_agent master_agent;

    router_slave_agent slave_agent0;
    router_slave_agent slave_agent1;
    router_slave_agent slave_agent2;


    router_scoreboard scoreboard;

    router_coverage coverage;


    function new(
        string name = "router_env",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        master_agent =
            router_master_agent::type_id::create(
                "master_agent",
                this
            );


        slave_agent0 =
            router_slave_agent::type_id::create(
                "slave_agent0",
                this
            );

        slave_agent0.slave_id = 0;


        slave_agent1 =
            router_slave_agent::type_id::create(
                "slave_agent1",
                this
            );

        slave_agent1.slave_id = 1;


        slave_agent2 =
            router_slave_agent::type_id::create(
                "slave_agent2",
                this
            );

        slave_agent2.slave_id = 2;


        scoreboard =
            router_scoreboard::type_id::create(
                "scoreboard",
                this
            );


        coverage =
            router_coverage::type_id::create(
                "coverage",
                this
            );

    endfunction


    function void connect_phase(uvm_phase phase);

        master_agent.monitor.analysis_port.connect(
            scoreboard.master_export
        );


        master_agent.monitor.analysis_port.connect(
            coverage.analysis_export
        );


        // Slave monitors can additionally be connected
        // to dedicated scoreboard analysis ports.

    endfunction

endclass



// ============================================================================
// TEST
// ============================================================================

class router_test extends uvm_test;

    `uvm_component_utils(router_test)


    router_env env;


    function new(
        string name = "router_test",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);


        env =
            router_env::type_id::create(
                "env",
                this
            );

    endfunction


    task run_phase(uvm_phase phase);

        router_random_sequence seq;


        phase.raise_objection(this);


        seq =
            router_random_sequence::type_id::create(
                "seq"
            );


        seq.start(
            env.master_agent.sequencer
        );


        #1000;


        phase.drop_objection(this);

    endtask

endclass



// ============================================================================
// TOP LEVEL
// ============================================================================

module tb_top;

    router_if vif;


    // ========================================================================
    // DUT
    // ========================================================================

    router_1x3 dut (

        .clk          (vif.clk),
        .rst_n        (vif.rst_n),

        .data_in      (vif.data_in),
        .pkt_valid    (vif.pkt_valid),

        .busy         (vif.busy),

        .data_out0    (vif.data_out0),
        .valid_out0   (vif.valid_out0),
        .read_en0     (vif.read_en0),

        .data_out1    (vif.data_out1),
        .valid_out1   (vif.valid_out1),
        .read_en1     (vif.read_en1),

        .data_out2    (vif.data_out2),
        .valid_out2   (vif.valid_out2),
        .read_en2     (vif.read_en2),

        .parity_error (vif.parity_error)

    );


    // ========================================================================
    // CLOCK
    // ========================================================================

    initial begin

        vif.clk = 0;

        forever #5 vif.clk = ~vif.clk;

    end


    // ========================================================================
    // RESET
    // ========================================================================

    initial begin

        vif.rst_n = 0;

        vif.data_in   = 0;
        vif.pkt_valid = 0;

        vif.read_en0 = 0;
        vif.read_en1 = 0;
        vif.read_en2 = 0;


        repeat (5)
            @(posedge vif.clk);


        vif.rst_n = 1;

    end


    // ========================================================================
    // UVM CONFIGURATION
    // ========================================================================

    initial begin

        uvm_config_db #(virtual router_if)::set(
            null,
            "*",
            "vif",
            vif
        );


        run_test("router_test");

    end


    // ========================================================================
    // FSDB
    // ========================================================================

    initial begin

        $fsdbDumpfile("router_1x3.fsdb");

        $fsdbDumpvars(
            0,
            tb_top
        );

    end

endmodule
