`timescale 1ns/1ps

module router_1x3 #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ================================================================
    // INPUT INTERFACE
    // ================================================================

    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                  pkt_valid,

    output logic                  busy,

    // ================================================================
    // OUTPUT 0
    // ================================================================

    output logic [DATA_WIDTH-1:0] data_out0,
    output logic                  valid_out0,
    input  logic                  read_en0,

    // ================================================================
    // OUTPUT 1
    // ================================================================

    output logic [DATA_WIDTH-1:0] data_out1,
    output logic                  valid_out1,
    input  logic                  read_en1,

    // ================================================================
    // OUTPUT 2
    // ================================================================

    output logic [DATA_WIDTH-1:0] data_out2,
    output logic                  valid_out2,
    input  logic                  read_en2,

    // ================================================================
    // ERROR
    // ================================================================

    output logic                  parity_error
);


    // =================================================================
    // Internal FIFO storage
    // =================================================================

    logic [DATA_WIDTH-1:0] fifo0 [0:FIFO_DEPTH-1];
    logic [DATA_WIDTH-1:0] fifo1 [0:FIFO_DEPTH-1];
    logic [DATA_WIDTH-1:0] fifo2 [0:FIFO_DEPTH-1];


    logic [$clog2(FIFO_DEPTH)-1:0] wr_ptr0;
    logic [$clog2(FIFO_DEPTH)-1:0] rd_ptr0;

    logic [$clog2(FIFO_DEPTH)-1:0] wr_ptr1;
    logic [$clog2(FIFO_DEPTH)-1:0] rd_ptr1;

    logic [$clog2(FIFO_DEPTH)-1:0] wr_ptr2;
    logic [$clog2(FIFO_DEPTH)-1:0] rd_ptr2;


    logic [$clog2(FIFO_DEPTH+1)-1:0] count0;
    logic [$clog2(FIFO_DEPTH+1)-1:0] count1;
    logic [$clog2(FIFO_DEPTH+1)-1:0] count2;


    // =================================================================
    // Packet state
    // =================================================================

    typedef enum logic [2:0] {

        IDLE,
        HEADER,
        PAYLOAD,
        PARITY

    } state_t;

    state_t state;


    logic [1:0] destination;

    logic [5:0] payload_length;

    logic [5:0] payload_count;

    logic parity_calc;


    // =================================================================
    // FIFO full signals
    // =================================================================

    logic full0;
    logic full1;
    logic full2;


    assign full0 = (count0 == FIFO_DEPTH);
    assign full1 = (count1 == FIFO_DEPTH);
    assign full2 = (count2 == FIFO_DEPTH);


    // =================================================================
    // BUSY
    // =================================================================

    always_comb begin

        case (destination)

            2'b00:
                busy = full0;

            2'b01:
                busy = full1;

            2'b10:
                busy = full2;

            default:
                busy = 1'b1;

        endcase

    end


    // =================================================================
    // OUTPUT VALID
    // =================================================================

    assign valid_out0 = (count0 != 0);
    assign valid_out1 = (count1 != 0);
    assign valid_out2 = (count2 != 0);


    // =================================================================
    // OUTPUT DATA
    // =================================================================

    always_comb begin

        if (count0 != 0)
            data_out0 = fifo0[rd_ptr0];
        else
            data_out0 = '0;


        if (count1 != 0)
            data_out1 = fifo1[rd_ptr1];
        else
            data_out1 = '0;


        if (count2 != 0)
            data_out2 = fifo2[rd_ptr2];
        else
            data_out2 = '0;

    end


    // =================================================================
    // MAIN ROUTER FSM
    // =================================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state          <= IDLE;

            destination    <= 2'b00;
            payload_length <= 6'd0;
            payload_count  <= 6'd0;

            parity_calc    <= 1'b0;

            parity_error   <= 1'b0;


            wr_ptr0 <= '0;
            wr_ptr1 <= '0;
            wr_ptr2 <= '0;


            rd_ptr0 <= '0;
            rd_ptr1 <= '0;
            rd_ptr2 <= '0;


            count0 <= '0;
            count1 <= '0;
            count2 <= '0;

        end

        else begin

            // ---------------------------------------------------------
            // Clear parity error after one cycle
            // ---------------------------------------------------------

            parity_error <= 1'b0;


            // ---------------------------------------------------------
            // Read enable handling
            // ---------------------------------------------------------

            if (read_en0 && count0 != 0) begin

                rd_ptr0 <= rd_ptr0 + 1'b1;
                count0  <= count0 - 1'b1;

            end


            if (read_en1 && count1 != 0) begin

                rd_ptr1 <= rd_ptr1 + 1'b1;
                count1  <= count1 - 1'b1;

            end


            if (read_en2 && count2 != 0) begin

                rd_ptr2 <= rd_ptr2 + 1'b1;
                count2  <= count2 - 1'b1;

            end


            // ---------------------------------------------------------
            // FSM
            // ---------------------------------------------------------

            case (state)

                // =====================================================
                // IDLE
                // =====================================================

                IDLE: begin

                    if (pkt_valid) begin

                        state <= HEADER;

                    end

                end


                // =====================================================
                // HEADER
                // =====================================================

                HEADER: begin

                    destination    <= data_in[7:6];
                    payload_length <= data_in[5:0];

                    payload_count <= 0;

                    parity_calc <= ^data_in;

                    state <= PAYLOAD;

                end


                // =====================================================
                // PAYLOAD
                // =====================================================

                PAYLOAD: begin

                    if (pkt_valid) begin

                        case (destination)

                            2'b00: begin

                                if (!full0) begin

                                    fifo0[wr_ptr0] <= data_in;

                                    wr_ptr0 <= wr_ptr0 + 1'b1;

                                    count0 <= count0 + 1'b1;

                                end

                            end


                            2'b01: begin

                                if (!full1) begin

                                    fifo1[wr_ptr1] <= data_in;

                                    wr_ptr1 <= wr_ptr1 + 1'b1;

                                    count1 <= count1 + 1'b1;

                                end

                            end


                            2'b10: begin

                                if (!full2) begin

                                    fifo2[wr_ptr2] <= data_in;

                                    wr_ptr2 <= wr_ptr2 + 1'b1;

                                    count2 <= count2 + 1'b1;

                                end

                            end


                            default: begin

                                // Invalid destination

                            end

                        endcase


                        parity_calc <= parity_calc ^ (^data_in);

                        payload_count <= payload_count + 1'b1;


                        if (payload_count + 1 >= payload_length)
                            state <= PARITY;

                    end

                end


                // =====================================================
                // PARITY
                // =====================================================

                PARITY: begin

                    if (pkt_valid) begin

                        if (parity_calc != (^data_in))
                            parity_error <= 1'b1;

                        state <= IDLE;

                    end

                end


                default:
                    state <= IDLE;

            endcase

        end

    end


    // =================================================================
    // SVA
    // =================================================================

    // ---------------------------------------------------------------
    // Output data must remain stable while valid and read is low.
    // ---------------------------------------------------------------

    property p_data_stable0;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out0 && !read_en0
        |=> valid_out0 && $stable(data_out0);

    endproperty

    assert property(p_data_stable0)
        else $error("Router OUT0 data changed while waiting for read");


    property p_data_stable1;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out1 && !read_en1
        |=> valid_out1 && $stable(data_out1);

    endproperty

    assert property(p_data_stable1)
        else $error("Router OUT1 data changed while waiting for read");


    property p_data_stable2;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out2 && !read_en2
        |=> valid_out2 && $stable(data_out2);

    endproperty

    assert property(p_data_stable2)
        else $error("Router OUT2 data changed while waiting for read");


    // ---------------------------------------------------------------
    // Invalid destination should never generate valid output.
    // ---------------------------------------------------------------

    property p_valid_destination;

        @(posedge clk)
        disable iff (!rst_n)
        (destination == 2'b11)
        |-> !(valid_out0 || valid_out1 || valid_out2);

    endproperty


    // ---------------------------------------------------------------
    // Valid output implies data is available.
    // ---------------------------------------------------------------

    property p_valid0_has_data;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out0 |-> (count0 != 0);

    endproperty

    assert property(p_valid0_has_data);


    property p_valid1_has_data;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out1 |-> (count1 != 0);

    endproperty

    assert property(p_valid1_has_data);


    property p_valid2_has_data;

        @(posedge clk)
        disable iff (!rst_n)
        valid_out2 |-> (count2 != 0);

    endproperty

    assert property(p_valid2_has_data);


endmodule
