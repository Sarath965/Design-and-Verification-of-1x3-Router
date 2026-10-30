// =====================================================================
// router_tests.sv  -  THE 8 TESTS
// Every test: (1) sets how the readers behave, (2) sends packets,
// (3) waits until the scoreboard has checked everything.
// Pick one with  +UVM_TESTNAME=<test name>
// =====================================================================

// ---------------------------------------------------------------
// base_test : common code used by all tests
// ---------------------------------------------------------------
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  router_env            env;
  virtual router_src_if vif;     // only used to wait for clock edges

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = router_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual router_src_if)::get(this, "", "src_vif", vif))
      `uvm_fatal("NOVIF", "src_vif not set for the test")
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();      // prints the testbench tree in the log
  endfunction

  // Set the reader behaviour of all three ports:
  //  dmin/dmax = wait this many cycles after vld_out before reading
  //  gpct      = % chance of pausing after each byte read
  //  gmax      = longest pause in cycles
  function void set_readers(int unsigned dmin, int unsigned dmax,
                            int unsigned gpct, int unsigned gmax);
    for (int i = 0; i < 3; i++) begin
      env.dst_cfg[i].enable          = 1'b1;
      env.dst_cfg[i].start_delay_min = dmin;
      env.dst_cfg[i].start_delay_max = dmax;
      env.dst_cfg[i].gap_pct         = gpct;
      env.dst_cfg[i].gap_max         = gmax;
    end
  endfunction

  // Send n random packets (see router_rand_seq for the meaning of the knobs)
  task send_rand(int n, int min_len, int max_len, int fixed_addr = -1,
                 int bad_pct = 0, int inv_pct = 0, int min_gap = 0, int max_gap = 4);
    router_rand_seq seq = router_rand_seq::type_id::create("seq");
    seq.n_pkts     = n;
    seq.min_len    = min_len;
    seq.max_len    = max_len;
    seq.fixed_addr = fixed_addr;
    seq.bad_pct    = bad_pct;
    seq.inv_pct    = inv_pct;
    seq.min_gap    = min_gap;
    seq.max_gap    = max_gap;
    seq.start(env.src_agent.sqr);
  endtask

  // each test overrides this with its own stimulus
  virtual task run_sequences();
  endtask

  // wait until all packets have been delivered and checked
  task wait_drain();
    int unsigned n = 0;
    repeat (50) @(posedge vif.clock);
    while (env.scb.pending() != 0 && n < 20000) begin
      @(posedge vif.clock);
      n++;
    end
    repeat (100) @(posedge vif.clock);   // extra time to catch unexpected output
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "test running");   // keeps the simulation alive
    fork
      begin   // watchdog: stops a hung simulation
        repeat (1000000) @(posedge vif.clock);
        `uvm_fatal("WATCHDOG", "test did not finish within 1,000,000 cycles")
      end
    join_none
    run_sequences();
    wait_drain();
    phase.drop_objection(this, "test done");       // lets the simulation end
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    super.report_phase(phase);
    if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) == 0)
      `uvm_info("RESULT", "*** TEST PASSED ***", UVM_NONE)
    else
      `uvm_info("RESULT", "*** TEST FAILED ***", UVM_NONE)
  endfunction

endclass


// 1) One packet to each port, fast readers
class smoke_test extends base_test;
  `uvm_component_utils(smoke_test)
  function new(string name = "smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    set_readers(0, 2, 0, 1);
    for (int p = 0; p < 3; p++) send_rand(1, 4, 4, p);   // length 4 to port p
  endtask
endclass


// 2) Boundary lengths 1,2,14,15,16,17,63
class length_test extends base_test;
  `uvm_component_utils(length_test)
  function new(string name = "length_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    router_len_sweep_seq seq = router_len_sweep_seq::type_id::create("seq");
    set_readers(0, 3, 0, 1);
    seq.start(env.src_agent.sqr);
  endtask
endclass


// 3) About half of the packets carry a wrong parity byte
class bad_parity_test extends base_test;
  `uvm_component_utils(bad_parity_test)
  function new(string name = "bad_parity_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    set_readers(0, 5, 20, 3);
    send_rand(20, 1, 30, -1, 50);        // bad_pct = 50
  endtask
endclass


// 4) Address-3 packets mixed with valid ones: must be ignored
class invalid_addr_test extends base_test;
  `uvm_component_utils(invalid_addr_test)
  function new(string name = "invalid_addr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    set_readers(0, 5, 0, 1);
    send_rand(20, 1, 20, -1, 0, 40);     // inv_pct = 40
  endtask
endclass


// 5) Back-to-back packets: same port first, then random ports, no idle gap
class back_to_back_test extends base_test;
  `uvm_component_utils(back_to_back_test)
  function new(string name = "back_to_back_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    set_readers(5, 15, 0, 1);
    send_rand(6, 3, 14, 0, 0, 0, 0, 0);  // 6 packets, all to port 0
    send_rand(6, 3, 14, 1, 0, 0, 0, 0);  // 6 packets, all to port 1
    send_rand(8, 3, 14, -1, 0, 0, 0, 0); // 8 packets, random ports
  endtask
endclass


// 6) Long packets + slow, pausing readers: the FIFO fills and busy stalls the source
class fifo_full_test extends base_test;
  `uvm_component_utils(fifo_full_test)
  function new(string name = "fifo_full_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    set_readers(15, 20, 50, 6);
    send_rand(10, 20, 63, -1, 20);
  endtask
endclass


// 7) Nobody reads a packet: the router flushes it after ~30 cycles, then recovers
class soft_reset_test extends base_test;
  `uvm_component_utils(soft_reset_test)
  function new(string name = "soft_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    env.scb.allow_flush      = 1'b1;   // tell the scoreboard flushes are expected
    env.scb.expected_flushes = 3;      // one per port
    set_readers(0, 3, 0, 1);
    for (int p = 0; p < 3; p++) begin
      env.dst_cfg[p].enable = 1'b0;                  // nobody reads port p
      send_rand(1, 5 + p, 5 + p, p, 0, 0, 45, 45);   // short packet, then 45 idle cycles
      env.dst_cfg[p].enable = 1'b1;                  // flush has happened, readers back on
    end
    send_rand(9, 1, 14);                             // recovery traffic on all ports
  endtask
endclass


// 8) Random packets (port, length, parity) with random reader behaviour
class random_test extends base_test;
  `uvm_component_utils(random_test)
  function new(string name = "random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_sequences();
    int unsigned dmax_opt[4] = '{0, 3, 10, 20};
    int unsigned gmax_opt[3] = '{1, 3, 8};
    int unsigned gpct_opt[4] = '{0, 0, 30, 70};
    int unsigned dmax;
    repeat (5) begin                       // 5 rounds x 20 packets = 100 packets
      dmax = dmax_opt[$urandom_range(3, 0)];
      set_readers($urandom_range(dmax, 0), dmax,
                  gpct_opt[$urandom_range(3, 0)], gmax_opt[$urandom_range(2, 0)]);
      send_rand(20, 1, 63, -1, 20, 10, 0, 6);   // 20% bad parity, 10% address 3
    end
  endtask
endclass
