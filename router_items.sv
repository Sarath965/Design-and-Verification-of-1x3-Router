// =====================================================================
// router_items.sv  -  TRANSACTIONS (data objects passed between classes)
// =====================================================================

// ---------------------------------------------------------------
// router_src_item : ONE PACKET sent into the router.
// "rand" fields are filled in by randomize(); constraints limit values.
// ---------------------------------------------------------------
class router_src_item extends uvm_sequence_item;

  rand bit [1:0]    addr;          // destination port (0,1,2; 3 = invalid)
  rand int unsigned len;           // number of payload bytes (1..63)
  rand bit [7:0]    payload[];     // the payload bytes
  rand bit          bad_parity;    // 1 = send a WRONG parity byte
  rand bit [7:0]    bad_mask;      // XORed into parity when bad_parity = 1
  rand bit          invalid_addr;  // 1 = use address 3 (router must ignore it)
  rand int unsigned gap_after;     // idle cycles after the packet

  bit [7:0] header;                // {len[5:0], addr}
  bit [7:0] parity;                // parity byte that will be sent
  bit       err_seen;              // filled by the source monitor: did DUT raise error?

  constraint c_len   { len inside {[1:63]}; payload.size() == len; }
  constraint c_addr  { if (invalid_addr) addr == 2'b11; else addr inside {[0:2]}; }
  // For address-3 packets every byte ends in 2'b11, otherwise the DUT
  // (sitting in DECODE_ADDRESS) could mistake a payload byte for a header.
  constraint c_inv   { if (invalid_addr) foreach (payload[i]) payload[i][1:0] == 2'b11; }
  constraint c_inv_d { soft invalid_addr == 1'b0; }   // default: valid address
  constraint c_bad   { if (bad_parity) bad_mask != 8'h00; else bad_mask == 8'h00; }
  constraint c_bad_d { soft bad_parity == 1'b0; }     // default: good parity
  constraint c_gap   { soft gap_after inside {[0:6]}; }

  `uvm_object_utils(router_src_item)

  function new(string name = "router_src_item");
    super.new(name);
  endfunction

  // Runs automatically after randomize(): builds header and parity
  function void post_randomize();
    bit [7:0] x;
    header = {len[5:0], addr};
    x = header;
    foreach (payload[i]) x ^= payload[i];   // parity = XOR of header and payload
    parity = x ^ bad_mask;                  // bad_mask = 0 -> good parity
  endfunction

  function string convert2string();
    return $sformatf("addr=%0d len=%0d bad_parity=%0b invalid=%0b err_seen=%0b gap=%0d",
                     addr, len, bad_parity, invalid_addr, err_seen, gap_after);
  endfunction

endclass


// ---------------------------------------------------------------
// router_exp_item : what the REFERENCE MODEL predicts for one packet.
// ---------------------------------------------------------------
class router_exp_item extends uvm_object;

  int       port;            // output port the packet must appear on
  bit       ignore;          // 1 = address-3 packet, nothing should come out
  bit       expect_error;    // 1 = parity is wrong, DUT must raise 'error'
  bit       seen_error;      // what the DUT actually did (from the source monitor)
  bit [7:0] data[$];         // expected bytes: header, payload..., parity

  `uvm_object_utils(router_exp_item)

  function new(string name = "router_exp_item");
    super.new(name);
  endfunction

endclass


// ---------------------------------------------------------------
// router_dst_item : what a destination MONITOR saw at one output port.
// ---------------------------------------------------------------
class router_dst_item extends uvm_sequence_item;

  int          port;
  logic [7:0]  data[$];       // 4-state so X/Z bytes stay visible
  bit          flushed;       // 1 = FIFO emptied without being read (soft reset)
  bit          bad_hdr;       // 1 = first byte was X/Z, so the length is unknown
  int unsigned idle_cycles;   // cycles the data sat unread before the flush

  `uvm_object_utils(router_dst_item)

  function new(string name = "router_dst_item");
    super.new(name);
  endfunction

endclass


// ---------------------------------------------------------------
// router_dst_cfg : "knobs" that control how a READER behaves.
// Tests change these values while the simulation runs.
// ---------------------------------------------------------------
class router_dst_cfg extends uvm_object;

  bit          enable          = 1'b1; // 0 = never read (used by soft reset test)
  int unsigned start_delay_min = 0;    // cycles to wait after vld_out before reading
  int unsigned start_delay_max = 3;    // keep <= 20, otherwise the DUT soft-resets
  int unsigned gap_pct         = 0;    // % chance to pause after each byte read
  int unsigned gap_max         = 3;    // pause length 1..gap_max cycles (keep <= 10)

  `uvm_object_utils(router_dst_cfg)

  function new(string name = "router_dst_cfg");
    super.new(name);
  endfunction

endclass
