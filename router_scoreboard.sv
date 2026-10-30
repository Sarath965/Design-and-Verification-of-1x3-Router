// =====================================================================
// router_scoreboard.sv  -  SCOREBOARD (the checker)
// Inputs : expected packets   (from the reference model)
//          actual packets     (from the 3 destination monitors)
// It keeps one queue of each per output port and compares them in order.
// =====================================================================
`uvm_analysis_imp_decl(_exp)   // creates "uvm_analysis_imp_exp"  -> calls write_exp()
`uvm_analysis_imp_decl(_dst)   // creates "uvm_analysis_imp_dst"  -> calls write_dst()

class router_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(router_scoreboard)

  uvm_analysis_imp_exp #(router_exp_item, router_scoreboard) exp_imp;
  uvm_analysis_imp_dst #(router_dst_item, router_scoreboard) dst_imp;

  router_exp_item exp_q[3][$];     // expected packets, one queue per port
  router_dst_item act_q[3][$];     // actual packets,   one queue per port

  // ---- knobs a test may set ----
  bit          allow_flush      = 1'b0;   // soft-reset test sets this to 1
  int          expected_flushes = -1;     // >= 0: exact number of flushes expected
  int unsigned min_flush_idle   = 29;     // a flush must happen after 29..33
  int unsigned max_flush_idle   = 33;     //   cycles of unread data

  // ---- statistics ----
  int unsigned n_pkts, n_ignored, n_match, n_mismatch, n_flush, n_err_ok, n_err_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_imp = new("exp_imp", this);
    dst_imp = new("dst_imp", this);
  endfunction

  // number of packets still waiting to be compared (used by the test to know
  // when everything has been delivered)
  function int unsigned pending();
    int unsigned n = 0;
    for (int p = 0; p < 3; p++) n += exp_q[p].size() + act_q[p].size();
    return n;
  endfunction

  // ---- a prediction arrived from the reference model ----
  function void write_exp(router_exp_item e);
    n_pkts++;

    // check the 'error' output: must be high exactly when parity was wrong
    if (e.expect_error != e.seen_error) begin
      n_err_bad++;
      `uvm_error("SCB", $sformatf("error flag wrong: expected %0b, DUT gave %0b (ignored pkt=%0b)",
                                  e.expect_error, e.seen_error, e.ignore))
    end
    else n_err_ok++;

    // address-3 packet: nothing is expected at any port
    if (e.ignore) begin
      n_ignored++;
      return;
    end

    exp_q[e.port].push_back(e);
    compare(e.port);
  endfunction

  // ---- a packet (or flush) was seen at an output port ----
  function void write_dst(router_dst_item t);
    act_q[t.port].push_back(t);
    compare(t.port);
  endfunction

  // helper functions to print the first few bytes of a packet
  function string fmt_exp(router_exp_item e);
    string s = $sformatf("%0d bytes:", e.data.size());
    foreach (e.data[i]) if (i < 7) s = {s, $sformatf(" %02h", e.data[i])};
    s = {s, " ... ", $sformatf("%02h", e.data[e.data.size()-1])};
    return s;
  endfunction

  function string fmt_act(router_dst_item a);
    string s = $sformatf("%0d bytes:", a.data.size());
    foreach (a.data[i]) if (i < 7) s = {s, $sformatf(" %02h", a.data[i])};
    if (a.data.size() > 0) s = {s, " ... ", $sformatf("%02h", a.data[a.data.size()-1])};
    return s;
  endfunction

  // Compare, in order, whatever is available for port p
  function void compare(int p);
    router_exp_item e;
    router_dst_item a;
    bit             ok;
    while (exp_q[p].size() > 0 && act_q[p].size() > 0) begin
      e = exp_q[p].pop_front();
      a = act_q[p].pop_front();

      // The FIFO was flushed instead of being read: this is the soft reset
      if (a.flushed) begin
        n_flush++;
        if (!allow_flush)
          `uvm_error("SCB", $sformatf("port %0d: unexpected FIFO flush after %0d idle cycles",
                                      p, a.idle_cycles))
        else if (a.idle_cycles < min_flush_idle || a.idle_cycles > max_flush_idle)
          `uvm_error("SCB", $sformatf("port %0d: flush after %0d idle cycles, expected %0d..%0d",
                                      p, a.idle_cycles, min_flush_idle, max_flush_idle))
        else
          `uvm_info("SCB", $sformatf("port %0d: unread packet flushed after %0d idle cycles (OK)",
                                     p, a.idle_cycles), UVM_LOW)
        continue;
      end

      // normal packet: sizes equal and every byte identical (=== also catches X/Z)
      ok = (e.data.size() == a.data.size());
      if (ok) foreach (e.data[i]) if (e.data[i] !== a.data[i]) ok = 1'b0;

      if (ok) n_match++;
      else begin
        n_mismatch++;
        `uvm_error("SCB", $sformatf("port %0d packet mismatch\n  expected %s\n  actual   %s",
                                    p, fmt_exp(e), fmt_act(a)))
      end
    end
  endfunction

  // End of test: nothing may be left over
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    for (int p = 0; p < 3; p++) begin
      if (exp_q[p].size() != 0)
        `uvm_error("SCB", $sformatf("port %0d: %0d packet(s) sent but never delivered", p, exp_q[p].size()))
      if (act_q[p].size() != 0)
        `uvm_error("SCB", $sformatf("port %0d: %0d unexpected packet(s) at the output", p, act_q[p].size()))
    end
    if (expected_flushes >= 0 && n_flush != expected_flushes)
      `uvm_error("SCB", $sformatf("expected %0d flush(es), saw %0d", expected_flushes, n_flush))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("\n------ SCOREBOARD SUMMARY ------\n packets sent         : %0d (address-3: %0d)\n packets matched      : %0d\n packet mismatches    : %0d\n flushes (soft reset) : %0d\n error flag ok / bad  : %0d / %0d\n--------------------------------",
              n_pkts, n_ignored, n_match, n_mismatch, n_flush, n_err_ok, n_err_bad), UVM_NONE)
  endfunction

endclass
