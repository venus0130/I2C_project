`timescale 1ns/1ps

module tb_i2c;

    parameter SLAVE_ADDR = 7'h3C;

    reg clk;
    reg reset;

    initial begin
        clk = 1'b0;
    end

    always #10 clk = ~clk;    // Period = 20 ns (50 MHz clock)

    // Master 0 
    reg        start_0;
    reg [3:0]  nbytes_0;
    reg [6:0]  addr_0;
    reg        rw_0;
    reg [63:0] write_data_0;

    wire [63:0] read_data_0;
    wire        busy_0;
    wire        done_0;
    wire        ack_fail_0;
    wire        arb_lost_0;

    // Master 1 
    reg        start_1;
    reg [3:0]  nbytes_1;
    reg [6:0]  addr_1;
    reg        rw_1;
    reg [63:0] write_data_1;

    wire [63:0] read_data_1;
    wire        busy_1;
    wire        done_1;
    wire        ack_fail_1;
    wire        arb_lost_1;

    // Slave 
    wire [7:0] slave_rx_data;
    wire       slave_rx_valid;
    wire       slave_busy;
    wire       slave_addr_match;

    // I²C Bus
    wire sda;
    wire scl;
    // 模擬外部上拉電阻
    pullup(sda);
    pullup(scl);

    i2c_system_top #(
        .SLAVE_ADDR(SLAVE_ADDR)
    ) u_top (
        .clk   (clk),
        .reset (reset),


        .start_0       (start_0),
        .nbytes_0      (nbytes_0),
        .addr_0        (addr_0),
        .rw_0          (rw_0),
        .write_data_0  (write_data_0),

        .read_data_0   (read_data_0),
        .busy_0        (busy_0),
        .done_0        (done_0),
        .ack_fail_0    (ack_fail_0),
        .arb_lost_0    (arb_lost_0),

        .start_1       (start_1),
        .nbytes_1      (nbytes_1),
        .addr_1        (addr_1),
        .rw_1          (rw_1),
        .write_data_1  (write_data_1),

        .read_data_1   (read_data_1),
        .busy_1        (busy_1),
        .done_1        (done_1),
        .ack_fail_1    (ack_fail_1),
        .arb_lost_1    (arb_lost_1),

        .slave_rx_data    (slave_rx_data),
        .slave_rx_valid   (slave_rx_valid),
        .slave_busy       (slave_busy),
        .slave_addr_match (slave_addr_match),

        .sda (sda),
        .scl (scl)
    );

    integer pass_cnt;
    integer fail_cnt;

    // ============================================================
    // Task：Master 0 單獨交易
    // ============================================================
    task master0_transaction;
        input [6:0]  t_addr;
        input        t_rw;
        input [3:0]  t_nbytes;
        input [63:0] t_wdata;

        begin
            addr_0       = t_addr;
            rw_0         = t_rw;
            nbytes_0     = t_nbytes;
            write_data_0 = t_wdata;

            // 在負緣改變 start，避免與 DUT 的正緣邏輯競爭
            @(negedge clk);
            start_0 = 1'b1;

            @(negedge clk);
            start_0 = 1'b0;

            wait (busy_0 == 1'b1);
            wait (done_0 == 1'b1);

            @(posedge clk);
        end
    endtask

    // ============================================================
    // Task：Master 1 單獨交易
    // ============================================================
    task master1_transaction;
        input [6:0]  t_addr;
        input        t_rw;
        input [3:0]  t_nbytes;
        input [63:0] t_wdata;

        begin
            addr_1       = t_addr;
            rw_1         = t_rw;
            nbytes_1     = t_nbytes;
            write_data_1 = t_wdata;

            @(negedge clk);
            start_1 = 1'b1;

            @(negedge clk);
            start_1 = 1'b0;

            wait (busy_1 == 1'b1);
            wait (done_1 == 1'b1);

            @(posedge clk);
        end
    endtask

    // ============================================================
    // Task：同時啟動 Master 0 與 Master 1
    // ============================================================
    task start_both_masters;
        begin
            @(negedge clk);
            start_0 = 1'b1;
            start_1 = 1'b1;

            @(negedge clk);
            start_0 = 1'b0;
            start_1 = 1'b0;
        end
    endtask

    // ============================================================
    // Task：檢查測試結果
    // ============================================================
    task check;
        input        condition;
        input [255:0] message;

        begin
            if (condition) begin
                $display("[PASS] %s", message);
                pass_cnt = pass_cnt + 1;
            end
            else begin
                $display("[FAIL] %s", message);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ============================================================
    // Monitor：監看 Slave 與 Master 事件
    // ============================================================
    reg slave_addr_match_d;
    reg done_0_d;
    reg done_1_d;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            slave_addr_match_d <= 1'b0;
            done_0_d           <= 1'b0;
            done_1_d           <= 1'b0;
        end
        else begin
            slave_addr_match_d <= slave_addr_match;
            done_0_d           <= done_0;
            done_1_d           <= done_1;

            // ----------------------------------------------------
            // Slave 收到資料
            // ----------------------------------------------------
            if (slave_rx_valid) begin
                $display("[%0t ns] [MON] Slave RX data = 0x%02h",
                         $time,
                         slave_rx_data);
            end

            // ----------------------------------------------------
            // Slave 地址符合
            // ----------------------------------------------------
            if (slave_addr_match && !slave_addr_match_d) begin
                $display("[%0t ns] [MON] Slave address matched",
                         $time);
            end

            // ----------------------------------------------------
            // Master 0 完成
            // ----------------------------------------------------
            if (done_0 && !done_0_d) begin
                if (arb_lost_0) begin
                    $display("[%0t ns] [MON] Master 0: ARBITRATION LOST",
                             $time);
                end
                else if (ack_fail_0) begin
                    $display("[%0t ns] [MON] Master 0: NACK",
                             $time);
                end
                else begin
                    $display("[%0t ns] [MON] Master 0: DONE OK",
                             $time);
                end
            end

            // ----------------------------------------------------
            // Master 1 完成
            // ----------------------------------------------------
            if (done_1 && !done_1_d) begin
                if (arb_lost_1) begin
                    $display("[%0t ns] [MON] Master 1: ARBITRATION LOST",
                             $time);
                end
                else if (ack_fail_1) begin
                    $display("[%0t ns] [MON] Master 1: NACK",
                             $time);
                end
                else begin
                    $display("[%0t ns] [MON] Master 1: DONE OK",
                             $time);
                end
            end
        end
    end


    initial begin
        // 初始化
        pass_cnt = 0;
        fail_cnt = 0;

        reset = 1'b1;

        // Master 0 初始值
        start_0      = 1'b0;
        nbytes_0     = 4'd0;
        addr_0       = 7'h00;
        rw_0         = 1'b0;
        write_data_0 = 64'h0;

        // Master 1 初始值
        start_1      = 1'b0;
        nbytes_1     = 4'd0;
        addr_1       = 7'h00;
        rw_1         = 1'b0;
        write_data_1 = 64'h0;

        // Reset
        #5000;
        reset = 1'b0;

        // 等待系統穩定
        #5000;

        // ========================================================
        // TEST1：
        // Master 0 READ + Clock Stretching
        // ========================================================
        $display("");
        $display("================================================");
        $display("TEST1: Master 0 READ + Clock Stretching");
        $display("================================================");

        /*
         \* Master 0：
         \*   Address = 0x3C
         \*   R/W     = READ
         \*   nbytes  = 1
         \*
         \* Slave：
         \*   進入 S_TX_WAIT
         \*   scl_oe = 1，主動拉低 SCL
         \*   等待 tx_data_valid
         \*   回傳 8'hA5
         \*   釋放 SCL*/
         
        master0_transaction(
            SLAVE_ADDR,
            1'b1,
            4'd1,
            64'h0
        );

        check(
            !ack_fail_0 && !arb_lost_0,
            "TEST1: Master 0 READ with Clock Stretching completed"
        );

        check(
            read_data_0[7:0] == 8'hA5,
            "TEST1: Master 0 received 0xA5"
        );

        $display(
            "[INFO] TEST1 read_data_0 = 0x%02h, expected = 0xA5",
            read_data_0[7:0]
        );

        #5000;

        // ========================================================
        // TEST2：
        // Address Arbitration
        //
        // Master 0：0x3C WRITE
        // Master 1：0x3D WRITE
        // ========================================================
        $display("");
        $display("================================================");
        $display("TEST2: Address Arbitration");
        $display("Master 0: 0x3C WRITE");
        $display("Master 1: 0x3D WRITE");
        $display("================================================");

        /*
         \* 0x3C = 0111100
         \* 0x3D = 0111101
         \*
         \* 在地址最低位：
         \*
         \* Master 0 輸出 0，主動拉低 SDA
         \* Master 1 輸出 1，釋放 SDA
         \* 實際 SDA = 0
         \*
         \* Master 1 發送 1 但讀到 0，
         \* 因此 Master 1 輸掉 Arbitration。
         \*/
        addr_0       = SLAVE_ADDR;
        rw_0         = 1'b0;
        nbytes_0     = 4'd1;
        write_data_0 = {56'h0, 8'h11};

        addr_1       = 7'h3D;
        rw_1         = 1'b0;
        nbytes_1     = 4'd1;
        write_data_1 = {56'h0, 8'h22};

        start_both_masters();

        // 等待任一 Master 發生仲裁失敗
        wait (arb_lost_0 || arb_lost_1);

        check(
            arb_lost_1 && !arb_lost_0,
            "TEST2: Master 1 lost address arbitration"
        );

        // 等待勝出的 Master 0 完成
        wait (done_0 == 1'b1);
        @(posedge clk);

        check(
            !ack_fail_0 && !arb_lost_0,
            "TEST2: Master 0 completed after winning arbitration"
        );

        #5000;

        // ========================================================
        // TEST3：
        // Data Arbitration
        //
        // Master 0：Address = 0x3C，Data = 0xFF
        // Master 1：Address = 0x3C，Data = 0x00
        // ========================================================
        $display("");
        $display("================================================");
        $display("TEST3: Data Arbitration");
        $display("Master 0: ADDR 0x3C, DATA 0xFF");
        $display("Master 1: ADDR 0x3C, DATA 0x00");
        $display("================================================");

        /*
         \* 兩個 Master 使用相同地址，因此地址階段不會分出勝負。
         \*
         \* Master 0：0xFF = 11111111
         \* Master 1：0x00 = 00000000
         \*
         \* 在資料第一個 bit：
         \*
         \* Master 0 想輸出 1，釋放 SDA
         \* Master 1 輸出 0，拉低 SDA
         \* 實際 SDA = 0
         \*
         \* Master 0 讀到：
         \*   sda_out = 1
         \*   sda_r2  = 0
         \*
         \* 因此 Master 0 輸掉 Data Arbitration。
         */
        addr_0       = SLAVE_ADDR;
        rw_0         = 1'b0;
        nbytes_0     = 4'd1;
        write_data_0 = {56'h0, 8'hFF};

        addr_1       = SLAVE_ADDR;
        rw_1         = 1'b0;
        nbytes_1     = 4'd1;
        write_data_1 = {56'h0, 8'h00};

        start_both_masters();

        // 等待任一 Master 發生仲裁失敗
        wait (arb_lost_0 || arb_lost_1);

        check(
            arb_lost_0 && !arb_lost_1,
            "TEST3: Master 0 lost data arbitration"
        );

        // 等待勝出的 Master 1 完成
        wait (done_1 == 1'b1);
        @(posedge clk);

        check(
            !ack_fail_1 && !arb_lost_1,
            "TEST3: Master 1 completed after winning arbitration"
        );

        #5000;

        // ========================================================
        // 測試結果統計
        // ========================================================
        $display("");
        $display("================================================");
        $display("ALL SELECTED TESTS DONE");
        $display("PASS = %0d", pass_cnt);
        $display("FAIL = %0d", fail_cnt);
        $display("================================================");

        if (fail_cnt == 0) begin
            $display("RESULT: ALL SELECTED TESTS PASSED");
        end
        else begin
            $display("RESULT: SOME TESTS FAILED");
        end

        $finish;
    end

    // ============================================================
    // VCD 波形輸出
    // ============================================================
    initial begin
        $dumpfile("i2c_wave_selected.vcd");
        $dumpvars(0, tb_i2c);
    end

    // ============================================================
    // Timeout 保護
    // ============================================================
    initial begin
        #5_000_000;
        $display("[TIMEOUT] Simulation exceeded time limit!");
        $finish;
    end

endmodule
