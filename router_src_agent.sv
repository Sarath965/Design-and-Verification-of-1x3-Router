// =====================================================================
// router_src_agent.sv  -  SOURCE AGENT
//   sequencer : hands packets (router_src_item) to the driver
//   driver    : wiggles pkt_valid / data_in on the pins
//   monitor   : watches the pins and rebuilds the packets that were sent
// =====================================================================
typedef uvm_sequencer #(router_src_item) router_src_sequencer;


// ---------------------------------------------------------------
// DRIVER
// KEY IDEA: a byte put on the bus is accepted by the DUT at a clock
// edge ONLY IF busy was low during that cycle. So after driving a byte
// we wait one edge, look at busy, and move to the next byte only if the
// byte was accepted; otherwise we simply keep holding it (spec rule).
// ---------------------------------------------------------------
class router_src_driver extends uvm_driver #(router_src_item);
  `uvm_component_utils(router_src_driver)

  virtual router_src_if vif;     // handle to the real interface

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_src_if)::get(this, "", "src_vif", vif))
      `uvm_fatal("NOVIF", "src_vif not set for router_src_driver")
  endfunction

  task run_phase(uvm_phase phase);
    wait (vif.resetn === 1'b1);          // wait for reset to finish
    repeat (2) @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);  // ask the sequencer for a packet
      drive_item(req);                   // send it
      seq_item_port.item_done();         // tell the sequencer we finished
    end
  endtask

  // Wait one clock edge; return once the byte on the bus was accepted
  task accept_byte();
    int unsigned n = 0;
    do begin
      @(vif.drv_cb);
      n++;
      if (n > 20000) `uvm_fatal("TIMEOUT", "busy stuck high - DUT hung")
    end while (vif.drv_cb.busy !== 1'b0);   // busy high -> byte dropped -> hold it
  endtask

  task drive_item(router_src_item it);
    int unsigned n = 0;

    // 1) header byte, pkt_valid goes high together with it
    vif.drv_cb.pkt_valid <= 1'b1;
    vif.drv_cb.data_in   <= it.header;
    accept_byte();

    // 2) payload bytes, pkt_valid stays high
    foreach (it.payload[i]) begin
      vif.drv_cb.data_in <= it.payload[i];
      accept_byte();
    end

    // 3) parity byte, pkt_valid goes LOW (marks the end of the packet)
    vif.drv_cb.pkt_valid <= 1'b0;
    vif.drv_cb.data_in   <= it.parity;
    accept_byte();

    // 4) keep the parity byte on the bus until the DUT is finished with the
    //    packet (busy low again). Needed when the FIFO is full: the DUT then
    //    latches the parity a few cycles later.
    do begin
      @(vif.drv_cb);
      n++;
      if (n > 20000) `uvm_fatal("TIMEOUT", "busy stuck high after parity")
    end while (vif.drv_cb.busy !== 1'b0);

    // 5) optional idle time before the next packet
    repeat (it.gap_after) @(vif.drv_cb);
  endtask

endclass


// ---------------------------------------------------------------
// MONITOR
// Only watches. A byte counts as "sent" when busy is low at a clock edge.
// First accepted byte with pkt_valid=1 is the header; following ones are
// payload; the accepted byte with pkt_valid=0 is the parity byte.
// It also watches 'error' for a few cycles after each packet.
// ---------------------------------------------------------------
class router_src_monitor extends uvm_monitor;
  `uvm_component_utils(router_src_monitor)

  virtual router_src_if vif;
  uvm_analysis_port #(router_src_item) ap;   // broadcasts finished packets
  router_src_item win_q[$];                  // packets waiting for their error window

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual router_src_if)::get(this, "", "src_vif", vif))
      `uvm_fatal("NOVIF", "src_vif not set for router_src_monitor")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      collect_packets();    // thread 1: rebuild packets from the pins
      collect_errors();     // thread 2: look at 'error' after each packet
    join
  endtask

  task collect_packets();
    bit       in_pkt;
    bit [7:0] hdr;
    bit [7:0] par;
    bit [7:0] x;
    bit [7:0] pay[$];
    router_src_item it;
    in_pkt = 0;
    forever begin
      @(vif.mon_cb);
      if (vif.resetn !== 1'b1) begin
        in_pkt = 0;
        pay.delete();
        continue;
      end
      if (vif.mon_cb.busy === 1'b0) begin            // DUT accepted the byte
        if (!in_pkt) begin
          if (vif.mon_cb.pkt_valid === 1'b1) begin   // header
            hdr    = vif.mon_cb.data_in;
            in_pkt = 1;
            pay.delete();
          end
        end
        else begin
          if (vif.mon_cb.pkt_valid === 1'b1) begin   // payload
            pay.push_back(vif.mon_cb.data_in);
          end
          else begin                                 // parity -> packet complete
            par    = vif.mon_cb.data_in;
            in_pkt = 0;
            it = router_src_item::type_id::create("src_mon_item");
            it.header       = hdr;
            it.addr         = hdr[1:0];
            it.len          = hdr[7:2];
            it.payload      = new[pay.size()];
            foreach (pay[i]) it.payload[i] = pay[i];
            it.parity       = par;
            x = hdr;
            foreach (pay[i]) x ^= pay[i];
            it.bad_parity   = (x != par);
            it.invalid_addr = (hdr[1:0] == 2'b11);
            it.err_seen     = 1'b0;
            win_q.push_back(it);                     // now wait to see 'error'
          end
        end
      end
    end
  endtask

  // The DUT raises 'error' a couple of cycles after the parity byte, while it
  // is busy checking. Window = from parity accept until busy has gone high and
  // low again, plus 4 more clocks. We publish the packet when the window ends.
  task collect_errors();
    router_src_item cur;
    int phase;
    int tail;
    cur   = null;
    phase = 0;
    tail  = 0;
    forever begin
      @(vif.mon_cb);
      if (cur == null && win_q.size() > 0) begin
        cur   = win_q.pop_front();
        phase = cur.invalid_addr ? 2 : 0;   // address-3 packets never raise busy
        tail  = 0;
      end
      if (cur != null) begin
        if (vif.mon_cb.error === 1'b1) cur.err_seen = 1'b1;
        case (phase)
          0: if (vif.mon_cb.busy === 1'b1) phase = 1;                       // wait busy high
          1: if (vif.mon_cb.busy === 1'b0) begin phase = 2; tail = 0; end   // wait busy low
          default: begin                                                    // 4 extra clocks
            tail++;
            if (tail >= 4) begin
              ap.write(cur);     // send the finished packet to the ref model + coverage
              cur = null;
            end
          end
        endcase
      end
    end
  endtask

endclass


// ---------------------------------------------------------------
// AGENT : just creates and connects sequencer + driver + monitor
// ---------------------------------------------------------------
class router_src_agent extends uvm_agent;
  `uvm_component_utils(router_src_agent)

  router_src_sequencer sqr;
  router_src_driver    drv;
  router_src_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = router_src_sequencer::type_id::create("sqr", this);
    drv = router_src_driver::type_id::create("drv", this);
    mon = router_src_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);   // sequencer -> driver
  endfunction

endclass
