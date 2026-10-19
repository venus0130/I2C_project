onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Global & Bus} /tb_i2c/clk
add wave -noupdate -expand -group {Global & Bus} /tb_i2c/reset
add wave -noupdate -expand -group {Global & Bus} -color Cyan /tb_i2c/scl
add wave -noupdate -expand -group {Global & Bus} -color Yellow /tb_i2c/sda
add wave -noupdate -expand -group {Data Arbitration} /tb_i2c/u_top/u_master_0/start_req
add wave -noupdate -expand -group {Data Arbitration} /tb_i2c/u_top/u_master_1/start_req
add wave -noupdate -expand -group {Data Arbitration} -radix unsigned /tb_i2c/u_top/u_master_0/state
add wave -noupdate -expand -group {Data Arbitration} -radix unsigned /tb_i2c/u_top/u_master_1/state
add wave -noupdate -expand -group {Data Arbitration} -radix hexadecimal /tb_i2c/u_top/u_master_0/shift_reg
add wave -noupdate -expand -group {Data Arbitration} -radix hexadecimal /tb_i2c/u_top/u_master_1/shift_reg
add wave -noupdate -expand -group {Data Arbitration} -color Yellow /tb_i2c/u_top/u_master_0/sda_out
add wave -noupdate -expand -group {Data Arbitration} -color Yellow /tb_i2c/u_top/u_master_1/sda_out
add wave -noupdate -expand -group {Data Arbitration} /tb_i2c/u_top/u_master_0/sda_r2
add wave -noupdate -expand -group {Data Arbitration} -color {Medium Orchid} /tb_i2c/u_top/u_master_0/arb_lost_cond
add wave -noupdate -expand -group {Data Arbitration} -color {Medium Orchid} /tb_i2c/arb_lost_0
add wave -noupdate -expand -group {Data Arbitration} /tb_i2c/done_0
add wave -noupdate -expand -group {Data Arbitration} /tb_i2c/done_1
add wave -noupdate -expand -group {Clock Stretching} -color Magenta /tb_i2c/u_top/u_slave/scl_oe
add wave -noupdate -expand -group {Clock Stretching} -radix unsigned /tb_i2c/u_top/u_slave/stretch_cnt
add wave -noupdate -expand -group {Clock Stretching} -color Cyan /tb_i2c/scl
add wave -noupdate -expand -group {Address Arbitration} /tb_i2c/u_top/u_master_0/start_req
add wave -noupdate -expand -group {Address Arbitration} /tb_i2c/u_top/u_master_1/start_req
add wave -noupdate -expand -group {Address Arbitration} -radix unsigned /tb_i2c/u_top/u_master_0/state
add wave -noupdate -expand -group {Address Arbitration} -radix unsigned /tb_i2c/u_top/u_master_1/state
add wave -noupdate -expand -group {Address Arbitration} -color Yellow /tb_i2c/u_top/u_master_0/sda_out
add wave -noupdate -expand -group {Address Arbitration} -color Yellow /tb_i2c/u_top/u_master_1/sda_out
add wave -noupdate -expand -group {Address Arbitration} /tb_i2c/u_top/u_master_0/sda_r2
add wave -noupdate -expand -group {Address Arbitration} -color Magenta /tb_i2c/u_top/u_master_1/arb_lost_cond
add wave -noupdate -expand -group {Address Arbitration} -color Magenta /tb_i2c/arb_lost_1
add wave -noupdate -expand -group {Address Arbitration} /tb_i2c/done_0
add wave -noupdate -expand -group {Address Arbitration} /tb_i2c/done_1
add wave -noupdate -expand -group {Read & Clock Stretch} /tb_i2c/done_0
add wave -noupdate -expand -group {Read & Clock Stretch} -radix hexadecimal /tb_i2c/read_data_0
add wave -noupdate -expand -group {Read & Clock Stretch} -color Magenta /tb_i2c/u_top/slave_tx_valid
add wave -noupdate -expand -group {Read & Clock Stretch} -color Magenta /tb_i2c/u_top/u_slave/tx_data_req
add wave -noupdate -expand -group {Read & Clock Stretch} /tb_i2c/u_top/u_master_0/tick
add wave -noupdate -expand -group {Read & Clock Stretch} /tb_i2c/u_top/u_master_0/scl_r2
add wave -noupdate -expand -group {Read & Clock Stretch} -color Magenta /tb_i2c/u_top/u_slave/scl_oe
add wave -noupdate -expand -group {Read & Clock Stretch} -radix unsigned /tb_i2c/u_top/u_slave/state
add wave -noupdate -expand -group {Read & Clock Stretch} -radix unsigned /tb_i2c/u_top/u_master_0/state
add wave -noupdate -expand -group {Read & Clock Stretch} /tb_i2c/slave_addr_match
add wave -noupdate -expand -group {Read & Clock Stretch} /tb_i2c/u_top/u_master_0/start_req
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {125053858 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 263
configure wave -valuecolwidth 40
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 1
configure wave -timelineunits ns
update
WaveRestoreZoom {126255080 ps} {182235758 ps}
