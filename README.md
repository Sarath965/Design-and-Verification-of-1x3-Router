# 1×3 Router: UVM Verification Environment

A UVM 1.2 testbench that verifies a 1×3 packet router written in SystemVerilog.
It has a source agent, three destination (reader) agents, a reference model, a scoreboard,
a functional coverage model and protocol assertions, plus 8 tests.

## Table of contents

1. [Design overview](#design-overview)
2. [Packet format and protocol](#packet-format-and-protocol)
3. [Testbench architecture](#testbench-architecture)
4. [Repository layout](#repository-layout)
5. [How to run](#how-to-run)
6. [Test list](#test-list)
7. [Checks and assertions](#checks-and-assertions)
8. [Functional coverage](#functional-coverage)
9. [RTL bugs found and fixed](#rtl-bugs-found-and-fixed)
10. [Design decisions in the testbench](#design-decisions-in-the-testbench)

## Design overview

The router accepts one packet at a time on a byte-wide input and forwards it to one of three
output ports, each buffered by a 16×9 FIFO.

|Module|Role|
|-|-|
|`router\_top`|Connects everything|
|`router\_fsm`|8-state controller (decode address, load data, FIFO-full handling, parity check)|
|`router\_register`|Holds header and full-state bytes, computes running parity, drives `dout` and `error`|
|`router\_fifo`|16-deep FIFO per port; 9th bit tags the header; length counter|
|`router\_synchronizer`|Latches the address, selects `write\_enb` and `fifo\_full`, drives `vld\_out`, and raises a **soft reset** when a FIFO's data sits unread for 30 cycles|

### Interface

|Signal|Dir|Description|
|-|-|-|
|`clock`, `resetn`|in|Clock, active-low synchronous reset|
|`pkt\_valid`|in|High from the header through the last payload byte; **low on the parity byte**|
|`data\_in\[7:0]`|in|Packet bytes|
|`read\_enb\_0/1/2`|in|Reader asks for a byte from port *x*|
|`data\_out\_0/1/2\[7:0]`|out|Output bytes|
|`vld\_out\_0/1/2`|out|Port *x* FIFO is not empty|
|`busy`|out|Router cannot take a new byte; the source must hold its current byte|
|`error`|out|Packet parity mismatch|

\---

## Packet format and protocol

|Byte|Content|
|-|-|
|Header|`\[7:2]` payload length (1 to 63), `\[1:0]` destination port (0, 1, 2; **3 is invalid and ignored**)|
|Payload|`length` bytes|
|Parity|Bitwise XOR of the header and all payload bytes|

**Source-side rule that the driver follows.** A byte on the bus is taken by the DUT at a clock edge
**only if `busy` was low during that cycle**. The driver sends a byte, waits one edge, and advances
only if `busy` was low; otherwise it keeps holding the byte (the spec requires this).

**Parity tail.** After the parity byte is accepted, the driver keeps it on the bus until `busy` has
gone high and low again. When the FIFO is full the DUT latches the parity several cycles later.

**Reader side.** A read happens at an edge where `read\_enb \&\& vld\_out`. The byte appears on
`data\_out` one clock later.

\---

## Testbench architecture

```
                         tb\_top  (clock, reset, DUT, interfaces)
                                       │
  ┌──────────────────────────── uvm\_test ────────────────────────────┐
  │                                  env                              │
  │                                                                   │
  │  Source agent                                  Destination agents ×3
  │  ┌───────────────┐                             ┌──────────────────┐
  │  │ sequencer     │                             │ reader driver    │
  │  │ driver ───────┼──► DUT ──────────────────►  │ (read\_enb)       │
  │  │ monitor ──────┼─┐                           │ monitor ─────────┼─┐
  │  └───────────────┘ │                           └──────────────────┘ │
  │                    ▼                                                 │
  │             ┌─────────────┐   expected packet     actual packet      │
  │             │ Reference   │──────────────┐   ┌────────────────────────┘
  │             │ model       │              ▼   ▼
  │             └─────────────┘          ┌────────────┐
  │                    │                 │ Scoreboard │
  │                    ▼                 └────────────┘
  │             ┌─────────────┐
  │             │ Coverage    │◄── source + destination transactions
  │             └─────────────┘
  └──────────────────────────────────────────────────────────────────┘
   SVA assertions live in the interfaces
```

|Component|File|What it does|
|-|-|-|
|Interfaces + SVA|`router\_if.sv`|Clocking blocks (`input #1step`, `output #1`) and protocol assertions|
|Transactions|`router\_items.sv`|`router\_src\_item` (packet), `router\_exp\_item` (prediction), `router\_dst\_item` (observed output), `router\_dst\_cfg` (reader knobs)|
|Source agent|`router\_src\_agent.sv`|Driver sends packets honouring `busy`; monitor rebuilds accepted packets and watches `error` in a window after each packet|
|Destination agent ×3|`router\_dst\_agent.sv`|Reader driver (delay, random pauses, enable); monitor assembles packets from `data\_out` and detects soft-reset flushes|
|Reference model|`router\_ref\_model.sv`|Predicts target port, expected bytes, expected `error`, and "ignore" for address 3|
|Scoreboard|`router\_scoreboard.sv`|Per-port in-order compare of predicted and actual packets; checks `error`; handles flushes|
|Coverage|`router\_coverage.sv`|Three covergroups: source packets, destination outcomes, reader behaviour|
|Environment|`router\_env.sv`|Builds and connects everything|
|Sequences|`router\_seq\_lib.sv`|Constrained-random sequence with knobs, and a boundary-length sweep|
|Tests|`router\_tests.sv`|`base\_test` and 8 tests|
|Package|`router\_pkg.sv`|Includes all classes in dependency order|
|Top|`testbench.sv`|Clock and reset, DUT hookup, `uvm\_config\_db` setup, `run\_test()`|

\---

## Repository layout

The testbench uses flat ``include` statements, which suits EDA Playground. Because of this,
all testbench files must be on one include path.

```
router-1x3-uvm/
├── rtl/
│   └── design.sv              # all 5 RTL modules, with the 2 fixes applied
├── tb/
│   ├── testbench.sv           # top module
│   ├── router\_if.sv
│   ├── router\_pkg.sv
│   ├── router\_items.sv
│   ├── router\_src\_agent.sv
│   ├── router\_dst\_agent.sv
│   ├── router\_ref\_model.sv
│   ├── router\_scoreboard.sv
│   ├── router\_coverage.sv
│   ├── router\_env.sv
│   ├── router\_seq\_lib.sv
│   └── router\_tests.sv
├── docs/
│   └── Router\_Design.pdf      # specification (optional)
└── README.md
```

\---

## How to run

### EDA Playground (verified setup)

1. Paste `design.sv` into the **right** pane and `testbench.sv` into the **left** pane.
2. Add the other 11 testbench files with the **+** button, using exactly the same names.
3. Settings: SystemVerilog/Verilog, **UVM 1.2**, simulator **VCS**, Questa or Riviera-PRO.
4. Run Options: `+UVM\_TESTNAME=smoke\_test` (change the name to run another test).
5. A passing run ends with `\*\*\* TEST PASSED \*\*\*`.

Do **not** leave old copies of the RTL modules as separate tabs. Only `design.sv` is compiled, and
extra copies cause confusion about which version is in use.

### Local (VCS)

```bash
vcs -sverilog -full64 -ntb\_opts uvm-1.2 -timescale=1ns/1ns \\
    rtl/design.sv tb/testbench.sv +incdir+tb -debug\_access+all
./simv +UVM\_TESTNAME=smoke\_test
```

### Local (Questa)

```bash
vlog -sv +incdir+tb rtl/design.sv tb/testbench.sv
vsim -c tb\_top +UVM\_TESTNAME=smoke\_test -do "run -all; quit"
```

> The EDA Playground + VCS run above is the setup I have verified. The local command lines are
> typical examples; adjust UVM library flags to match your installation.

### Run the whole regression (local shell)

```bash
for t in smoke\_test length\_test bad\_parity\_test invalid\_addr\_test \\
         back\_to\_back\_test fifo\_full\_test soft\_reset\_test random\_test; do
  ./simv +UVM\_TESTNAME=$t -l logs/$t.log
  grep -H "TEST PASSED\\|TEST FAILED" logs/$t.log
done
```

\---

## Test list

|#|Test|Stimulus|Pass condition|
|-|-|-|-|
|1|`smoke\_test`|One packet (length 4) to each of ports 0, 1, 2; fast readers|All 3 delivered intact|
|2|`length\_test`|Lengths 1, 2, 14, 15, 16, 17, 63 (around the 16-entry FIFO depth)|All delivered intact|
|3|`bad\_parity\_test`|About 50% of packets carry a wrong parity byte|`error` high only for bad packets; all packets still delivered|
|4|`invalid\_addr\_test`|Address-3 packets mixed with valid ones|Address-3 packets produce no output and no `error`; valid packets pass|
|5|`back\_to\_back\_test`|Same-port bursts with zero idle gap, then random ports|Nothing lost, duplicated or mixed|
|6|`fifo\_full\_test`|Long packets (20 to 63 bytes) with slow, pausing readers|FIFO fills, `busy` stalls the source, data stays intact|
|7|`soft\_reset\_test`|One packet per port with the reader disabled, then re-enabled|Flush about 30 idle cycles after `vld\_out`; next packet is delivered|
|8|`random\_test`|100 random packets (port, length, 20% bad parity, 10% address 3) with random reader behaviour|All checks pass|

Select a test with `+UVM\_TESTNAME=<name>`. The default in `testbench.sv` is `smoke\_test`.

\---

## Checks and assertions

|Check|Where|
|-|-|
|Routing and data integrity (header, payload, parity as sent versus as read)|Scoreboard against reference model|
|`error` is high if and only if the parity byte is wrong|Scoreboard|
|Address-3 packets are ignored (no output, no `error`)|Reference model and scoreboard|
|Soft-reset flush happens 29 to 33 idle cycles after data became visible|Scoreboard|
|No leftover or unexpected packets at end of test|Scoreboard and destination monitor `check\_phase`|
|Source holds `data\_in` and `pkt\_valid` while `busy` is high|SVA in `router\_src\_if`|
|`busy`, `error`, `vld\_out` are not X/Z after reset and are low right after reset|SVA in both interfaces|
|Hung simulation|Driver timeout (20,000 cycles) and a 1,000,000-cycle watchdog in `base\_test`|

\---

## Functional coverage

|Covergroup|Coverpoints|Cross|
|-|-|-|
|`cg\_src` (source packets)|address {0, 1, 2, 3}; length bins {1, 2-13, 14, 15, 16, 17, 18-62, 63}; parity {good, bad}; `error` seen {no, yes}|address × length|
|`cg\_dst` (destination)|port {0, 1, 2}; outcome {delivered, flushed}|port × outcome|
|`cg\_reader` (reader behaviour)|start delay {0, 1-5, 6-20}; pause {none, some}|delay × pause|

Coverage percentages are printed at the end of each run:

```
UVM\_INFO router\_coverage.sv ... \[COV] coverage  source: 39.4%   destination: 66.7%   reader: 33.3%
```

Each run starts from zero, so a single short test shows low numbers (the numbers above are from
`smoke\_test`). `random\_test` and the full set of tests give the highest coverage.



## Design decisions in the testbench

* **Clocking blocks everywhere.** Inputs are sampled just before the clock edge (`#1step`) and outputs
change 1 time unit after it, so the testbench never races the DUT.
* **Accepted-byte detection.** The source monitor counts a byte as sent only when `busy` is low at the
edge. This matches what the DUT actually received, even when the driver stalls.
* **Error window.** The DUT raises `error` a few cycles after the parity byte, while it is busy. The source
monitor watches `error` from parity-accept until `busy` has risen and fallen, plus 4 clocks.
* **Address-3 packets.** Every byte of an address-3 packet ends in `2'b11`. Otherwise the FSM, which sits in
`DECODE\_ADDRESS` for the whole packet, could mistake a payload byte for a new header.
* **Reader as a responder.** Readers have no sequencer. A shared `router\_dst\_cfg` object holds the knobs
(enable, start delay, pause chance), and tests change it at run time.
* **Reader limits.** Keep `start\_delay\_max` at 20 or less and `gap\_max` at 10 or less. Longer idle time lets the DUT's
30-cycle timeout flush the FIFO, which is a real feature but unwanted in normal tests.
* **No packet is queued behind an unread one.** A new packet to a port whose FIFO is being soft-reset can
confuse the FSM (the header is already accepted when the FSM is sent back to `DECODE\_ADDRESS`).
`soft\_reset\_test` therefore waits 45 idle cycles before more traffic.
* **Destination monitor.** It builds packets from the header length. A FIFO that goes empty with no read is
reported as a *flush*. An X/Z header is reported once instead of causing a cascade of bad packets.

\---



\---

