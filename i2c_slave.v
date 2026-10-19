`timescale 1ns / 1ps

module i2c_slave (
    input  wire        clk,
    input  wire        reset,
    inout  wire        sda,
    inout  wire        scl,
    input  wire [6:0]  slave_addr,
    output reg  [7:0]  rx_data,
    output reg         rx_data_valid,
    input  wire [7:0]  tx_data,
    input  wire        tx_data_valid,
    output reg         tx_data_req,
    output reg         busy,
    output reg         addr_match
);

localparam  S_IDLE    = 4'd0,
            S_ADDR    = 4'd1,
            S_RW      = 4'd2,
            S_ACK     = 4'd3,
            S_RX_DATA = 4'd4,
            S_RX_ACK  = 4'd5,
            S_TX_DATA = 4'd6,
            S_TX_ACK  = 4'd7,
            S_TX_WAIT  = 4'd8;
localparam READ  = 1'b1,
           WRITE = 1'b0;

// SDA
reg sda_oe; // SDA Output Enable
assign sda = sda_oe ? 1'b0 : 1'bz;

//SCL
reg scl_oe; // SCL Output Enable
assign scl = scl_oe ? 1'b0 : 1'bz; // scl_oe 為 1 時強行拉低 SCL
reg [7:0] stretch_cnt; 
reg scl_r0, scl_r1, scl_r2;
reg sda_r0, sda_r1, sda_r2;
reg sda_oe_r1, sda_oe_r2;
reg [7:0] tx_data_reg;

reg [3:0] state;
reg [2:0] bit_cnt;
reg [7:0] shift_reg;
reg       rw_bit;
reg       ack_phase;  // 區分 ACK 的兩個下降沿
// 邊緣偵測
wire scl_rise =  scl_r1 & ~scl_r2; 
wire scl_fall = ~scl_r1 &  scl_r2; 
wire sda_rise =  sda_r1 & ~sda_r2;  
wire sda_fall = ~sda_r1 &  sda_r2;  

// START / STOP 偵測
wire start_cond = sda_fall & scl_r1 & scl_r2 & (~sda_oe_r2); 
wire stop_cond  = sda_rise & scl_r1 & scl_r2;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        scl_r0<=1; scl_r1<=1; scl_r2<=1;
        sda_r0<=1; sda_r1<=1; sda_r2<=1;
        sda_oe_r1 <= 1'b0;
        sda_oe_r2 <= 1'b0;
    end else begin
        scl_r0 <= scl;    // 第一級（可能 metastable）
        scl_r1 <= scl_r0; // 第二級（穩定）
        scl_r2 <= scl_r1; // 第三級（用於邊緣偵測）

        sda_r0 <= sda;
        sda_r1 <= sda_r0;
        sda_r2 <= sda_r1;
        sda_oe_r1 <= sda_oe;
        sda_oe_r2 <= sda_oe_r1;
    end
end

// FSM
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state         <= S_IDLE;
        sda_oe        <= 1'b0;
        scl_oe        <= 1'b0;
        bit_cnt       <= 3'd6;
        shift_reg     <= 8'h00;
        rw_bit        <= 1'b0;
        rx_data       <= 8'h00;
        rx_data_valid <= 1'b0;
        tx_data_req   <= 1'b0;
        busy          <= 1'b0;
        addr_match    <= 1'b0;
        ack_phase     <= 1'b0;
        stretch_cnt   <= 8'b0;
    end else begin
        rx_data_valid <= 1'b0;

        // start_condition
        if (start_cond) begin
            state      <= S_ADDR;
            bit_cnt    <= 3'd6;
            sda_oe     <= 1'b0;
            busy       <= 1'b1;
            addr_match <= 1'b0;
            ack_phase  <= 1'b0;
            $display("[%0t] SLAVE: START detected", $time);
        end

        // stop_condition
        else if (stop_cond) begin
            state      <= S_IDLE;
            sda_oe     <= 1'b0;
            busy       <= 1'b0;
            addr_match <= 1'b0;
            $display("[%0t] SLAVE: STOP detected", $time);
        end

        else begin
            case (state)

                S_IDLE: begin
                    sda_oe <= 1'b0;
                    busy   <= 1'b0;
                end

                // addr bit
                S_ADDR: begin
                    if (scl_rise) begin
                        shift_reg[bit_cnt] <= sda_r1;
                        $display("[%0t] SLAVE: ADDR bit[%0d]=%b",
                                  $time, bit_cnt, sda_r1);
                        if (bit_cnt == 3'd0)
                            state <= S_RW;
                        else
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                // RW bit, addr_match
                S_RW: begin
                    if (scl_rise) begin
                        rw_bit <= sda_r1;
                        $display("[%0t] SLAVE: RW=%b, addr_rcv=0x%02h, slave_addr=0x%02h",
                                  $time, sda_r1, shift_reg[6:0], slave_addr);

                        if (shift_reg[6:0] == slave_addr) begin
                            addr_match <= 1'b1;
                            state      <= S_ACK;
                            ack_phase  <= 1'b0;
                            $display("[%0t] SLAVE: Address MATCH!", $time);
                        end else begin
                            addr_match <= 1'b0;
                            state      <= S_IDLE;
                            busy       <= 1'b0;
                            $display("[%0t] SLAVE: Address MISMATCH", $time);
                        end
                    end
                end

                // ACK 狀態：使用 ack_phase 分兩段處理
                //   phase=0：SCL 下降沿 → 拉低 SDA
                //   phase=1：SCL 下降沿 → 釋放 SDA，跳下一狀態



                S_ACK: begin                  // 這邊可跟master的ACK_ADDR一起看
                    // master那邊scl_out <= 0
                    // slave這邊就會先
                    // scl_r0 <= 0    ，    scl_r1 <= scl_r0    ，    scl_r2 <= scl_r1
                    //                      (兩者皆舊值，所以是1，不要忘記non-block)
                    // 再來下一拍
                    // scl_r0 <= 0    ，    scl_r1 <= scl_r0    ，    scl_r2 <= scl_r1
                    //                      (新值=0)                 (舊值=1)
                    // 符合wire scl_fall = ~scl_r1 & scl_r2;
                    // 這樣就會進入這個if
                    if (scl_fall) begin         
                        if (ack_phase == 1'b0) begin
                            sda_oe    <= 1'b1;
                            // 回去看master的ACK_ADDR
                            // master的sda_oe <= 0，放手
                            // slave的sda_oe <= 1，拉低
                            // 所以這part是slave控制sda總線
                            // !!如果slave的sda_oe這邊沒有變0，也就是說沒有拉低的話
                            // master就會收到NACK，ack_fail=1
                            ack_phase <= 1'b1;
                            $display("[%0t] SLAVE: ACK pulling SDA low", $time);
                        end else begin
                            ack_phase <= 1'b0;
                            if (rw_bit == WRITE) begin
                                sda_oe  <= 1'b0;  // Slave 釋放 SDA/
                                scl_oe  <= 1'b0;
                                state   <= S_RX_DATA;
                                bit_cnt <= 3'd7;
                                $display("[%0t] SLAVE: → RX_DATA", $time);
                            end else begin
                                tx_data_req <= 1'b1;// 要求上層提供第一個 TX byte
                                scl_oe <= 1'b1;
                                sda_oe <= 1'b0;
                                state  <= S_TX_WAIT;
                                $display("[%0t] SLAVE: -> TX_WAIT, stretching SCL",$time);
                            end
                        end
                    end
                end
                S_TX_WAIT: begin
                // tx_data_req 保持為 1，直到上層回覆 tx_data_valid
                    tx_data_req <= 1'b1;
                    scl_oe <= 1'b1;
                    if (tx_data_valid) begin
                        tx_data_reg  <= tx_data;
                        $display("[%0t] SLAVE: TX ready: data=%02h, SDA=%b, SCL=%b, sda_oe=%b, scl_oe=%b",$time, tx_data, sda, scl, sda_oe, scl_oe);

                        // 第一個 bit 必須在釋放 SCL 前準備好
                        sda_oe <= ~tx_data[7];
                        tx_data_req  <= 1'b0;
                        // 資料準備好後才釋放 SCL
                        scl_oe <= 1'b0;

                        state        <= S_TX_DATA;
                        bit_cnt      <= 3'd6;
                        $display("[%0t] SLAVE: TX data ready = 0x%02h, bit[7]=%b",$time, tx_data, tx_data[7]);
                    end
                end

                // 接收 Master 寫入資料
                S_RX_DATA: begin
                    if (scl_rise) begin
                        shift_reg[bit_cnt] <= sda_r1;
                        if (bit_cnt == 3'd0) begin
                            rx_data       <= {shift_reg[7:1], sda_r1};
                            rx_data_valid <= 1'b1;
                            state         <= S_RX_ACK;
                            ack_phase     <= 1'b0;
                            $display("[%0t] SLAVE: RX byte=0x%02h",
                                      $time, {shift_reg[7:1], sda_r1});
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end

                // 回覆 Data ACK
                S_RX_ACK: begin
                    if (scl_fall) begin
                        if (ack_phase == 1'b0) begin
                            sda_oe      <= 1'b1;   // 拉低 SDA (回覆 ACK)
                            scl_oe      <= 1'b1;   // 強行拉低 SCL，開始 Clock Stretching
                            stretch_cnt <= 8'd100; 
                            ack_phase   <= 1'b1;
                            $display("[%0t] SLAVE: Start Clock Stretching!", $time);
                        end else begin
                            sda_oe    <= 1'b0;   
                            ack_phase <= 1'b0;
                            bit_cnt   <= 3'd7;
                            state     <= S_RX_DATA;
                        end
                    end 
                    
                    if (ack_phase == 1'b1 && scl_oe == 1'b1) begin
                        if (stretch_cnt > 0) begin
                            stretch_cnt <= stretch_cnt - 1'b1;
                        end else begin
                            scl_oe <= 1'b0; // 釋放 SCL
                            $display("[%0t] SLAVE: End Clock Stretching!", $time);
                        end
                    end
                end
                // 發送資料給 Master
                S_TX_DATA: begin
                    scl_oe <= 1'b0;
                    if (scl_fall) begin
                        
                        // 根據 tx_data[bit] 決定是否拉低
                        sda_oe <= ~tx_data_reg[bit_cnt];
                        $display("[%0t] SLAVE: TX bit[%0d]=%b",$time, bit_cnt, tx_data_reg[bit_cnt]);
                        if (bit_cnt == 3'd0) begin
                            state <= S_TX_ACK;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end

                // 等待 Master ACK/NACK
                S_TX_ACK: begin
                    scl_oe <= 1'b0;
                    sda_oe <= 1'b0;   // 釋放 SDA 讓 Master 驅動
                    if (scl_rise) begin
                        if (sda_r1 == 1'b0) begin//ACK
                            tx_data_req <= 1'b1;
                            state       <= S_TX_WAIT;
                            $display("[%0t] SLAVE: Master ACK, continue TX", $time);
                        end else begin//NACK
                            tx_data_req <= 1'b0;
                            state <= S_IDLE;
                            busy  <= 1'b0;
                            $display("[%0t] SLAVE: Master NACK, stop TX", $time);
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
end
endmodule
