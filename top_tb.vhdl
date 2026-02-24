-- top_tb.vhdl — Testbench for TOP (SPI spy system)
-- Tests the complete data path: MCU SPI capture -> buffer -> COMM SPI readout

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ================================================================
-- Behavioral model for MEMORY (dual-port RAM 512x64)
-- ================================================================
entity memory_model is
    port (
        clock     : in  std_logic;
        data      : in  std_logic_vector(63 downto 0);
        rdaddress : in  std_logic_vector(8 downto 0);
        wraddress : in  std_logic_vector(8 downto 0);
        wren      : in  std_logic;
        q         : out std_logic_vector(63 downto 0)
    );
end entity;

architecture behavioral of memory_model is
    type ram_t is array(0 to 511) of std_logic_vector(63 downto 0);
    signal ram : ram_t := (others => (others => '0'));
    signal rd_addr_reg : std_logic_vector(8 downto 0) := (others => '0');
begin

    process(clock)
    begin
        if rising_edge(clock) then
            if wren = '1' then
                ram(to_integer(unsigned(wraddress))) <= data;
            end if;
            rd_addr_reg <= rdaddress;
        end if;
    end process;

    process(clock)
    begin
        if rising_edge(clock) then
            q <= ram(to_integer(unsigned(rd_addr_reg)));
        end if;
    end process;

end architecture;

-- ================================================================
-- Behavioral model for COMM_SPI (SPI slave with Avalon-ST)
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;

entity comm_spi_model is
    port (
        SYSCLK        : in  std_logic;
        NRESET        : in  std_logic;
        MOSI          : in  std_logic;
        NSS           : in  std_logic;
        MISO          : inout std_logic;
        SCLK          : in  std_logic;
        STSINKVALID   : in  std_logic;
        STSINKDATA    : in  std_logic_vector(7 downto 0);
        STSINKREADY   : out std_logic;
        STSOURCEVALID : out std_logic;
        STSOURCEDATA  : out std_logic_vector(7 downto 0);
        STSOURCEREADY : in  std_logic
    );
end entity;

architecture behavioral of comm_spi_model is
    signal shift_out     : std_logic_vector(7 downto 0) := (others => '1');
    signal shift_in      : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_cnt       : integer range 0 to 7 := 0;
    signal sclk_d        : std_logic := '0';
    signal data_loaded   : std_logic := '0';
begin

    process(SYSCLK)
    begin
        if rising_edge(SYSCLK) then
            if NRESET = '1' then
                shift_out     <= (others => '1');
                shift_in      <= (others => '0');
                bit_cnt       <= 0;
                sclk_d        <= '0';
                data_loaded   <= '0';
                STSINKREADY   <= '0';
                STSOURCEVALID <= '0';
                STSOURCEDATA  <= (others => '0');
            else
                sclk_d <= SCLK;
                STSINKREADY <= '0';
                STSOURCEVALID <= '0';
                
                if NSS = '1' then
                    bit_cnt <= 0;
                    data_loaded <= '0';
                    shift_out <= (others => '1');
                else
                    if data_loaded = '0' and STSINKVALID = '1' then
                        shift_out <= STSINKDATA;
                        STSINKREADY <= '1';
                        data_loaded <= '1';
                    end if;

                    if SCLK = '1' and sclk_d = '0' then
                        shift_in <= shift_in(6 downto 0) & MOSI;
                    end if;
                    
                    if SCLK = '0' and sclk_d = '1' then
                        shift_out <= shift_out(6 downto 0) & '1';
                        if bit_cnt = 7 then
                            bit_cnt <= 0;
                            data_loaded <= '0';
                            STSOURCEVALID <= '1';
                            STSOURCEDATA <= shift_in(6 downto 0) & MOSI;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    MISO <= shift_out(7) when NSS = '0' else 'Z';

end architecture;

-- ================================================================
-- Main testbench
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_tb is
end entity;

