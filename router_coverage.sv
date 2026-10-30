// =====================================================================
// router_coverage.sv  -  FUNCTIONAL COVERAGE MODEL
// Answers "did our tests actually try the interesting situations?"
// Covergroups count how often each bin (value range) was hit.
// =====================================================================
`uvm_analysis_imp_decl(_cov_src)
`uvm_analysis_imp_decl(_cov_dst)

class router_coverage extends uvm_component;
  `uvm_component_utils(router_coverage)

  uvm_analysis_imp_cov_src #(router_src_item, router_coverage) src_imp;
  uvm_analysis_imp_cov_dst #(router_dst_item, router_coverage) dst_imp;

  router_dst_cfg cfgs[3];          // reader settings, assigned by the env

  // variables that the covergroups sample
  router_src_item sit;
  router_dst_item dit;
  int unsigned    rd_delay;
  int unsigned    rd_gap;

  // ---- source packets ----
  covergroup cg_src;
    option.per_instance = 1;
    cp_addr : coverpoint sit.addr {
      bins port0 = {0}; bins port1 = {1}; bins port2 = {2}; bins invalid = {3};
    }
    cp_len : coverpoint sit.len {
      bins one   = {1};
      bins short_len = {[2:13]};
      bins l14   = {14};
      bins l15   = {15};
      bins l16   = {16};
      bins l17   = {17};
      bins big   = {[18:62]};
      bins max   = {63};
    }
    cp_parity : coverpoint sit.bad_parity { bins good = {0}; bins bad = {1}; }
    cp_error  : coverpoint sit.err_seen   { bins no_error = {0}; bins error = {1}; }
    x_addr_len : cross cp_addr, cp_len;
  endgroup

  // ---- destination outcomes ----
  covergroup cg_dst;
    option.per_instance = 1;
    cp_port    : coverpoint dit.port    { bins p0 = {0}; bins p1 = {1}; bins p2 = {2}; }
    cp_outcome : coverpoint dit.flushed { bins delivered = {0}; bins flushed = {1}; }
    x_port_outcome : cross cp_port, cp_outcome;
  endgroup

  // ---- reader behaviour ----
  covergroup cg_reader;
    option.per_instance = 1;
    cp_delay : coverpoint rd_delay { bins none = {0}; bins low = {[1:5]}; bins high = {[6:20]}; }
    cp_pause : coverpoint rd_gap   { bins no_pause = {0}; bins some_pause = {[1:100]}; }
    x_delay_pause : cross cp_delay, cp_pause;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_src    = new();
    cg_dst    = new();
    cg_reader = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    src_imp = new("src_imp", this);
    dst_imp = new("dst_imp", this);
  endfunction

  // called for every packet from the source monitor
  function void write_cov_src(router_src_item t);
    sit = t;
    cg_src.sample();
  endfunction

  // called for every packet/flush from a destination monitor
  function void write_cov_dst(router_dst_item t);
    dit = t;
    cg_dst.sample();
    if (cfgs[t.port] != null) begin
      rd_delay = cfgs[t.port].start_delay_max;
      rd_gap   = cfgs[t.port].gap_pct;
      cg_reader.sample();
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("coverage  source: %0.1f%%   destination: %0.1f%%   reader: %0.1f%%",
              cg_src.get_inst_coverage(), cg_dst.get_inst_coverage(),
              cg_reader.get_inst_coverage()), UVM_NONE)
  endfunction

endclass
