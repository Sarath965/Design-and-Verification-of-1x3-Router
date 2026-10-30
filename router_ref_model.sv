// =====================================================================
// router_ref_model.sv  -  REFERENCE MODEL (predictor)
// Receives every packet the source sent and works out what the router
// SHOULD do with it, independently of the DUT:
//   - which port it must appear on
//   - which bytes must come out (header, payload, parity)
//   - whether 'error' must be raised (parity wrong)
//   - or "ignore" if the address is 3
// The scoreboard then compares this prediction with what really happened.
// =====================================================================
class router_ref_model extends uvm_subscriber #(router_src_item);
  `uvm_component_utils(router_ref_model)

  uvm_analysis_port #(router_exp_item) exp_ap;   // sends predictions on

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_ap = new("exp_ap", this);
  endfunction

  // Called automatically for every packet from the source monitor
  function void write(router_src_item t);
    router_exp_item e;
    bit [7:0]       x;

    e = router_exp_item::type_id::create("exp_item");
    e.seen_error = t.err_seen;               // what the DUT did with 'error'

    // parity the router should compute: XOR of header and all payload bytes
    x = t.header;
    foreach (t.payload[i]) x ^= t.payload[i];
    e.expect_error = (x != t.parity);

    if (t.header[1:0] == 2'b11) begin
      // address 3 is invalid: nothing goes to any port, parity is not even checked
      e.ignore       = 1'b1;
      e.expect_error = 1'b0;
    end
    else begin
      e.ignore = 1'b0;
      e.port   = t.header[1:0];
      e.data.push_back(t.header);
      foreach (t.payload[i]) e.data.push_back(t.payload[i]);
      e.data.push_back(t.parity);            // router forwards the parity byte too
    end

    exp_ap.write(e);
  endfunction

endclass
