// =====================================================================
// router_dst_agent.sv  -  DESTINATION AGENT (one instance per output port)
//   driver  : the "reader". Raises read_enb when vld_out says data is ready.
//   monitor : collects the bytes that come out on data_out into packets.
// =====================================================================

// ---------------------------------------------------------------
// READER DRIVER
// Waits for vld_out, waits a random delay, then keeps read_enb high
// (with optional random pauses) until the FIFO is empty again.
// Its behaviour is controlled by router_dst_cfg.
// ---------------------------------------------------------------
class router_dst_driver extends uvm_component;
  `uvm_component_utils(router_dst_driver)

  virtual router_dst_if vif;
  router_dst_cfg        cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_dst_if)::get(this, "", "dst_vif", vif))
      `uvm_fatal("NOVIF", "dst_vif not set for router_dst_driver")
    if (!uvm_config_db#(router_dst_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "cfg not set for router_dst_driver")
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned d;
    int unsigned g;
    wait (vif.resetn === 1'b1);
    repeat (2) @(vif.drv_cb);
    forever begin
      // 1) wait until the FIFO holds data
      do @(vif.drv_cb); while (vif.drv_cb.vld_out !== 1'b1);

      // 2) react after a random delay (never more than ~20 cycles, or the
      //    DUT's 30-cycle timeout would flush the FIFO)
      d = $urandom_range(cfg.start_delay_max, cfg.start_delay_min);
      repeat (d) @(vif.drv_cb);
      while (!cfg.enable) @(vif.drv_cb);       // disabled: do not read at all

      // 3) read until the FIFO is empty
      vif.drv_cb.read_enb <= 1'b1;
      forever begin
        @(vif.drv_cb);
        if (vif.drv_cb.vld_out !== 1'b1) break;   // FIFO empty -> packet done
        if (!cfg.enable) break;
        if ($urandom_range(99, 0) < cfg.gap_pct) begin   // random pause
          vif.drv_cb.read_enb <= 1'b0;
          g = $urandom_range(cfg.gap_max, 1);
          repeat (g) @(vif.drv_cb);
          vif.drv_cb.read_enb <= 1'b1;
        end
      end
      vif.drv_cb.read_enb <= 1'b0;
    end
  endtask

endclass


// ---------------------------------------------------------------
// DESTINATION MONITOR
// A read happens at an edge where read_enb=1 AND vld_out=1. The byte
// appears on data_out one clock later. The first byte of a packet is the
// header, which tells us the packet length (len + 2 bytes in total).
// If vld_out drops without any read, the FIFO was flushed (soft reset).
// ---------------------------------------------------------------
class router_dst_monitor extends uvm_monitor;
  `uvm_component_utils(router_dst_monitor)

  virtual router_dst_if vif;
  uvm_analysis_port #(router_dst_item) ap;
  int port_id = 0;                 // which output port this monitor watches

  logic [7:0] bytes[$];            // bytes collected for the current packet
  bit         bad_hdr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual router_dst_if)::get(this, "", "dst_vif", vif))
      `uvm_fatal("NOVIF", "dst_vif not set for router_dst_monitor")
  endfunction

  // Package the collected bytes into an item and broadcast it
  function void emit(bit flushed, bit bad, int unsigned idle_c);
    router_dst_item it;
    it = router_dst_item::type_id::create("dst_item");
    it.port        = port_id;
    it.flushed     = flushed;
    it.bad_hdr     = bad;
    it.idle_cycles = idle_c;
    foreach (bytes[i]) it.data.push_back(bytes[i]);
    ap.write(it);
    bytes.delete();
    bad_hdr = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    bit          pend, pv, pr, cv, cr;
    logic [7:0]  b;
    int unsigned elen, idle;
    pend = 0; pv = 0; pr = 0; bad_hdr = 0; elen = 0; idle = 0;
    forever begin
      @(vif.mon_cb);
      if (vif.resetn !== 1'b1) begin
        bytes.delete();
        pend = 0; pv = 0; pr = 0; bad_hdr = 0; idle = 0;
        continue;
      end
      cv = (vif.mon_cb.vld_out  === 1'b1);    // current vld_out
      cr = (vif.mon_cb.read_enb === 1'b1);    // current read_enb

      // (1) pick up the byte requested by the read at the previous edge
      if (pend) begin
        b = vif.mon_cb.data_out;
        if (bytes.size() == 0) begin                 // first byte = header
          if ((^b) === 1'bx) bad_hdr = 1'b1;         // X/Z header: length unknown
          else               elen = b[7:2] + 2;      // header + payload + parity
        end
        bytes.push_back(b);
        if (!bad_hdr && bytes.size() == elen) emit(1'b0, 1'b0, 0);   // packet complete
      end

      // (2) vld_out fell from 1 to 0
      if (pv && !cv) begin
        if (!pr)          emit(1'b1, bad_hdr, idle);   // no read -> soft reset flush
        else if (bad_hdr) emit(1'b0, 1'b1, 0);         // unknown length: send what we have
      end

      pend = cv && cr;                        // a read happens at THIS edge
      if (cv) idle = cr ? 0 : idle + 1;       // count cycles data waits unread
      else    idle = 0;
      pv = cv;
      pr = cr;
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (bytes.size() != 0)
      `uvm_error("DST_MON", $sformatf("port %0d: %0d byte(s) of an incomplete packet at end of test",
                                      port_id, bytes.size()))
  endfunction

endclass


// ---------------------------------------------------------------
// DESTINATION AGENT : reader driver + monitor for one port
// ---------------------------------------------------------------
class router_dst_agent extends uvm_agent;
  `uvm_component_utils(router_dst_agent)

  router_dst_driver  drv;
  router_dst_monitor mon;
  int                port_id = 0;     // set by the env before build_phase

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = router_dst_driver::type_id::create("drv", this);
    mon = router_dst_monitor::type_id::create("mon", this);
    mon.port_id = port_id;
  endfunction

endclass
