// =====================================================================
// router_pkg.sv  -  one package that holds every UVM class.
// The ORDER of the includes matters: a class must be defined before
// another class uses it.
// =====================================================================
package router_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "router_items.sv"        // transactions + reader config
  `include "router_src_agent.sv"    // source agent (sequencer, driver, monitor)
  `include "router_dst_agent.sv"    // destination agent (reader driver, monitor)
  `include "router_ref_model.sv"    // reference model (predictor)
  `include "router_scoreboard.sv"   // scoreboard (comparator)
  `include "router_coverage.sv"     // functional coverage
  `include "router_env.sv"          // environment (ties everything together)
  `include "router_seq_lib.sv"      // stimulus sequences
  `include "router_tests.sv"        // the 8 tests
endpackage
