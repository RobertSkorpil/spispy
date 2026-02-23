library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity bufctrl_tb is
end entity bufctrl_tb;

architecture sim of bufctrl_tb is

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- DUT signals
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '0';

    signal cap_addr     : std_logic_vector(23 downto 0) := (others => '0');
    signal cap_count    : std_logic_vector(23 downto 0) := (others => '0');
    signal cap_strobe   : std_logic := '0';
    signal cap_time     : std_logic_vector(15 downto 0) := (others => '0');

    signal read_addr    : std_logic_vector(23 downto 0);
    signal read_count   : std_logic_vector(23 downto 0);
    signal read_time    : std_logic_vector(15 downto 0);
    signal read_ready   : std_logic;
    signal read_lost    : std_logic;
    signal read_next    : std_logic := '0';

    signal mem_addr_in  : std_logic_vector(8 downto 0);
    signal mem_data_in  : std_logic_vector(63 downto 0);
    signal mem_addr_out : std_logic_vector(8 downto 0);
    signal mem_data_out : std_logic_vector(63 downto 0);
    signal mem_write    : std_logic;

    -- Simple dual-port RAM model (512 x 64 bit)
    type ram_t is array(0 to 511) of std_logic_vector(63 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    -- Test bookkeeping
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    -- Helper: report check result
    procedure check(
        signal   p : inout integer;
        signal   f : inout integer;
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

    ----------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ----------------------------------------------------------------
    -- DUT instantiation
    ----------------------------------------------------------------
    uut: entity work.bufctrl
        port map (
            RESET        => reset,
            CLK          => clk,
            CAP_ADDR     => cap_addr,
            CAP_COUNT    => cap_count,
            CAP_STROBE   => cap_strobe,
            CAP_TIME     => cap_time,
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

    ----------------------------------------------------------------
    -- RAM model — write port (synchronous), read port (async)
    ----------------------------------------------------------------
    ram_proc: process(clk)
    begin
        if rising_edge(clk) then
            if mem_write = '1' then
                ram(to_integer(unsigned(mem_addr_out))) <= mem_data_out;
            end if;
        end if;
    end process;

    -- Asynchronous read (matches how the DUT drives MEM_ADDR_IN combinationally)
    mem_data_in <= ram(to_integer(unsigned(mem_addr_in)));

    ----------------------------------------------------------------
    -- Stimulus process
    ----------------------------------------------------------------
    stim: process
        -- Helper: pulse CAP_STROBE for one clock cycle
        procedure capture(
            addr  : in std_logic_vector(23 downto 0);
            count : in std_logic_vector(23 downto 0);
            tval  : in std_logic_vector(15 downto 0)
        ) is
        begin
            cap_addr   <= addr;
            cap_count  <= count;
            cap_time   <= tval;
            cap_strobe <= '1';
            wait until rising_edge(clk);
            cap_strobe <= '0';
            -- Wait one more cycle for the write to complete and
            -- the synchronous pointers to update
            wait until rising_edge(clk);
        end procedure;

        -- Helper: pulse READ_NEXT for one clock cycle
        procedure consume is
        begin
            read_next <= '1';
            wait until rising_edge(clk);
            read_next <= '0';
            -- Wait one more cycle for pointers to update
            wait until rising_edge(clk);
        end procedure;

        variable i : integer;

    begin
        -------------------------------------------------------
        -- TEST 1: Reset
        -------------------------------------------------------
        report "=== TEST 1: Reset ===" severity note;
        reset <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        reset <= '0';
        wait until rising_edge(clk);

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY = 0 after reset");

        check(pass_count, fail_count,
              read_lost = '0',
              "READ_LOST = 0 after reset");

        -------------------------------------------------------
        -- TEST 2: Single capture and read-back
        -------------------------------------------------------
        report "=== TEST 2: Single capture and read-back ===" severity note;

        capture(x"ABCDEF", x"000004", x"04D2");  -- addr=0xABCDEF, count=4, time=1234

        check(pass_count, fail_count,
              read_ready = '1',
              "READ_READY = 1 after capture");

        -- The read port should now present the captured data
        wait for 1 ns;  -- allow combinational settle
        check(pass_count, fail_count,
              read_addr = x"ABCDEF",
              "READ_ADDR expected 0xABCDEF, got 0x" &
              integer'image(to_integer(unsigned(read_addr))));

        check(pass_count, fail_count,
              to_integer(unsigned(read_count)) = 4,
              "READ_COUNT expected 4, got " &
              integer'image(to_integer(unsigned(read_count))));

        check(pass_count, fail_count,
              to_integer(unsigned(read_time)) = 1234,
              "READ_TIME expected 1234, got " &
              integer'image(to_integer(unsigned(read_time))));

        -- Consume the entry
        consume;

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY expected 0 after consuming entry");

        -------------------------------------------------------
        -- TEST 3: Multiple captures, then sequential reads
        -------------------------------------------------------
        report "=== TEST 3: Multiple captures, then sequential reads ===" severity note;

        capture(x"110000", x"000010", x"0001");
        capture(x"220000", x"000020", x"0002");
        capture(x"330000", x"000030", x"0003");

        check(pass_count, fail_count,
              read_ready = '1',
              "READ_READY = 1 after 3 captures");

        -- Read entry 1
        wait for 1 ns;
        check(pass_count, fail_count,
              read_addr = x"110000",
              "Entry 1 ADDR expected 0x110000, got 0x" &
              integer'image(to_integer(unsigned(read_addr))));
        consume;

        -- Read entry 2
        wait for 1 ns;
        check(pass_count, fail_count,
              read_addr = x"220000",
              "Entry 2 ADDR expected 0x220000, got 0x" &
              integer'image(to_integer(unsigned(read_addr))));
        consume;

        -- Read entry 3
        wait for 1 ns;
        check(pass_count, fail_count,
              read_addr = x"330000",
              "Entry 3 ADDR expected 0x330000, got 0x" &
              integer'image(to_integer(unsigned(read_addr))));
        consume;

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY expected 0 after reading all 3 entries");

        -------------------------------------------------------
        -- TEST 4: Read-next on empty buffer
        -------------------------------------------------------
        report "=== TEST 4: Read-next on empty buffer ===" severity note;

        -- Buffer should be empty; pulsing read_next should be harmless
        consume;

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY should remain 0 on empty read");

        -------------------------------------------------------
        -- TEST 5: Overflow detection
        -------------------------------------------------------
        report "=== TEST 5: Overflow detection ===" severity note;

        -- Fill all 512 slots (pointers are 9-bit, so 512 entries)
        -- write_ptr wraps to meet read_ptr => overflow on 512th write
        for j in 0 to 511 loop
            cap_addr   <= std_logic_vector(to_unsigned(j, 24));
            cap_count  <= x"000001";
            cap_time   <= x"FFFF";
            cap_strobe <= '1';
            wait until rising_edge(clk);
            cap_strobe <= '0';
            wait until rising_edge(clk);
        end loop;

        check(pass_count, fail_count,
              read_lost = '1',
              "READ_LOST expected 1 on overflow");

        -------------------------------------------------------
        -- TEST 6: Overflow clears on read-next
        -------------------------------------------------------
        report "=== TEST 6: Overflow clears on read-next ===" severity note;

        consume;

        check(pass_count, fail_count,
              read_lost = '0',
              "READ_LOST = 0 after read-next");

        -------------------------------------------------------
        -- TEST 7: Interleaved capture and read
        -------------------------------------------------------
        report "=== TEST 7: Interleaved capture and read ===" severity note;

        -- Drain the buffer from test 5 first
        while read_ready = '1' loop
            consume;
        end loop;

        -- Capture, read, capture, read
        capture(x"AA0000", x"00000A", x"000A");
        wait for 1 ns;
        check(pass_count, fail_count,
              read_addr = x"AA0000",
              "Interleaved entry 1 ADDR wrong");
        consume;

        capture(x"BB0000", x"00000B", x"000B");
        wait for 1 ns;
        check(pass_count, fail_count,
              read_addr = x"BB0000",
              "Interleaved entry 2 ADDR wrong");
        check(pass_count, fail_count,
              to_integer(unsigned(read_count)) = 11,
              "Interleaved entry 2 COUNT wrong");
        consume;

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY expected 0 after interleaved drain");

        -------------------------------------------------------
        -- TEST 8: Reset clears mid-operation
        -------------------------------------------------------
        report "=== TEST 8: Reset clears mid-operation ===" severity note;

        capture(x"CC0000", x"0000CC", x"00CC");
        capture(x"DD0000", x"0000DD", x"00DD");

        -- Reset while entries are pending
        reset <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        reset <= '0';
        wait until rising_edge(clk);

        check(pass_count, fail_count,
              read_ready = '0',
              "READ_READY = 0 after mid-operation reset");

        check(pass_count, fail_count,
              read_lost = '0',
              "READ_LOST = 0 after mid-operation reset");

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

        wait;
    end process;

end architecture sim;
