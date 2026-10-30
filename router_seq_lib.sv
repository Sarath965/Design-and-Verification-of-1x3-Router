// =====================================================================
// router_seq_lib.sv  -  SEQUENCES (they create the packets)
// =====================================================================

// ---------------------------------------------------------------
// Random packets controlled by simple "knobs"
// ---------------------------------------------------------------
class router_rand_seq extends uvm_sequence #(router_src_item);
  `uvm_object_utils(router_rand_seq)

  int n_pkts     = 1;    // how many packets
  int min_len    = 1;    // payload length range
  int max_len    = 63;
  int fixed_addr = -1;   // -1 = random port, 0/1/2 = always that port
  int bad_pct    = 0;    // % of packets with a wrong parity byte
  int inv_pct    = 0;    // % of packets addressed to port 3
  int min_gap    = 0;    // idle cycles after each packet
  int max_gap    = 4;

  function new(string name = "router_rand_seq");
    super.new(name);
  endfunction

  task body();
    router_src_item req;
    repeat (n_pkts) begin
      req = router_src_item::type_id::create("req");
      start_item(req);                       // get permission to send
      if (!req.randomize() with {            // "local::" = the sequence's own knobs
            len       inside {[local::min_len : local::max_len]};
            gap_after inside {[local::min_gap : local::max_gap]};
            (local::fixed_addr >= 0) -> (invalid_addr || addr == local::fixed_addr);
            bad_parity   dist {1 := local::bad_pct, 0 := 100 - local::bad_pct};
            invalid_addr dist {1 := local::inv_pct, 0 := 100 - local::inv_pct};
          })
        `uvm_error("SEQ", "randomization failed")
      finish_item(req);                      // hand the packet to the driver
    end
  endtask

endclass


// ---------------------------------------------------------------
// One packet per boundary length, rotating over ports 0,1,2
// (14 / 15 / 16 / 17 sit around the 16-entry FIFO depth)
// ---------------------------------------------------------------
class router_len_sweep_seq extends uvm_sequence #(router_src_item);
  `uvm_object_utils(router_len_sweep_seq)

  function new(string name = "router_len_sweep_seq");
    super.new(name);
  endfunction

  task body();
    router_src_item req;
    int lens[7] = '{1, 2, 14, 15, 16, 17, 63};
    foreach (lens[i]) begin
      req = router_src_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { len == lens[i]; addr == (i % 3); })
        `uvm_error("SEQ", "randomization failed")
      finish_item(req);
    end
  endtask

endclass