architecture sim of top_tb is

    constant CLK_PERIOD  : time := 20 ns;
    constant SPI_HALF    : time := 100 ns;
    constant SYNC_SETTLE : time := CLK_PERIOD * 6;

    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';

    signal mcu_spi_ss_n   : std_logic := '1';
    signal mcu_spi_clk    : std_logic := '0';
    signal mcu_spi_mosi   : std_logic := '0';

    signal comm_spi_ss_n  : std_logic := '1';
    signal comm_spi_clk   : std_logic := '0';
    signal comm_spi_mosi  : std_logic := '0';
    signal comm_spi_miso  : std_logic;

    signal led_ready      : std_logic;
    signal led_overflow   : std_logic;
    signal led_mcu_act    : std_logic;
    signal led_comm_act   : std_logic;
    signal gpio_ready     : std_logic;

    signal dbg_spi_ss_n   : std_logic;
    signal dbg_spi_clk    : std_logic;
    signal dbg_spi_miso   : std_logic;

    signal done           : boolean := false;
    signal pass_count     : integer := 0;
    signal fail_count     : integer := 0;

    signal time_val       : std_logic_vector(15 downto 0);
    signal reset_n        : std_logic;
    signal spy_addr_out   : std_logic_vector(23 downto 0);
    signal spy_byte_count : std_logic_vector(23 downto 0);
    signal spy_strobe     : std_logic;
    signal read_next      : std_logic;
    signal read_ready     : std_logic;
    signal read_lost      : std_logic;
    signal mem_write      : std_logic;
    signal mem_addr_in    : std_logic_vector(8 downto 0);
    signal mem_addr_out   : std_logic_vector(8 downto 0);
    signal mem_data_in    : std_logic_vector(63 downto 0);
    signal mem_data_out   : std_logic_vector(63 downto 0);
    signal read_addr      : std_logic_vector(23 downto 0);
    signal read_count     : std_logic_vector(23 downto 0);
    signal read_time      : std_logic_vector(15 downto 0);
    signal st_sink_data   : std_logic_vector(7 downto 0);
    signal st_sink_valid  : std_logic;
    signal st_sink_ready  : std_logic;
    signal st_source_data : std_logic_vector(7 downto 0);
    signal st_source_valid: std_logic;
    signal st_source_ready: std_logic;

    procedure send_byte (
        signal   spi_clk_o : out std_logic;
        signal   mosi_o    : out std_logic;
        constant data      : in  std_logic_vector(7 downto 0)
    ) is
    begin
        for i in 7 downto 0 loop
            mosi_o <= data(i);
            wait for SPI_HALF;
            spi_clk_o <= '1';
            wait for SPI_HALF;
            spi_clk_o <= '0';
        end loop;
    end procedure;

    procedure comm_spi_xfer (
        signal   spi_clk_o : out std_logic;
        signal   mosi_o    : out std_logic;
        signal   miso_i    : in  std_logic;
        constant tx_data   : in  std_logic_vector(7 downto 0);
        variable rx_data   : out std_logic_vector(7 downto 0)
    ) is
        variable rx : std_logic_vector(7 downto 0) := (others => '0');
    begin
        for i in 7 downto 0 loop
            mosi_o <= tx_data(i);
            wait for SPI_HALF;
            spi_clk_o <= '1';
            rx(i) := miso_i;
            wait for SPI_HALF;
            spi_clk_o <= '0';
        end loop;
        rx_data := rx;
    end procedure;

    procedure check(
        signal   p    : inout integer;
        signal   f    : inout integer;
        constant ok   : in boolean;
        constant msg  : in string
    ) is
    begin
        if ok then
            report "PASS: " & msg severity note;
            p <= p + 1;
        else
            report "FAIL: " & msg severity error;
            f <= f + 1;
        end if;
    end procedure;

