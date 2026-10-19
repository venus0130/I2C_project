`timescale 1ns / 1ps

module i2c_system_top #(
    parameter SLAVE_ADDR = 7'h3C
)(
    input  wire        clk,
    input  wire        reset,

    // Master 0 控制介面
    input  wire        start_0,
    input  wire [3:0]  nbytes_0,
    input  wire [6:0]  addr_0,
    input  wire        rw_0,
    input  wire [63:0] write_data_0,

    output wire [63:0] read_data_0,
    output wire        busy_0,
    output wire        done_0,
    output wire        ack_fail_0,
    output wire        arb_lost_0,

    // Master 1 控制介面
    input  wire        start_1,
    input  wire [3:0]  nbytes_1,
    input  wire [6:0]  addr_1,
    input  wire        rw_1,
    input  wire [63:0] write_data_1,

    output wire [63:0] read_data_1,
    output wire        busy_1,
    output wire        done_1,
    output wire        ack_fail_1,
    output wire        arb_lost_1,

    // Slave 狀態輸出
    output wire [7:0]  slave_rx_data,
    output wire        slave_rx_valid,
    output wire        slave_busy,
    output wire        slave_addr_match,

    // I²C bus
    inout  wire        sda,
    inout  wire        scl
);

    // Slave TX interface
    wire [7:0] slave_tx_data;
    wire       slave_tx_req;
    reg        slave_tx_valid;

    reg [7:0] slave_tx_data_reg;
    reg       tx_req_seen;

    assign slave_tx_data = slave_tx_data_reg;

    // Master 0
    i2c_master #(
        .SYS_CLK_FREQ (50_000_000),
        .I2C_CLK_FREQ (400_000)
    ) u_master_0 (
        .clk        (clk),
        .rst        (reset),

        .start_req  (start_0),
        .dev_addr   (addr_0),
        .rw         (rw_0),
        .n_bytes    (nbytes_0),
        .write_data (write_data_0),

        .read_data  (read_data_0),
        .busy       (busy_0),
        .done       (done_0),
        .ack_fail   (ack_fail_0),
        .arb_lost   (arb_lost_0),

        .sda_w      (sda),
        .scl        (scl)
    );

    // Master 1
    i2c_master #(
        .SYS_CLK_FREQ (50_000_000),
        .I2C_CLK_FREQ (400_000)
    ) u_master_1 (
        .clk        (clk),
        .rst        (reset),

        .start_req  (start_1),
        .dev_addr   (addr_1),
        .rw         (rw_1),
        .n_bytes    (nbytes_1),
        .write_data (write_data_1),

        .read_data  (read_data_1),
        .busy       (busy_1),
        .done        (done_1),
        .ack_fail   (ack_fail_1),
        .arb_lost   (arb_lost_1),

        .sda_w      (sda),
        .scl        (scl)
    );

    // Slave
    i2c_slave u_slave (
        .clk           (clk),
        .reset         (reset),

        .sda           (sda),
        .scl           (scl),

        .slave_addr    (SLAVE_ADDR),

        .rx_data       (slave_rx_data),
        .rx_data_valid (slave_rx_valid),

        .tx_data       (slave_tx_data),
        .tx_data_req   (slave_tx_req),
        .tx_data_valid (slave_tx_valid),

        .busy          (slave_busy),
        .addr_match    (slave_addr_match)
    );

    // Slave TX 上層控制器
    // 這裡先模擬實際上層邏輯：Slave 要資料時，回傳 8'hA5。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            slave_tx_data_reg <= 8'h00;
            slave_tx_valid    <= 1'b0;
            tx_req_seen       <= 1'b0;
        end
        else begin
            slave_tx_valid <= 1'b0;

            // request 結束後，允許下一次 request
            if (!slave_tx_req) begin
                tx_req_seen <= 1'b0;
            end
            else if (slave_tx_req && !tx_req_seen) begin
                slave_tx_data_reg <= 8'hA5;
                slave_tx_valid    <= 1'b1;
                tx_req_seen       <= 1'b1;
            end
        end
    end
endmodule
