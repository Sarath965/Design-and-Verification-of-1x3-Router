// =====================================================================
// router_env.sv  -  ENVIRONMENT
// Creates every component and connects them:
//
//   src monitor --> ref model --> scoreboard <-- 3 dst monitors
//   src monitor --> coverage  <-- 3 dst monitors
// =====================================================================
class router_env extends uvm_env;
  `uvm_component_utils(router_env)

  router_src_agent  src_agent;
  router_dst_agent  dst_agent[3];    // one per output port
  router_dst_cfg    dst_cfg[3];      // reader knobs, one per port
  router_ref_model  ref_model;
  router_scoreboard scb;
  router_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    src_agent = router_src_agent::type_id::create("src_agent", this);

    for (int i = 0; i < 3; i++) begin
      // reader config object, handed to that port's reader driver
      dst_cfg[i] = router_dst_cfg::type_id::create($sformatf("dst_cfg%0d", i));
      uvm_config_db#(router_dst_cfg)::set(this, $sformatf("dst_agent%0d.drv", i), "cfg", dst_cfg[i]);

      dst_agent[i] = router_dst_agent::type_id::create($sformatf("dst_agent%0d", i), this);
      dst_agent[i].port_id = i;
    end

    ref_model = router_ref_model::type_id::create("ref_model", this);
    scb       = router_scoreboard::type_id::create("scb", this);
    cov       = router_coverage::type_id::create("cov", this);

    for (int i = 0; i < 3; i++) cov.cfgs[i] = dst_cfg[i];
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // source side
    src_agent.mon.ap.connect(ref_model.analysis_export);   // packets -> predictor
    src_agent.mon.ap.connect(cov.src_imp);                 // packets -> coverage
    ref_model.exp_ap.connect(scb.exp_imp);                 // predictions -> scoreboard

    // destination side
    for (int i = 0; i < 3; i++) begin
      dst_agent[i].mon.ap.connect(scb.dst_imp);            // actual output -> scoreboard
      dst_agent[i].mon.ap.connect(cov.dst_imp);            // actual output -> coverage
    end
  endfunction

endclass