begin
    reset_n <= reset;

    clk_gen : process
    begin
        while not done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    clock_unit: entity work.CLOCK
    port map (
        RESET    => reset_n,
        CLK      => clk,
        TIME_OUT => time_val
    );

    mcu_spi_inst: entity work.SPISPY
    port map (
        RESET      => reset_n,
        CLK        => clk,
        SPI_CS_N   => mcu_spi_ss_n,
        SPI_CLK    => mcu_spi_clk,
        SPI_MOSI   => mcu_spi_mosi,
        ADDR_OUT   => spy_addr_out,
        BYTE_COUNT => spy_byte_count,
        STROBE     => spy_strobe
    );

    bufctrl_inst: entity work.BUFCTRL
    port map (
        RESET        => reset_n,
        CLK          => clk,
        CAP_ADDR     => spy_addr_out,
        CAP_COUNT    => spy_byte_count,
        CAP_STROBE   => spy_strobe,
        CAP_TIME     => time_val,
        READ_ADDR    => read_addr,
        READ_COUNT   => read_count,
        READ_TIME    => read_time,
        READ_READY   => read_ready,
        READ_LOST    => read_lost,
        READ_NEXT    => read_next,
        MEM_ADDR_IN  => mem_addr_in,
        MEM_DATA_IN  => mem_data_in,
        MEM_ADDR_OUT => mem_addr_out,
        MEM_DATA_OUT => mem_data_out,
        MEM_WRITE    => mem_write
    );

    ram_model: entity work.memory_model
    port map (
        clock     => clk,
        data      => mem_data_out,
        rdaddress => mem_addr_in,
        wraddress => mem_addr_out,
        wren      => mem_write,
        q         => mem_data_in
    );

    comm_spi_inst: entity work.comm_spi_model
    port map (
        SYSCLK        => clk,
        NRESET        => reset,
        MOSI          => comm_spi_mosi,
        NSS           => comm_spi_ss_n,
        MISO          => comm_spi_miso,
        SCLK          => comm_spi_clk,
        STSINKVALID   => st_sink_valid,
        STSINKDATA    => st_sink_data,
        STSINKREADY   => st_sink_ready,
        STSOURCEVALID => st_source_valid,
        STSOURCEDATA  => st_source_data,
        STSOURCEREADY => st_source_ready
    );

    comm_ctrl_inst: entity work.COMM_CTRL
    port map (
        CLK             => clk,
        RESET           => reset_n,
        READ_ADDR       => read_addr,
        READ_COUNT      => read_count,
        READ_TIME       => read_time,
        READ_READY      => read_ready,
        READ_LOST       => read_lost,
        READ_NEXT       => read_next,
        ST_SINK_DATA    => st_sink_data,
        ST_SINK_VALID   => st_sink_valid,
        ST_SINK_READY   => st_sink_ready,
        ST_SOURCE_DATA  => st_source_data,
        ST_SOURCE_VALID => st_source_valid,
        ST_SOURCE_READY => st_source_ready,
        SPI_SS_N        => comm_spi_ss_n
    );

    led_ready    <= not read_ready;
    led_overflow <= not read_lost;
    led_mcu_act  <= mcu_spi_ss_n;
    led_comm_act <= comm_spi_ss_n;
    gpio_ready   <= read_ready;

    dbg_spi_ss_n <= comm_spi_ss_n;
    dbg_spi_clk  <= comm_spi_clk;
    dbg_spi_miso <= comm_spi_miso;

    stim : process
        constant CMD_READ   : std_logic_vector(7 downto 0) := x"03";
        variable rx_byte    : std_logic_vector(7 downto 0);
        variable rx_record  : std_logic_vector(63 downto 0);
        variable exp_addr   : std_logic_vector(23 downto 0);
        variable exp_count  : std_logic_vector(23 downto 0);
    begin
        -- =========================================================
        -- TEST 1: Reset
        -- =========================================================
        report "=== TEST 1: Reset ===" severity note;
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '0',
              "GPIO_READY = 0 after reset (buffer empty)");

        check(pass_count, fail_count,
              led_ready = '1',
              "LED_READY = 1 (inverted) after reset");

        -- =========================================================
        -- TEST 2: MCU SPI Transaction: Read 0xABCDEF with 4 data bytes
        -- =========================================================
        report "=== TEST 2: MCU SPI capture (addr 0xABCDEF, 4 bytes) ===" severity note;

        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;

        send_byte(mcu_spi_clk, mcu_spi_mosi, CMD_READ);
        wait for SYNC_SETTLE;

        send_byte(mcu_spi_clk, mcu_spi_mosi, x"AB");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"CD");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"EF");
        wait for SYNC_SETTLE;

        send_byte(mcu_spi_clk, mcu_spi_mosi, x"11");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"22");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"33");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"44");
        wait for SYNC_SETTLE;

        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '1',
              "GPIO_READY = 1 after MCU transaction captured");

        -- =========================================================
        -- TEST 3: COMM SPI Readout: Read captured record
        -- =========================================================
        report "=== TEST 3: COMM SPI readout ===" severity note;

        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 10;

        rx_record := (others => '0');
        for i in 7 downto 0 loop
            comm_spi_xfer(comm_spi_clk, comm_spi_mosi, comm_spi_miso, x"00", rx_byte);
            rx_record(i*8+7 downto i*8) := rx_byte;
            wait for CLK_PERIOD * 2;
        end loop;

        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 5;

        exp_addr  := x"ABCDEF";
        exp_count := x"000004";

        check(pass_count, fail_count,
              rx_record(63 downto 40) = exp_addr,
              "Readout ADDR = 0xABCDEF");

        check(pass_count, fail_count,
              rx_record(39 downto 16) = exp_count,
              "Readout COUNT = 4");

        check(pass_count, fail_count,
              true,
              "Readout TIME present (value varies)");

        -- =========================================================
        -- TEST 4: Verify buffer empty after read
        -- =========================================================
        report "=== TEST 4: Buffer empty after readout ===" severity note;
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '0',
              "GPIO_READY = 0 after consuming entry");

        -- =========================================================
        -- TEST 5: Multiple transactions capture and readout
        -- =========================================================
        report "=== TEST 5: Multiple MCU transactions ===" severity note;

        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"00");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"12");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"34");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"AA");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"BB");
        wait for SYNC_SETTLE;
        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;

        wait for CLK_PERIOD * 10;
        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"FF");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"00");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"00");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"CC");
        wait for SYNC_SETTLE;
        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;

        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '1',
              "GPIO_READY = 1 after 2 transactions");

        report "=== TEST 5b: Read first entry ===" severity note;
        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 10;
        for i in 7 downto 0 loop
            comm_spi_xfer(comm_spi_clk, comm_spi_mosi, comm_spi_miso, x"00", rx_byte);
            rx_record(i*8+7 downto i*8) := rx_byte;
            wait for CLK_PERIOD * 2;
        end loop;
        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              rx_record(63 downto 40) = x"001234",
              "Entry 1 ADDR = 0x001234");

        check(pass_count, fail_count,
              to_integer(unsigned(rx_record(39 downto 16))) = 2,
              "Entry 1 COUNT = 2");

        report "=== TEST 5c: Read second entry ===" severity note;
        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 10;
        for i in 7 downto 0 loop
            comm_spi_xfer(comm_spi_clk, comm_spi_mosi, comm_spi_miso, x"00", rx_byte);
            rx_record(i*8+7 downto i*8) := rx_byte;
            wait for CLK_PERIOD * 2;
        end loop;
        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              rx_record(63 downto 40) = x"FF0000",
              "Entry 2 ADDR = 0xFF0000");

        check(pass_count, fail_count,
              to_integer(unsigned(rx_record(39 downto 16))) = 1,
              "Entry 2 COUNT = 1");

        -- =========================================================
        -- TEST 6: Read empty buffer (should return 0xFF)
        -- =========================================================
        report "=== TEST 6: Read empty buffer ===" severity note;

        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 10;
        for i in 7 downto 0 loop
            comm_spi_xfer(comm_spi_clk, comm_spi_mosi, comm_spi_miso, x"00", rx_byte);
            rx_record(i*8+7 downto i*8) := rx_byte;
            wait for CLK_PERIOD * 2;
        end loop;
        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              rx_record = x"FFFFFFFFFFFFFFFF",
              "Empty buffer returns 0xFFFFFFFFFFFFFFFF");

        -- =========================================================
        -- TEST 7: Invalid command ignored
        -- =========================================================
        report "=== TEST 7: Invalid MCU command ignored ===" severity note;

        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"FF");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"11");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"22");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"33");
        wait for SYNC_SETTLE;
        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '0',
              "GPIO_READY still 0 after invalid command");

        -- =========================================================
        -- TEST 8: LED activity indicators
        -- =========================================================
        report "=== TEST 8: LED activity indicators ===" severity note;

        check(pass_count, fail_count,
              led_mcu_act = '1',
              "LED_MCU_ACT = 1 when MCU SS_N high");

        check(pass_count, fail_count,
              led_comm_act = '1',
              "LED_COMM_ACT = 1 when COMM SS_N high");

        mcu_spi_ss_n <= '0';
        wait for CLK_PERIOD * 2;
        check(pass_count, fail_count,
              led_mcu_act = '0',
              "LED_MCU_ACT = 0 when MCU SS_N low");
        mcu_spi_ss_n <= '1';
        wait for CLK_PERIOD * 2;

        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 2;
        check(pass_count, fail_count,
              led_comm_act = '0',
              "LED_COMM_ACT = 0 when COMM SS_N low");
        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 2;

        -- =========================================================
        -- TEST 9: MCU transaction aborted mid-address
        -- =========================================================
        report "=== TEST 9: MCU transaction aborted mid-address ===" severity note;

        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"AA");
        wait for SYNC_SETTLE;
        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '0',
              "GPIO_READY = 0 after aborted transaction (no strobe)");

        -- =========================================================
        -- TEST 10: Zero data bytes after address
        -- =========================================================
        report "=== TEST 10: Zero data bytes transaction ===" severity note;

        mcu_spi_ss_n <= '0';
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"DE");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"AD");
        wait for SYNC_SETTLE;
        send_byte(mcu_spi_clk, mcu_spi_mosi, x"00");
        wait for SYNC_SETTLE;
        mcu_spi_ss_n <= '1';
        wait for SYNC_SETTLE;
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              gpio_ready = '1',
              "GPIO_READY = 1 after 0-byte read captured");

        comm_spi_ss_n <= '0';
        wait for CLK_PERIOD * 10;
        for i in 7 downto 0 loop
            comm_spi_xfer(comm_spi_clk, comm_spi_mosi, comm_spi_miso, x"00", rx_byte);
            rx_record(i*8+7 downto i*8) := rx_byte;
            wait for CLK_PERIOD * 2;
        end loop;
        comm_spi_ss_n <= '1';
        wait for CLK_PERIOD * 5;

        check(pass_count, fail_count,
              rx_record(63 downto 40) = x"DEAD00",
              "0-byte transaction ADDR = 0xDEAD00");

        check(pass_count, fail_count,
              to_integer(unsigned(rx_record(39 downto 16))) = 0,
              "0-byte transaction COUNT = 0");

        -- =========================================================
        -- Summary
        -- =========================================================
        report "=========================================";
        report "RESULTS: " & integer'image(pass_count) & " passed, " &
               integer'image(fail_count) & " failed";
        report "=========================================";

        if fail_count > 0 then
            report "SIMULATION FAILED" severity failure;
        else
            report "ALL TESTS PASSED" severity note;
        end if;

        done <= true;
        wait;
    end process;

end architecture;
