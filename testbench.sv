// Code your testbench here
// or browse Examples
// =====================================================================
// testbench.sv  -  TOP MODULE
// Generates clock/reset, instantiates the DUT and the interfaces,
// hands the interfaces to UVM and starts the test.
// =====================================================================
`include "uvm_macros.svh"
import uvm_pkg::*;

`include "router_if.sv"      // interfaces must be compiled before the package
`include "router_pkg.sv"     // package containing all the UVM classes
import router_pkg::*;

module tb_top;

  bit clock;
  bit resetn;

  // 10 time-unit clock period
  always #5 clock = ~clock;

  // Active-low reset: low for 4 clock edges, then released
  initial begin
    resetn = 1'b0;
    repeat (4) @(posedge clock);
    #2 resetn = 1'b1;
  end

  // One interface for the source side, one per output port
  router_src_if src_if  (clock, resetn);
  router_dst_if dst_if0 (clock, resetn);
  router_dst_if dst_if1 (clock, resetn);
  router_dst_if dst_if2 (clock, resetn);

  // The design under test, wired to the interfaces
  router_top dut (
    .clock      (clock),
    .resetn     (resetn),
    .pkt_valid  (src_if.pkt_valid),
    .data_in    (src_if.data_in),
    .read_enb_0 (dst_if0.read_enb),
    .read_enb_1 (dst_if1.read_enb),
    .read_enb_2 (dst_if2.read_enb),
    .data_out_0 (dst_if0.data_out),
    .data_out_1 (dst_if1.data_out),
    .data_out_2 (dst_if2.data_out),
    .vld_out_0  (dst_if0.vld_out),
    .vld_out_1  (dst_if1.vld_out),
    .vld_out_2  (dst_if2.vld_out),
    .busy       (src_if.busy),
    .error      (src_if.error)
  );

  // Waveform dump (view with EPWave)
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

  // Give each UVM component the interface it needs, then run the test.
  // The test name comes from +UVM_TESTNAME; smoke_test is the default.
  initial begin
    uvm_config_db#(virtual router_src_if)::set(null, "uvm_test_top",                  "src_vif", src_if);
    uvm_config_db#(virtual router_src_if)::set(null, "uvm_test_top.env.src_agent.*",  "src_vif", src_if);
    uvm_config_db#(virtual router_dst_if)::set(null, "uvm_test_top.env.dst_agent0.*", "dst_vif", dst_if0);
    uvm_config_db#(virtual router_dst_if)::set(null, "uvm_test_top.env.dst_agent1.*", "dst_vif", dst_if1);
    uvm_config_db#(virtual router_dst_if)::set(null, "uvm_test_top.env.dst_agent2.*", "dst_vif", dst_if2);
    run_test("smoke_test");
  end

endmodule
