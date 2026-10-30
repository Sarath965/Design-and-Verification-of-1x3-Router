// =====================================================================
// router_if.sv  -  INTERFACES (bundles of signals) + ASSERTIONS
// A "clocking block" samples/drives signals at the clock edge so the
// testbench and the DUT never race each other.
//   input  #1step : read the value just BEFORE the clock edge
//   output #1     : change signals 1 time unit AFTER the clock edge
// =====================================================================

// ---------------- source side (data_in, pkt_valid, busy, error) ------
interface router_src_if (input logic clock, input logic resetn);

  logic       pkt_valid = 1'b0;   // starts at 0 so the DUT never sees X
  logic [7:0] data_in   = 8'h00;
  logic       busy;               // driven by the DUT
  logic       error;              // driven by the DUT

  // used by the DRIVER
  clocking drv_cb @(posedge clock);
    default input #1step output #1;
    output pkt_valid;
    output data_in;
    input  busy;
    input  error;
  endclocking

  // used by the MONITOR (only reads)
  clocking mon_cb @(posedge clock);
    default input #1step output #1;
    input pkt_valid;
    input data_in;
    input busy;
    input error;
  endclocking

  // ---- assertions (checked automatically every clock) ----
  // Spec rule: while busy is high, the source must keep its byte unchanged.
  a_hold_while_busy : assert property (
    @(posedge clock) disable iff (!resetn)
      busy |=> ($stable(data_in) && $stable(pkt_valid)))
    else $error("[SVA] source changed data_in/pkt_valid while busy was high");

  // busy and error must never be X/Z once reset is released
  a_known_outputs : assert property (
    @(posedge clock) disable iff (!resetn)
      !$isunknown(busy) && !$isunknown(error))
    else $error("[SVA] busy/error is X/Z after reset");

  // busy and error must be low right after reset
  a_reset_values : assert property (
    @(posedge clock) !resetn |=> (busy == 1'b0 && error == 1'b0))
    else $error("[SVA] busy/error not low after reset");

endinterface


// ---------------- destination side (one per output port) -------------
interface router_dst_if (input logic clock, input logic resetn);

  logic       read_enb = 1'b0;    // driven by the reader
  logic [7:0] data_out;           // driven by the DUT
  logic       vld_out;            // driven by the DUT

  clocking drv_cb @(posedge clock);
    default input #1step output #1;
    output read_enb;
    input  vld_out;
  endclocking

  clocking mon_cb @(posedge clock);
    default input #1step output #1;
    input read_enb;
    input vld_out;
    input data_out;
  endclocking

  a_vld_known : assert property (
    @(posedge clock) disable iff (!resetn) !$isunknown(vld_out))
    else $error("[SVA] vld_out is X/Z after reset");

  a_vld_reset : assert property (
    @(posedge clock) !resetn |=> (vld_out == 1'b0))
    else $error("[SVA] vld_out not low after reset");

endinterface
