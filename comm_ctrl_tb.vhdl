library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity comm_ctrl_tb is
end entity comm_ctrl_tb;

architecture sim of comm_ctrl_tb is

    constant CLK_PERIOD : time := 10 ns;

    signal clk           : std_logic := '0';
    signal reset_n       : std_logic := '1';

    signal read_addr     : std_logic_vector(23 downto 0) := (others => '0');
    signal read_count    : std_logic_vector(23 downto 0) := (others => '0');
    signal read_time     : std_logic_vector(15 downto 0) := (others => '0');
    signal read_ready    : std_logic := '0';
    signal read_lost     : std_logic := '0';
    signal read_next     : std_logic;

    signal st_sink_data  : std_logic_vector(7 downto 0);
    signal st_sink_valid : std_logic;
    signal st_sink_ready : std_logic := '1';

    signal st_source_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal st_source_valid : std_logic := '0';
    signal st_source_ready : std_logic;

    signal spi_ss_n      : std_logic := '1';

    signal replace_ix    : std_logic_vector(7 downto 0);
    signal replace_addr  : std_logic_vector(23 downto 0);
    signal replace_data  : std_logic_vector(63 downto 0);
    signal replace_store : std_logic;
    signal replace_clear : std_logic;

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;
    signal sim_done   : boolean := false;

    procedure check(
        signal   p : inout integer;
        signal   f : inOut integer;
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

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else clk;

    uut: entity work.COMM_CTRL
        port map (
            CLK             => clk,
            RESET_N         => reset_n,
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
            SPI_SS_N        => spi_ss_n,
            REPLACE_IX      => replace_ix,
            REPLACE_ADDR    => replace_addr,
            REPLACE_DATA    => replace_data,
            REPLACE_STORE   => replace_store,
            REPLACE_CLEAR   => replace_clear
        );

    stim: process

        procedure do_reset is
        begin
            reset_n <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            reset_n <= '1';
            wait until rising_edge(clk);
        end procedure;

        procedure spi_select is
        begin
            spi_ss_n <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure;

        procedure spi_deselect is
        begin
            spi_ss_n <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure;

        procedure send_byte(data : std_logic_vector(7 downto 0)) is
        begin
            st_source_data <= data;
            st_source_valid <= '1';
            wait until rising_edge(clk);
            st_source_valid <= '0';
        end procedure;

        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

    begin
        -------------------------------------------------------
        -- TEST 1: Reset behavior
        -------------------------------------------------------
        report "=== TEST 1: Reset ===" severity note;
        do_reset;

        check(pass_count, fail_count,
              st_source_ready = '1',
              "ST_SOURCE_READY always 1");

        check(pass_count, fail_count,
              replace_store = '0',
              "REPLACE_STORE = 0 after reset");

        check(pass_count, fail_count,
              replace_clear = '0',
              "REPLACE_CLEAR = 0 after reset");

        -------------------------------------------------------
        -- TEST 2: Command 1 (LATCH) with READ_READY = 1
        -------------------------------------------------------
        report "=== TEST 2: Command 1 (LATCH) with data ready ===" severity note;
        do_reset;

        read_addr  <= x"AABBCC";
        read_count <= x"112233";
        read_time  <= x"4455";
        read_ready <= '1';

        spi_select;

        check(pass_count, fail_count,
              st_sink_valid = '1',
              "S_CMD: ST_SINK_VALID = 1");

        check(pass_count, fail_count,
              st_sink_data = x"CC",
              "S_CMD sends 0xCC response");

        send_byte(x"01");
        wait_cycles(1);

        check(pass_count, fail_count,
              read_next = '1',
              "READ_NEXT pulsed in S_LATCH");

        check(pass_count, fail_count,
              st_sink_data = x"AA",
              "S_LATCH sends READ_ADDR high byte (0xAA)");

        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_valid = '1',
              "S_SEND: ST_SINK_VALID = 1");

        check(pass_count, fail_count,
              st_sink_data = x"AA",
              "S_SEND byte 0: 0xAA (READ_ADDR high)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"BB",
              "S_SEND byte 1: 0xBB (READ_ADDR mid)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"CC",
              "S_SEND byte 2: 0xCC (READ_ADDR low)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"11",
              "S_SEND byte 3: 0x11 (READ_COUNT high)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"22",
              "S_SEND byte 4: 0x22 (READ_COUNT mid)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"33",
              "S_SEND byte 5: 0x33 (READ_COUNT low)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"44",
              "S_SEND byte 6: 0x44 (READ_TIME high)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"55",
              "S_SEND byte 7: 0x55 (READ_TIME low)");

        wait_cycles(1);
        check(pass_count, fail_count,
              st_sink_data = x"EE",
              "S_INVALID: sends 0xEE after all bytes");

        spi_deselect;

        -------------------------------------------------------
        -- TEST 3: Command 1 (LATCH) with READ_READY = 0
        -------------------------------------------------------
        report "=== TEST 3: Command 1 (LATCH) with no data ready ===" severity note;
        do_reset;

        read_ready <= '0';

        spi_select;
        send_byte(x"01");
        wait_cycles(1);

        check(pass_count, fail_count,
              read_next = '0',
              "READ_NEXT not pulsed when READ_READY = 0");

        check(pass_count, fail_count,
              st_sink_data = x"FF",
              "S_LATCH sends 0xFF when not ready");

        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"FF",
              "S_SEND byte 0: 0xFF when not ready");

        spi_deselect;

        -------------------------------------------------------
        -- TEST 4: Command 2 (REPLACE) - store replacement entry
        -------------------------------------------------------
        report "=== TEST 4: Command 2 (REPLACE) ===" severity note;
        do_reset;

        spi_select;

        check(pass_count, fail_count,
              st_sink_data = x"CC",
              "S_CMD sends 0xCC");

        send_byte(x"02");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"00",
              "S_REPLACE byte_cnt=0 response");

        send_byte(x"07");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"01",
              "S_REPLACE byte_cnt=1 response");

        send_byte(x"12");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"02",
              "S_REPLACE byte_cnt=2 response");

        send_byte(x"34");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"03",
              "S_REPLACE byte_cnt=3 response");

        send_byte(x"56");
        wait_cycles(1);
        send_byte(x"AA");
        wait_cycles(1);
        send_byte(x"BB");
        wait_cycles(1);
        send_byte(x"CC");
        wait_cycles(1);
        send_byte(x"DD");
        wait_cycles(1);
        send_byte(x"11");
        wait_cycles(1);
        send_byte(x"22");
        wait_cycles(1);
        send_byte(x"33");
        wait_cycles(1);
        send_byte(x"44");
        wait_cycles(1);

        check(pass_count, fail_count,
              replace_store = '1',
              "REPLACE_STORE = 1 after 12 bytes");

        check(pass_count, fail_count,
              replace_ix = x"07",
              "REPLACE_IX = 0x07");

        check(pass_count, fail_count,
              replace_addr = x"123456",
              "REPLACE_ADDR = 0x123456");

        check(pass_count, fail_count,
              replace_data = x"AABBCCDD11223344",
              "REPLACE_DATA = 0xAABBCCDD11223344");

        spi_deselect;

        check(pass_count, fail_count,
              replace_store = '0',
              "REPLACE_STORE = 0 after deselect");

        -------------------------------------------------------
        -- TEST 5: Command 3 (CLEAR)
        -------------------------------------------------------
        report "=== TEST 5: Command 3 (CLEAR) ===" severity note;
        do_reset;

        spi_select;

        check(pass_count, fail_count,
              st_sink_data = x"CC",
              "S_CMD sends 0xCC for command 3");

        send_byte(x"03");
        wait_cycles(1);

        check(pass_count, fail_count,
              replace_clear = '1',
              "REPLACE_CLEAR = 1 in S_CLEAR state");

        check(pass_count, fail_count,
              st_sink_data = x"AC",
              "S_CLEAR sends 0xAC response");

        send_byte(x"00");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"EE",
              "S_INVALID sends 0xEE after extra byte");

        spi_deselect;

        check(pass_count, fail_count,
              replace_clear = '0',
              "REPLACE_CLEAR = 0 after deselect");

        -------------------------------------------------------
        -- TEST 6: Invalid command (0x00)
        -------------------------------------------------------
        report "=== TEST 6: Invalid command (0x00) ===" severity note;
        do_reset;

        spi_select;
        send_byte(x"00");
        wait_cycles(1);

        check(pass_count, fail_count,
              st_sink_data = x"EE",
              "Invalid command goes to S_INVALID (0xEE)");

        spi_deselect;

        -------------------------------------------------------
        -- TEST 7: SS_N deselect resets state mid-transaction
        -------------------------------------------------------
        report "=== TEST 7: SS_N deselect resets state ===" severity note;
        do_reset;

        read_addr  <= x"FEDCBA";
        read_count <= x"987654";
        read_time  <= x"3210";
        read_ready <= '1';

        spi_select;
        send_byte(x"01");
        wait_cycles(3);

        spi_deselect;
        spi_select;

        check(pass_count, fail_count,
              st_sink_data = x"CC",
              "State reset to S_CMD after deselect/reselect");

        spi_deselect;

        -------------------------------------------------------
        -- TEST 8: ST_SINK_READY flow control in S_SEND
        -------------------------------------------------------
        report "=== TEST 8: ST_SINK_READY flow control ===" severity note;
        do_reset;

        read_addr  <= x"FEDCBA";
        read_count <= x"987654";
        read_time  <= x"3210";
        read_ready <= '1';
        st_sink_ready <= '0';

        spi_select;
        send_byte(x"01");
        wait_cycles(2);

        check(pass_count, fail_count,
              st_sink_data = x"FE",
              "S_SEND byte 0 is 0xFE");

        wait_cycles(3);

        check(pass_count, fail_count,
              st_sink_data = x"FE",
              "Byte counter paused at byte 0 when ST_SINK_READY = 0");

        st_sink_ready <= '1';
        wait_cycles(2);

        check(pass_count, fail_count,
              st_sink_data = x"DC",
              "Byte counter advances to byte 1 when ST_SINK_READY = 1");

        spi_deselect;

        -------------------------------------------------------
        -- Summary
        -------------------------------------------------------
        report "=========================================" severity note;
        report "RESULTS: " & integer'image(pass_count) &
               " passed, "  & integer'image(fail_count) &
               " failed" severity note;
        report "=========================================" severity note;

        if fail_count > 0 then
            report "SIMULATION FAILED" severity failure;
        else
            report "SIMULATION PASSED" severity note;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture sim;
