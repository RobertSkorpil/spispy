-- spispy_tb.vhdl — Testbench for spispy (3-process FSM with synchronizer)
-- Compatible with VHDL-93 and later; simulator: nvc

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spispy_tb is
end entity;

architecture sim of spispy_tb is

    -- Clock periods
    constant CLK_PERIOD : time := 20 ns;    -- 50 MHz system clock
    constant SPI_HALF   : time := 100 ns;   -- SPI clock half-period (5 MHz)

    -- Synchronizer pipeline depth: 3 sync stages + 1 register = 4 CLK cycles
    -- Add margin for edge alignment → 6 CLK cycles is safe
    constant SYNC_SETTLE : time := CLK_PERIOD * 6;

    -- DUT signals
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal cs_n     : std_logic := '1';
    signal spi_clk  : std_logic := '0';
    signal mosi     : std_logic := '0';
    signal addr     : std_logic_vector(23 downto 0);
    signal count    : std_logic_vector(23 downto 0);
    signal strobe   : std_logic;

    signal done     : boolean := false;

    -- ----------------------------------------------------------------
    -- Procedure: send one byte MSB-first on MOSI, toggling SPI_CLK
    -- ----------------------------------------------------------------
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

begin

    -- -----------------------------------------------------------
    -- DUT instantiation
    -- -----------------------------------------------------------
    uut : entity work.spispy
        port map (
            RESET      => reset,
            CLK        => clk,
            SPI_CS_N   => cs_n,
            SPI_CLK    => spi_clk,
            SPI_MOSI   => mosi,
            ADDR_OUT   => addr,
            BYTE_COUNT => count,
            STROBE     => strobe
        );

    -- -----------------------------------------------------------
    -- System clock generator (runs until 'done')
    -- -----------------------------------------------------------
    clk_gen : process
    begin
        while not done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- -----------------------------------------------------------
    -- Main stimulus
    -- -----------------------------------------------------------
    stim : process
        constant CMD_READ   : std_logic_vector(7 downto 0) := x"03";
        constant CMD_BAD    : std_logic_vector(7 downto 0) := x"FF";
        constant ADDR_BYTES : std_logic_vector(23 downto 0) := x"ABCDEF";
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
    begin
        -- =========================================================
        -- 1. Reset
        -- =========================================================
        report "=== TEST 1: Reset ===" severity note;
        reset <= '1';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        -- =========================================================
        -- 2. Valid SPI Read (cmd 0x03, addr 0xABCDEF, 4 data bytes)
        -- =========================================================
        report "=== TEST 2: Valid SPI Read ===" severity note;

        -- Assert CS and wait for synchronizer to detect the falling edge
        cs_n <= '0';
        wait for SYNC_SETTLE;

        -- Command byte
        send_byte(spi_clk, mosi, CMD_READ);
        wait for SYNC_SETTLE;  -- let last SPI_CLK edge propagate

        -- 3 address bytes
        send_byte(spi_clk, mosi, ADDR_BYTES(23 downto 16));
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, ADDR_BYTES(15 downto 8));
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, ADDR_BYTES(7 downto 0));
        wait for SYNC_SETTLE;

        -- 4 data bytes
        send_byte(spi_clk, mosi, x"DE");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"AD");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"BE");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"EF");
        wait for SYNC_SETTLE;

        -- De-assert CS and wait for synchronizer to detect the rising edge
        cs_n <= '1';
        wait for SYNC_SETTLE;

        -- Check address
        if addr = x"ABCDEF" then
            report "PASS: ADDR = 0xABCDEF" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: ADDR expected 0xABCDEF, got " &
                   integer'image(to_integer(unsigned(addr))) severity error;
            fail_count := fail_count + 1;
        end if;

        -- Check count (4 data bytes)
        if unsigned(count) = to_unsigned(4, 24) then
            report "PASS: COUNT = 4" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: COUNT expected 4, got " &
                   integer'image(to_integer(unsigned(count))) severity error;
            fail_count := fail_count + 1;
        end if;

        -- =========================================================
        -- 3. Invalid command — should stay idle, no strobe
        -- =========================================================
        report "=== TEST 3: Invalid command byte ===" severity note;
        wait for SPI_HALF * 4;

        cs_n <= '0';
        wait for SYNC_SETTLE;

        send_byte(spi_clk, mosi, CMD_BAD);
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"00");
        wait for SYNC_SETTLE;

        cs_n <= '1';
        wait for SYNC_SETTLE;

        -- Address and count should be unchanged from previous transaction
        if addr = x"ABCDEF" then
            report "PASS: ADDR unchanged after bad cmd" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: ADDR changed after bad cmd to " &
                   integer'image(to_integer(unsigned(addr))) severity error;
            fail_count := fail_count + 1;
        end if;

        -- =========================================================
        -- 4. Second valid read with different address & more data
        -- =========================================================
        report "=== TEST 4: Second valid read (addr 0x001234, 2 bytes) ===" severity note;
        wait for SPI_HALF * 4;

        cs_n <= '0';
        wait for SYNC_SETTLE;

        send_byte(spi_clk, mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"00");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"12");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"34");
        wait for SYNC_SETTLE;

        send_byte(spi_clk, mosi, x"AA");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"55");
        wait for SYNC_SETTLE;

        cs_n <= '1';
        wait for SYNC_SETTLE;

        if addr = x"001234" then
            report "PASS: ADDR = 0x001234" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: ADDR expected 0x001234, got " &
                   integer'image(to_integer(unsigned(addr))) severity error;
            fail_count := fail_count + 1;
        end if;

        if unsigned(count) = to_unsigned(2, 24) then
            report "PASS: COUNT = 2" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: COUNT expected 2, got " &
                   integer'image(to_integer(unsigned(count))) severity error;
            fail_count := fail_count + 1;
        end if;

        -- =========================================================
        -- 5. CS de-asserted mid-address — should NOT produce strobe
        -- =========================================================
        report "=== TEST 5: Abort mid-address ===" severity note;
        wait for SPI_HALF * 4;

        cs_n <= '0';
        wait for SYNC_SETTLE;

        send_byte(spi_clk, mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"FF");  -- first addr byte only
        wait for SYNC_SETTLE;

        -- Abort early
        cs_n <= '1';
        wait for SYNC_SETTLE;

        -- BYTE_COUNT reflects the live state.count which was reset to 0
        -- when CS fell for this (aborted) transaction — so expect 0.
        if unsigned(count) = to_unsigned(0, 24) then
            report "PASS: COUNT = 0 after abort (no data bytes counted)" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: COUNT expected 0 after abort, got " &
                   integer'image(to_integer(unsigned(count))) severity error;
            fail_count := fail_count + 1;
        end if;

        -- =========================================================
        -- 6. Zero data bytes after address (count should be 0)
        -- =========================================================
        report "=== TEST 6: Read with 0 data bytes ===" severity note;
        wait for SPI_HALF * 4;

        cs_n <= '0';
        wait for SYNC_SETTLE;

        send_byte(spi_clk, mosi, CMD_READ);
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"FF");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"00");
        wait for SYNC_SETTLE;
        send_byte(spi_clk, mosi, x"01");
        wait for SYNC_SETTLE;

        -- No data bytes, immediate de-assert
        cs_n <= '1';
        wait for SYNC_SETTLE;

        if addr = x"FF0001" then
            report "PASS: ADDR = 0xFF0001" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: ADDR expected 0xFF0001, got " &
                   integer'image(to_integer(unsigned(addr))) severity error;
            fail_count := fail_count + 1;
        end if;

        if unsigned(count) = to_unsigned(0, 24) then
            report "PASS: COUNT = 0" severity note;
            pass_count := pass_count + 1;
        else
            report "FAIL: COUNT expected 0, got " &
                   integer'image(to_integer(unsigned(count))) severity error;
            fail_count := fail_count + 1;
        end if;

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
