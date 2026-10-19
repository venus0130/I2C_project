Multi-Master I²C Controller with Clock Stretching and Arbitration
A Verilog RTL implementation of a shared-bus I²C system featuring two masters, one slave, clock stretching, and multi-master arbitration. The design demonstrates how multiple controllers can share an open-drain I²C bus without an external multiplexer.
Features
- Two independent I²C masters sharing SCL and SDA
- Address-phase and data-phase arbitration
- Slave-controlled clock stretching
- Master read and write transactions with ACK/NACK handling
- Open-drain signaling with pull-ups modeled in the testbench
- Single-system-clock, tick/phase-based master timing
- RTL testbench and ModelSim/Questa waveform configuration
Architecture
        +-----------+             +-----------+
        | Master 0  |----+--------|           |
        +-----------+    |        |           |
                         +--SCL---|   Slave   |
                         +--SDA---|  (0x3C)   |
        +-----------+    |        |           |
        | Master 1  |----+--------|           |
        +-----------+             +-----------+
             Shared open-drain I²C bus
Both masters use a 50 MHz system clock and are configured for a 400 kHz target I²C clock in i2c_system_top.v. Each master uses tick-based timing to track SCL phases and monitors the actual bus state before advancing when SCL is stretched.

Arbitration: While SCL is high, a master transmitting logic 1 but sampling logic 0 on SDA loses arbitration and returns to IDLE. The winning master can continue its transaction.

Clock stretching: The slave can hold SCL low while waiting for transmit data or preparing an acknowledgment. The master waits for the released bus to return high before proceeding.
Files
File	Description
i2c_master.v	I²C master RTL, including timing, read/write FSM, arbitration, and stretching support
i2c_slave.v	I²C slave RTL, including data reception/transmission and clock stretching
i2c_system_top.v	Two-master/one-slave integration and example slave transmit-data provider
tb_i2c.v	RTL testbench with three functional test scenarios
wave_test.do	ModelSim/Questa waveform setup
InternshipReport.pptx	Internship project presentation and waveform examples


Functional Verification
The supplied tb_i2c.v includes the following checks:
Test	Scenario	Expected behavior
1	Master 0 reads one byte from slave 0x3C	Slave returns 0xA5; read transaction exercises clock stretching
2	Address arbitration: Master 0 targets 0x3C, Master 1 targets 0x3D	Master 1 loses arbitration; Master 0 completes its write of 0x11
3	Data arbitration: both target 0x3C; Master 0 sends 0xFF, Master 1 sends 0x00	Master 0 loses arbitration; Master 1 completes its write


The testbench prints [PASS]/[FAIL] messages and a final summary. It also generates i2c_wave_selected.vcd for waveform inspection. These are implemented test scenarios, not a claim of independently rerun results.
Simulation
With Icarus Verilog installed, run from the directory containing the Verilog files:
iverilog -g2012 -s tb_i2c -o i2c_sim \
  i2c_master.v i2c_slave.v i2c_system_top.v tb_i2c.v
vvp i2c_sim
Open i2c_wave_selected.vcd in a compatible waveform viewer such as GTKWave.

For ModelSim/Questa, a typical workflow is:
vlib work
vlog i2c_master.v i2c_slave.v i2c_system_top.v tb_i2c.v
vsim work.tb_i2c
do wave_test.do
run -all
The simulation commands are provided for reproducibility; they have not been executed in this README preparation environment.

Design Notes
- The physical I²C bus requires pull-up resistors. The RTL models open-drain outputs as 0 or high impedance (Z), and the testbench instantiates pullup primitives.
- The top-level slave returns 8'hA5 when transmit data is requested; this is an example data source, not a complete peripheral register map.
- The testbench currently reads one byte (0xA5) in Test 1 and uses 0x00 as Master 1's data in Test 3. These values differ from some examples shown in InternshipReport.pptx (0xA5A5 and 0x01).
- FPGA/ASIC hardware validation, more than two masters, and repeated-START/combined transactions are potential future extensions, not verified features of this version.
Project Context
Developed as part of a 2026 internship project, focusing on RTL design and functional verification of multi-master I²C communication.
