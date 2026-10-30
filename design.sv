// =====================================================================
// design.sv : 1x3 router RTL (all 5 modules)
// Fixes applied vs. the original:
//   router_fifo : header tag uses lfd_state_s (registered lfd_state)
//   router_fsm  : CHECK_PARITY_ERROR uses full_d (no duplicate parity write)
// =====================================================================

// ---------------------------------------------------------------------
// router_fifo
// ---------------------------------------------------------------------
module router_fifo (
    input  logic       clock,
    input  logic       resetn,
    input  logic       soft_reset,
    input  logic       write_enb,
    input  logic       read_enb,
    input  logic [7:0] data_in,
    input  logic       lfd_state,

    output logic [7:0] data_out,
    output logic       full,
    output logic       empty
);

    logic [8:0] mem [0:15];

    logic [4:0] read_ptr;
    logic [4:0] write_ptr;

    logic [6:0] counter;
    logic       lfd_state_s;

    // Register lfd_state so the header is tagged in the cycle it is written
    always_ff @(posedge clock) begin
        if (!resetn)
            lfd_state_s <= 1'b0;
        else
            lfd_state_s <= lfd_state;
    end

    // FIFO status flags
    assign empty = (read_ptr == write_ptr);
    assign full  = ({~read_ptr[4], read_ptr[3:0]} == write_ptr);

    // FIFO write and read operations
    always_ff @(posedge clock) begin
        if (!resetn) begin
            data_out  <= 8'h00;
            read_ptr  <= 5'd0;
            write_ptr <= 5'd0;
            counter   <= 7'd0;
        end
        else if (soft_reset) begin
            data_out  <= 8'hzz;
            read_ptr  <= 5'd0;
            write_ptr <= 5'd0;
            counter   <= 7'd0;
        end
        else begin

            // Write operation
            if (!full && write_enb) begin
                mem[write_ptr[3:0]] <= {lfd_state_s, data_in};
                write_ptr           <= write_ptr + 1'b1;
            end

            // Read operation
            if (!empty && read_enb) begin
                data_out <= mem[read_ptr[3:0]][7:0];

                // Header byte: load payload length + parity byte
                if (mem[read_ptr[3:0]][8]) begin
                    counter <= {1'b0, mem[read_ptr[3:0]][7:2]} + 1'b1;
                end
                else begin
                    if (counter != 0)
                        counter <= counter - 1'b1;

                    if (counter == 0)
                        data_out <= 8'hzz;
                end

                read_ptr <= read_ptr + 1'b1;
            end
        end
    end

endmodule


// ---------------------------------------------------------------------
// router_synchronizer
// ---------------------------------------------------------------------
module router_synchronizer(
  input detect_add,
  input [1:0] data_in,
  input write_enb_reg,
  input clock,
  input resetn,
  input read_enb_0,
  input read_enb_1,
  input read_enb_2,
  input empty_0,
  input empty_1,
  input empty_2,
  input full_0,
  input full_1,
  input full_2,
  output vld_out_0,
  output vld_out_1,
  output vld_out_2,
  output logic soft_reset_0,
  output logic soft_reset_1,
  output logic soft_reset_2,
  output logic fifo_full,
  output logic [2:0] write_enb
);
  reg [1:0] addr;
  reg [4:0] counter_0;
  reg [4:0] counter_1;
  reg [4:0] counter_2;

  assign vld_out_0 = ~empty_0;
  assign vld_out_1 = ~empty_1;
  assign vld_out_2 = ~empty_2;

  always@(posedge clock)
    begin
      if(~resetn)
        begin
          addr<=0;
        end
      else if(detect_add)
        begin
          addr<=data_in;
        end
    end

  always@(posedge clock)
    begin
      if(~resetn)
        begin
          counter_0 <= 0;
          soft_reset_0 <= 0;
        end
      else if (~vld_out_0)
        begin
          counter_0 <= 0;
          soft_reset_0 <= 0;
        end
      else if (read_enb_0)
        begin
          counter_0 <= 0;
          soft_reset_0 <= 0;
        end
      else
        begin
          if(counter_0 == 29)
            begin
              soft_reset_0 <= 1;
              counter_0 <= 0;
            end
          else
            begin
              counter_0 <= counter_0+1;
              soft_reset_0 <= 0;
            end
        end
    end

  always@(posedge clock)
    begin
      if(~resetn)
        begin
          counter_1 <= 0;
          soft_reset_1 <= 0;
        end
      else if (~vld_out_1)
        begin
          counter_1 <= 0;
          soft_reset_1 <= 0;
        end
      else if (read_enb_1)
        begin
          counter_1 <= 0;
          soft_reset_1 <= 0;
        end
      else
        begin
          if(counter_1 == 29)
            begin
              soft_reset_1 <= 1;
              counter_1 <= 0;
            end
          else
            begin
              counter_1 <= counter_1+1;
              soft_reset_1 <= 0;
            end
        end
    end

  always@(posedge clock)
    begin
      if(~resetn)
        begin
          counter_2 <= 0;
          soft_reset_2 <= 0;
        end
      else if (~vld_out_2)
        begin
          counter_2 <= 0;
          soft_reset_2 <= 0;
        end
      else if (read_enb_2)
        begin
          counter_2 <= 0;
          soft_reset_2 <= 0;
        end
      else
        begin
          if(counter_2 == 29)
            begin
              soft_reset_2 <= 1;
              counter_2 <= 0;
            end
          else
            begin
              counter_2 <= counter_2+1;
              soft_reset_2 <= 0;
            end
        end
    end

  always_comb
    case(addr)
        2'b00 : fifo_full = full_0;
        2'b01 : fifo_full = full_1;
        2'b10 : fifo_full = full_2;
        default : fifo_full = 0;
    endcase

  always_comb
    begin
      if(write_enb_reg)
        begin
          case(addr)
            2'b00 : write_enb = 3'b001;
            2'b01 : write_enb = 3'b010;
            2'b10 : write_enb = 3'b100;
            default : write_enb = 3'b000;
          endcase
        end
      else
        write_enb = 3'b000;
    end

endmodule


// ---------------------------------------------------------------------
// router_fsm
// ---------------------------------------------------------------------
module router_fsm (
    input  logic       clock,
    input  logic       resetn,
    input  logic       pkt_valid,
    input  logic       parity_done,
    input  logic [1:0] data_in,

    input  logic       soft_reset_0,
    input  logic       soft_reset_1,
    input  logic       soft_reset_2,

    input  logic       fifo_full,
    input  logic       low_pkt_valid,

    input  logic       fifo_empty_0,
    input  logic       fifo_empty_1,
    input  logic       fifo_empty_2,

    output logic       detect_add,
    output logic       ld_state,
    output logic       laf_state,
    output logic       full_state,
    output logic       write_enb_reg,
    output logic       lfd_state,
    output logic       rst_int_reg,
    output logic       busy
);

    typedef enum logic [2:0] {
        DECODE_ADDRESS,
        WAIT_TILL_EMPTY,
        LOAD_FIRST_DATA,
        LOAD_DATA,
        FIFO_FULL_STATE,
        LOAD_AFTER_FULL,
        LOAD_PARITY,
        CHECK_PARITY_ERROR
    } state_t;

    state_t current_state, next_state;

    logic [1:0] data_in_temp;
    logic       full_d;

    // Capture the destination address
    always_ff @(posedge clock) begin
        if (!resetn)
            data_in_temp <= 2'b00;
        else if (detect_add)
            data_in_temp <= data_in;
    end

    // Register the FIFO full status (value seen during the previous cycle)
    always_ff @(posedge clock) begin
        if (!resetn)
            full_d <= 1'b0;
        else
            full_d <= fifo_full;
    end

    // State register
    always_ff @(posedge clock) begin
        if (!resetn ||
            (data_in_temp == 2'd0 && soft_reset_0) ||
            (data_in_temp == 2'd1 && soft_reset_1) ||
            (data_in_temp == 2'd2 && soft_reset_2)) begin
            current_state <= DECODE_ADDRESS;
        end
        else begin
            current_state <= next_state;
        end
    end

    // Next-state logic
    always_comb begin
        next_state = current_state;

        case (current_state)

            DECODE_ADDRESS: begin
                if (pkt_valid && data_in == 2'd0 && fifo_empty_0)
                    next_state = LOAD_FIRST_DATA;
                else if (pkt_valid && data_in == 2'd1 && fifo_empty_1)
                    next_state = LOAD_FIRST_DATA;
                else if (pkt_valid && data_in == 2'd2 && fifo_empty_2)
                    next_state = LOAD_FIRST_DATA;
                else if (pkt_valid && data_in == 2'd0 && !fifo_empty_0)
                    next_state = WAIT_TILL_EMPTY;
                else if (pkt_valid && data_in == 2'd1 && !fifo_empty_1)
                    next_state = WAIT_TILL_EMPTY;
                else if (pkt_valid && data_in == 2'd2 && !fifo_empty_2)
                    next_state = WAIT_TILL_EMPTY;
                else
                    next_state = DECODE_ADDRESS;
            end

            WAIT_TILL_EMPTY: begin
                if ((data_in_temp == 2'd0 && fifo_empty_0) ||
                    (data_in_temp == 2'd1 && fifo_empty_1) ||
                    (data_in_temp == 2'd2 && fifo_empty_2))
                    next_state = LOAD_FIRST_DATA;
                else
                    next_state = WAIT_TILL_EMPTY;
            end

            LOAD_FIRST_DATA: begin
                next_state = LOAD_DATA;
            end

            LOAD_DATA: begin
                if (!fifo_full && !pkt_valid)
                    next_state = LOAD_PARITY;
                else if (fifo_full)
                    next_state = FIFO_FULL_STATE;
                else
                    next_state = LOAD_DATA;
            end

            LOAD_PARITY: begin
                next_state = CHECK_PARITY_ERROR;
            end

            // FIX: retry only if the parity write was rejected (FIFO full during LOAD_PARITY)
            CHECK_PARITY_ERROR: begin
                if (full_d)
                    next_state = FIFO_FULL_STATE;
                else
                    next_state = DECODE_ADDRESS;
            end

            FIFO_FULL_STATE: begin
                if (fifo_full)
                    next_state = FIFO_FULL_STATE;
                else
                    next_state = LOAD_AFTER_FULL;
            end

            LOAD_AFTER_FULL: begin
                if (parity_done)
                    next_state = DECODE_ADDRESS;
                else if (low_pkt_valid)
                    next_state = LOAD_PARITY;
                else
                    next_state = LOAD_DATA;
            end

        endcase
    end

    // Output logic
    always_comb begin
        detect_add    = 1'b0;
        ld_state      = 1'b0;
        laf_state     = 1'b0;
        full_state    = 1'b0;
        write_enb_reg = 1'b0;
        lfd_state     = 1'b0;
        rst_int_reg   = 1'b0;
        busy          = 1'b0;

        case (current_state)

            DECODE_ADDRESS: begin
                detect_add = 1'b1;
            end

            WAIT_TILL_EMPTY: begin
                busy = 1'b1;
            end

            LOAD_FIRST_DATA: begin
                lfd_state = 1'b1;
                busy      = 1'b1;
            end

            LOAD_DATA: begin
                ld_state      = 1'b1;
                write_enb_reg = 1'b1;
            end

            LOAD_PARITY: begin
                busy          = 1'b1;
                write_enb_reg = 1'b1;
            end

            CHECK_PARITY_ERROR: begin
                busy        = 1'b1;
                rst_int_reg = 1'b1;
            end

            FIFO_FULL_STATE: begin
                busy       = 1'b1;
                full_state = 1'b1;
            end

            LOAD_AFTER_FULL: begin
                laf_state     = 1'b1;
                busy          = 1'b1;
                write_enb_reg = 1'b1;
            end

        endcase
    end

endmodule


// ---------------------------------------------------------------------
// router_register
// ---------------------------------------------------------------------
module router_register (
    input         clock,
    input         resetn,
    input         pkt_valid,
    input  [7:0]  data_in,
    input         fifo_full,
    input         rst_int_reg,
    input         detect_add,
    input         ld_state,
    input         laf_state,
    input         full_state,
    input         lfd_state,

    output logic        parity_done,
    output logic        low_pkt_valid,
    output logic [7:0]  dout,
    output logic        err
);

    // Internal registers
    logic [7:0] first_byte;
    logic [7:0] full_state_byte;
    logic [7:0] internal_parity;
    logic [7:0] pkt_parity;

    // 1. PARITY DONE LOGIC
    always_ff @(posedge clock) begin
        if (!resetn)
            parity_done <= 1'b0;

        else if ((ld_state && !fifo_full && !pkt_valid) ||
                 (laf_state && !parity_done && low_pkt_valid))
            parity_done <= 1'b1;

        else if (detect_add)
            parity_done <= 1'b0;
    end

    // 2. LOW PACKET VALID LOGIC
    always_ff @(posedge clock) begin
        if (!resetn)
            low_pkt_valid <= 1'b0;

        else if (ld_state && !pkt_valid)
            low_pkt_valid <= 1'b1;

        else if (rst_int_reg)
            low_pkt_valid <= 1'b0;
    end

    // 3. REGISTER DATA OUTPUT LOGIC
    always_ff @(posedge clock) begin
        if (!resetn) begin
            dout            <= 8'h00;
            first_byte      <= 8'h00;
            full_state_byte <= 8'h00;
        end
        else begin

            // Capture the header byte
            if (detect_add && pkt_valid &&
                (data_in[1:0] != 2'b11))
                first_byte <= data_in;

            // Output the stored header byte
            else if (lfd_state)
                dout <= first_byte;

            // Capture payload data when FIFO is not full
            else if (ld_state && !fifo_full)
                dout <= data_in;

            // Save the data when FIFO is full
            else if (ld_state && fifo_full)
                full_state_byte <= data_in;

            // Output the saved data after FIFO becomes available
            else if (laf_state)
                dout <= full_state_byte;
        end
    end

    // 4. INTERNAL PARITY CALCULATION
    always_ff @(posedge clock) begin
        if (!resetn)
            internal_parity <= 8'h00;

        else begin
            if (detect_add)
                internal_parity <= 8'h00;

            // Include the header byte in the parity calculation
            else if (lfd_state)
                internal_parity <= internal_parity ^ first_byte;

            // Include each payload byte
            else if (ld_state && !full_state && pkt_valid)
                internal_parity <= internal_parity ^ data_in;
        end
    end

    // 5. PACKET PARITY BYTE CAPTURE
    always_ff @(posedge clock) begin
        if (!resetn)
            pkt_parity <= 8'h00;

        else if (detect_add)
            pkt_parity <= 8'h00;

        else if ((ld_state && !pkt_valid && !fifo_full) ||
                 (laf_state && low_pkt_valid && !parity_done))
            pkt_parity <= data_in;
    end

    // 6. ERROR DETECTION LOGIC
    always_ff @(posedge clock) begin
        if (!resetn)
            err <= 1'b0;

        else if (!parity_done)
            err <= 1'b0;

        else if (pkt_parity != internal_parity)
            err <= 1'b1;

        else
            err <= 1'b0;
    end

endmodule


// ---------------------------------------------------------------------
// router_top
// ---------------------------------------------------------------------
module router_top (
    input         clock,
    input         resetn,
    input         pkt_valid,
    input  [7:0]  data_in,

    input         read_enb_0,
    input         read_enb_1,
    input         read_enb_2,

    output [7:0]  data_out_0,
    output [7:0]  data_out_1,
    output [7:0]  data_out_2,

    output        vld_out_0,
    output        vld_out_1,
    output        vld_out_2,

    output        busy,
    output        error
);

    // Internal wires
    wire [2:0] write_enb;
    wire [7:0] dout;

    wire empty_0, empty_1, empty_2;
    wire full_0,  full_1,  full_2;
    wire fifo_full;

    wire detect_add;
    wire ld_state;
    wire laf_state;
    wire full_state;
    wire lfd_state;

    wire write_enb_reg;
    wire rst_int_reg;
    wire parity_done;
    wire low_pkt_valid;

    wire soft_reset_0;
    wire soft_reset_1;
    wire soft_reset_2;

    // FIFO 0
    router_fifo FIFO_0 (
        .clock      (clock),
        .resetn     (resetn),
        .soft_reset (soft_reset_0),
        .write_enb  (write_enb[0]),
        .read_enb   (read_enb_0),
        .data_in    (dout),
        .data_out   (data_out_0),
        .empty      (empty_0),
        .full       (full_0),
        .lfd_state  (lfd_state)
    );

    // FIFO 1
    router_fifo FIFO_1 (
        .clock      (clock),
        .resetn     (resetn),
        .soft_reset (soft_reset_1),
        .write_enb  (write_enb[1]),
        .read_enb   (read_enb_1),
        .data_in    (dout),
        .data_out   (data_out_1),
        .empty      (empty_1),
        .full       (full_1),
        .lfd_state  (lfd_state)
    );

    // FIFO 2
    router_fifo FIFO_2 (
        .clock      (clock),
        .resetn     (resetn),
        .soft_reset (soft_reset_2),
        .write_enb  (write_enb[2]),
        .read_enb   (read_enb_2),
        .data_in    (dout),
        .data_out   (data_out_2),
        .empty      (empty_2),
        .full       (full_2),
        .lfd_state  (lfd_state)
    );

    // Router FSM
    router_fsm FSM (
        .clock         (clock),
        .resetn        (resetn),
        .pkt_valid     (pkt_valid),
        .data_in       (data_in[1:0]),

        .parity_done   (parity_done),
        .low_pkt_valid (low_pkt_valid),

        .soft_reset_0  (soft_reset_0),
        .soft_reset_1  (soft_reset_1),
        .soft_reset_2  (soft_reset_2),

        .fifo_full     (fifo_full),
        .fifo_empty_0  (empty_0),
        .fifo_empty_1  (empty_1),
        .fifo_empty_2  (empty_2),

        .detect_add    (detect_add),
        .ld_state      (ld_state),
        .laf_state     (laf_state),
        .full_state    (full_state),
        .write_enb_reg (write_enb_reg),
        .lfd_state     (lfd_state),
        .rst_int_reg   (rst_int_reg),
        .busy          (busy)
    );

    // Router Synchronizer
    router_synchronizer SYNC (
        .clock         (clock),
        .resetn        (resetn),

        .detect_add    (detect_add),
        .data_in       (data_in[1:0]),
        .write_enb_reg (write_enb_reg),

        .read_enb_0    (read_enb_0),
        .read_enb_1    (read_enb_1),
        .read_enb_2    (read_enb_2),

        .empty_0       (empty_0),
        .empty_1       (empty_1),
        .empty_2       (empty_2),

        .full_0        (full_0),
        .full_1        (full_1),
        .full_2        (full_2),

        .vld_out_0     (vld_out_0),
        .vld_out_1     (vld_out_1),
        .vld_out_2     (vld_out_2),

        .soft_reset_0  (soft_reset_0),
        .soft_reset_1  (soft_reset_1),
        .soft_reset_2  (soft_reset_2),

        .fifo_full     (fifo_full),
        .write_enb     (write_enb)
    );

    // Router Register
    router_register REG (
        .clock         (clock),
        .resetn        (resetn),

        .pkt_valid     (pkt_valid),
        .data_in       (data_in),

        .fifo_full     (fifo_full),
        .rst_int_reg   (rst_int_reg),
        .detect_add    (detect_add),
        .ld_state      (ld_state),
        .laf_state     (laf_state),
        .full_state    (full_state),
        .lfd_state     (lfd_state),

        .parity_done   (parity_done),
        .low_pkt_valid (low_pkt_valid),
        .dout          (dout),
        .err           (error)
    );

endmodule
