`timescale 1ns / 1ps

module i2c_master #(
    parameter SYS_CLK_FREQ = 50_000_000, 
    parameter I2C_CLK_FREQ = 5_000_000      
)(
    input  wire        clk,
    input  wire        rst,
    
    input  wire        start_req,
    input  wire [6:0]  dev_addr,
    input  wire        rw,          
    input  wire [3:0]  n_bytes,   //要連續傳送/讀取的 byte 數  
    input  wire [63:0] write_data,  
    output reg  [63:0] read_data,   
    output reg         busy,
    output reg         done,
    output reg         ack_fail,    
    output reg         arb_lost,      // 仲裁旗標
    inout  wire        sda_w,
    inout  wire        scl        
);

    reg [15:0] div_cnt;
    reg        tick;
    reg        scl_has_risen; 
    reg scl_out, sda_out, sda_oe; // out是欲輸出的值，oe是控制權
    reg [3:0]  state;
    reg [1:0]  phase;
    reg [2:0]  bit_cnt;
    reg [3:0]  byte_cnt;      //紀錄還剩幾個 byte 要傳
    reg [63:0] tx_data_reg;   //暫存要發出去的 64-bit 資料
    reg [7:0]  shift_reg;
    reg scl_r1, scl_r2;
    reg sda_r1, sda_r2;
    reg bus_busy;
    reg rw_reg;

    localparam IDLE      = 4'd0;
    localparam START     = 4'd1;
    localparam TX_ADDR   = 4'd2;
    localparam ACK_ADDR  = 4'd3;
    localparam TX_DATA   = 4'd4;
    localparam ACK_TX    = 4'd5;
    localparam RX_DATA   = 4'd6;
    localparam ACK_RX    = 4'd7;
    localparam STOP      = 4'd8;
    //無條件進位，公式為 (分子 + 分母 - 1) / 分母
    localparam DIV_MAX = (SYS_CLK_FREQ + (I2C_CLK_FREQ * 4) - 1) / (I2C_CLK_FREQ * 4);//確保頻率只會等於或低於目標值
        /*概念:
		假設SYS_CLK_FREQ 每秒跑5000萬步(50M)
    	I2C_CLK_FREQ 每秒跑500萬步(5M)
		DIV_MAX=5000/500/4=2.5，無條件進位=3
		表示SYS_CLK_FREQ每跑3步，tick就拍一次手
		意思是到某一階段(低電位、上升期、高電位、下降期)
		tick就會輸出1
		而拍4次手就表示SCL走完一個完整的波*/

    assign scl   = (scl_out == 1'b0) ? 1'b0 : 1'bz; 
    assign sda_w = (sda_oe && !sda_out) ? 1'b0 : 1'bz; 
	// 除了master有控制權且要輸出0時往下拉，其餘都放手

    always @(posedge clk) begin
        if (rst) begin
            scl_r1 <= 1'b1;
            scl_r2 <= 1'b1;
        end else begin
            scl_r1 <= scl;     
            scl_r2 <= scl_r1;
        end
    end
    
    wire scl_fall = (scl_r2 == 1'b1 && scl_r1 == 1'b0); // SCL下降緣偵測

    always @(posedge clk) begin
        if (rst) begin
            sda_r1 <= 1'b1;
            sda_r2 <= 1'b1;
        end else begin
            sda_r1 <= sda_w;
            sda_r2 <= sda_r1;
        end
    end

    // SDA 在 SCL 高電位時由 0 變 1 (only開始才這樣，觸發的概念)
    wire start_detect = (scl_r2 == 1'b1) &&(sda_r2 == 1'b1) &&(sda_r1 == 1'b0);
    // SDA 在 SCL 高電位時由 1 變 0
    wire stop_detect =(scl_r2 == 1'b1) && (sda_r2 == 1'b0) && (sda_r1 == 1'b1);
    wire bus_free =!bus_busy &&(sda_r2 == 1'b1) &&(scl_r2 == 1'b1);
    wire arb_lost_cond =tick &&(phase == 2'b10) &&((state == TX_ADDR) || (state == TX_DATA)) &&
    (sda_out == 1'b1) &&(sda_r2 == 1'b0);

    // Bus busy monitor
    always @(posedge clk) begin
        if (rst) begin
            bus_busy <= 1'b0;
        end
        else begin
            if (start_detect) begin
                bus_busy <= 1'b1;

                $display("[%0t] BUS BUSY: START detected", $time);
            end
            else if (stop_detect) begin
                bus_busy <= 1'b0;

                $display("[%0t] BUS FREE: STOP detected", $time);
            end
        end
    end



    // Clock Stretching 與 除頻
    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 0;
            tick    <= 0;
            scl_has_risen   <=0;
        end else if (busy) begin
            //Master 主動把 SCL 拉低
            if (scl_out == 1'b0) begin 
                scl_has_risen <= 1'b0; 
                
                if (div_cnt == DIV_MAX - 1) begin // 除頻
                    div_cnt <= 0;
                    tick    <= 1'b1;
                end else begin
                    div_cnt <= div_cnt + 1;
                    tick    <= 1'b0;
                end
            end 
            // Master 放開 SCL (scl_out == 1)
            else begin
                // SCL Low 同步 (等最慢的 / Clock Stretching)
                //另一個 Master 還在拉低匯流排，或是 Slave 主動拉低降速。
                if (scl_r2 == 1'b0) begin
                    scl_has_risen <= 1'b0;
                    div_cnt <= div_cnt; 
                    tick    <= 1'b0;
                end 
                
                // 實際 SCL 已經升高
                else begin
                    // 第一次確認 SCL 升高
                    if (!scl_has_risen) begin
                        scl_has_risen <= 1'b1;
                        div_cnt       <= 0;
                        tick          <= 1'b0;
                    end
                    // SCL 已處於高電位，且偵測到下降
                    else if (scl_fall) begin
                        scl_has_risen <= 1'b0; 
                        div_cnt <= 0;      
                        tick    <= 1'b1;    //讓 FSM 提早進入下一個階段
                    end
                    // SCL 高電位正常計時
                    else if (div_cnt == DIV_MAX - 1) begin
                        div_cnt <= 0;
                        tick    <= 1'b1;
                    end else begin
                        div_cnt <= div_cnt + 1;
                        tick    <= 1'b0;
                    end
                end
            end
        end else begin
            div_cnt <= 0;
            tick    <= 0;
            scl_has_risen <= 1'b0; 
        end
    end

    //FSM
    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            phase       <= 0;
            busy        <= 0;
            done        <= 0;
            ack_fail    <= 0;
            arb_lost    <= 0;
            scl_out     <= 1;
            sda_out     <= 1;
            sda_oe      <= 0;
            read_data   <= 0;
            byte_cnt    <= 0;
            tx_data_reg <= 0;
            shift_reg   <= 0;
            rw_reg      <= 0;

        end 
        else begin
            done <= 1'b0;
            
            if (state == IDLE) begin
                scl_out <= 1'b1;
                sda_out <= 1'b1;
                sda_oe  <= 1'b0; 
                if (start_req && !busy&& bus_free) begin
                    busy        <= 1'b1;
                    ack_fail    <= 1'b0;
                    arb_lost    <= 1'b0;
                    state       <= START;
                    phase       <= 2'b00;
                    // R/W bit
                    rw_reg      <= rw;
                    shift_reg   <= {dev_addr, rw};
                    tx_data_reg <= write_data; // 鎖存資料
                    byte_cnt    <= (n_bytes == 0) ? 4'd1 : (n_bytes > 8)  ? 4'd8 : n_bytes;// 設定傳輸長度
                end
            end 
            else if (tick) begin 
                phase <= phase + 1; // tick觸發表示某一階段，phase表示現在是低電or上升or高電or下降
                    // 仲裁失敗優先權最高
                if (arb_lost_cond) begin
                    arb_lost <= 1'b1;
                    scl_out <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b0;
                    state   <= IDLE;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    phase   <= 2'b00;
                    $display("[%0t] ARB_LOST state=%0d bit=%0d",$time, state, bit_cnt);
                end
                else begin
                case (state)
                    START: begin
                        case (phase)
 							// 我超之前的寫法，是利用SDA正緣(還負緣)觸發與SCL相反，
							// 來實踐SDA在SCL=0時才改變；SCL=1時不變，及控制sda_w
							// 但現在的寫法是直接用case規定低電位、上升期、高電位、下降期
							// scl_out和sda_oe分別該是什麼
							// 藉此控制sda_w   
                            2'b00: begin scl_out <= 1; sda_out <= 1; sda_oe <= 1; end
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin sda_out <= 0; end 
                            2'b11: begin scl_out <= 0; end 
                        endcase
                        if (phase == 2'b11) begin state <= TX_ADDR; bit_cnt <= 7; end
                    end

                    TX_ADDR: begin
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_out <= shift_reg[7]; end
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin 
                            end
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            if (bit_cnt == 0) begin
                                state <= ACK_ADDR;
                            end
                            else begin 
                                bit_cnt <= bit_cnt - 1; 
                                shift_reg <= {shift_reg[6:0], 1'b0};  
                            end
                        end
                    end

                    ACK_ADDR: begin   // 這邊可跟slave的S_ACK一起看
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_oe <= 0; end  // master把scl拉低，sda的部分放手。讓slave操控
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin ack_fail <= sda_w; end 
                            // 這裡很重要
							// 為什麼sda_w是1的時候反而會失敗(看後面會進STOP)
							// 因為我已經把sda_oe給0，這表示master沒控制權，sda_w理應會是1'bz(看assign那條)
							// 但不要忘記sda_w是master跟slave共用的
							// 若slave有收到地址的話，slave會來控制這條sda_w
							// 所以slave會往下拉(導致sda_w = 0)
							// 所以如果是1的話反而表示sda那邊沒反應，則表示失敗
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            if (ack_fail) state <= STOP;
                            else if (rw_reg == 1'b0) begin 
                                state     <= TX_DATA; 
                                // 動態切出當前要傳的 8-bit (高位元 Byte 優先)                                
                                shift_reg <= tx_data_reg[(byte_cnt-1)*8 +: 8]; 
                                byte_cnt  <= byte_cnt - 1;
                                bit_cnt   <= 7; 
                            end
                            else begin 
                                state     <= RX_DATA; 
                                bit_cnt   <= 7; 
                                read_data <= 64'd0;  // 清空準備接收
                            end
                        end
                    end

                    TX_DATA: begin
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_out <= shift_reg[7]; sda_oe <= 1; end
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin            
                            end
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            if (bit_cnt == 0) state <= ACK_TX;
                            else begin bit_cnt <= bit_cnt - 1; shift_reg <= {shift_reg[6:0], 1'b0}; end
							// 還有byte要傳就繼續
                        end
                    end

                    ACK_TX: begin
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_oe <= 0; end
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin ack_fail <= sda_w; end
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            // 若還有 Byte 沒傳完，繼續傳
                            if (ack_fail || byte_cnt == 0) state <= STOP;
                            else begin
                                state     <= TX_DATA;
                                shift_reg <= tx_data_reg[(byte_cnt-1)*8 +: 8];
                                byte_cnt  <= byte_cnt - 1;
                                bit_cnt   <= 7;
                            end
                        end
                    end

                    RX_DATA: begin
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_oe <= 0; end
                            2'b01: begin scl_out <= 1; end
                            // 下降緣讀取slave寫入的 bit ， 推入 64-bit 暫存器中
                            2'b10: begin read_data <= {read_data[62:0], sda_r2}; end 
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            if (bit_cnt == 0) state <= ACK_RX;
                            else bit_cnt <= bit_cnt - 1;
                        end
                    end

                    ACK_RX: begin
                        case (phase)
                            2'b00: begin 
                                scl_out <= 0; 
                                sda_oe  <= 1; 
                                // 還有 Byte 沒讀完給 ACK(0)，讀完給 NACK(1)
                                sda_out <= (byte_cnt > 1) ? 1'b0 : 1'b1; 
                            end 
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin end
                            2'b11: begin scl_out <= 0; end
                        endcase
                        if (phase == 2'b11) begin
                            if (byte_cnt > 1) begin
                                byte_cnt <= byte_cnt - 1;
                                state    <= RX_DATA;
                                bit_cnt  <= 7;
                            end else begin
                                state <= STOP;
                            end
                        end
                    end

                    STOP: begin
                        case (phase)
                            2'b00: begin scl_out <= 0; sda_out <= 0; sda_oe <= 1; end 
                            2'b01: begin scl_out <= 1; end 
                            2'b10: begin scl_out <= 1; end
                            2'b11: begin sda_out <= 1; scl_out <= 1'b1; sda_oe  <= 1'b0;end 
                        endcase
                        if (phase == 2'b11) begin
                            state  <= IDLE;
                            busy   <= 0;
                            done   <= 1; 
                        end
                    end
                endcase
            end
        end
    end
    end
endmodule
