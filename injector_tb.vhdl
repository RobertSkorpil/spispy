-- injector_tb.vhdl - Comprehensive Testbench for INJECTOR module
-- Tests programming, initialization, address matching, and re-programming
-- Block RAM model: registered inputs, combinatorial output

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity injector_tb is
end entity;

architecture sim of injector_tb is

    constant CLK_PERIOD  : time := 20 ns;  -- 50 MHz
    constant NUM_ENTRIES : integer := 1;   -- minimal for debugging

    -- DUT signals
    signal clk           : std_logic := '0';
    signal reset_n       : std_logic := '0';

    signal prog_en       : std_logic := '0';
    signal prog_data     : std_logic_vector(7 downto 0) := (others => '0');
    signal prog_strobe   : std_logic := '0';

    signal match_addr    : std_logic_vector(23 downto 0) := (others => '0');
    signal match_offset  : std_logic_vector(23 downto 0) := (others => '0');
    signal match_valid   : std_logic;
    signal match_data    : std_logic_vector(7 downto 0);

    signal mem_addr      : std_logic_vector(15 downto 0);
    signal mem_rden      : std_logic;
    signal mem_wren      : std_logic;
    signal mem_data_out  : std_logic_vector(7 downto 0);
    signal mem_data_in   : std_logic_vector(7 downto 0) := (others => '0');

    signal armed         : std_logic;

    signal done          : boolean := false;

    -- ----------------------------------------------------------------
    -- Block RAM model: registered inputs, combinatorial output
    -- ----------------------------------------------------------------
    type ram_t is array(0 to 65535) of std_logic_vector(7 downto 0);
    signal ram : ram_t := (others => (others => '0'));
    signal mem_addr_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Each RANGE_REGISTER entry is 8 bytes (shifted MSB-first):
    --   Byte 0: stored(1) & reserved(6..0)
    --   Byte 1: addr(23..16)
    --   Byte 2: addr(15..8)
    --   Byte 3: addr(7..0)
    --   Byte 4: length(15..8)
    --   Byte 5: length(7..0)
    --   Byte 6: data_address(15..8)
    --   Byte 7: data_address(7..0)
    --
    -- Entries are shifted through a chain of NUM_ENTRIES registers,
    -- so entry 0 in memory ends up in register NUM_ENTRIES-1 after
    -- all bytes have been shifted through.

    -- Helper: pack a register entry into 8 bytes in RAM starting at base_addr
    procedure pack_entry(
        signal   mem  : inout ram_t;
        constant base : in integer;
        constant is_stored    : in std_logic;
        constant addr_val     : in unsigned;       -- 24 bits
        constant length_val   : in unsigned;       -- 16 bits
        constant data_addr    : in unsigned         -- 16 bits
    ) is
    begin
        mem(base + 0) <= is_stored & "0000000";
        mem(base + 1) <= std_logic_vector(addr_val(23 downto 16));
        mem(base + 2) <= std_logic_vector(addr_val(15 downto 8));
        mem(base + 3) <= std_logic_vector(addr_val(7 downto 0));
        mem(base + 4) <= std_logic_vector(length_val(15 downto 8));
        mem(base + 5) <= std_logic_vector(length_val(7 downto 0));
        mem(base + 6) <= std_logic_vector(data_addr(15 downto 8));
        mem(base + 7) <= std_logic_vector(data_addr(7 downto 0));
    end procedure;

begin

    -- ---------------------------------------------------------------
    -- Clock generation
    -- ---------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    -- ---------------------------------------------------------------
    -- DUT instantiation
    -- ---------------------------------------------------------------
    DUT: entity work.INJECTOR
        generic map (
            NUM_ENTRIES => NUM_ENTRIES
        )
        port map (
            RESET_N      => reset_n,
            CLK          => clk,
            PROG_EN      => prog_en,
            PROG_DATA    => prog_data,
            PROG_STROBE  => prog_strobe,
            MATCH_ADDR   => match_addr,
            MATCH_OFFSET => match_offset,
            MATCH_VALID  => match_valid,
            MATCH_DATA   => match_data,
            MEM_ADDR     => mem_addr,
            MEM_RDEN     => mem_rden,
            MEM_WREN     => mem_wren,
            MEM_DATA_OUT => mem_data_out,
            MEM_DATA_IN  => mem_data_in,
            ARMED        => armed
        );
    
    -- Monitor to debug signals during ready state
    process
    begin
        wait until armed = '1';
        wait for CLK_PERIOD * 10;
        report "MONITOR: After ARMED, testing match_addr=0x001000" severity note;
        wait for CLK_PERIOD * 20;
        report "MONITOR: match_valid=" & std_logic'image(match_valid) &
               ", mem_addr=" & to_hstring(unsigned(mem_addr)) severity note;
        wait;
    end process;

    -- ---------------------------------------------------------------
    -- Block RAM model: registered inputs, combinatorial output
    -- ---------------------------------------------------------------
    MEM_PROC: process(clk)
    begin
        if rising_edge(clk) then
            -- Register the input address
            mem_addr_reg <= mem_addr;
            
            -- Write (registered input)
            if mem_wren = '1' then
                ram(to_integer(unsigned(mem_addr))) <= mem_data_out;
            end if;
        end if;
    end process;
    
    -- Combinatorial read output (using registered address)
    mem_data_in <= ram(to_integer(unsigned(mem_addr_reg)));

    -- ---------------------------------------------------------------
    -- Stimulus
    -- ---------------------------------------------------------------
    STIM: process
        -- Helper: program a single byte via the programming interface
        procedure prog_byte(constant d : in std_logic_vector(7 downto 0)) is
        begin
            prog_data <= d;
            prog_strobe <= '1';
            wait until rising_edge(clk);
            prog_strobe <= '0';
            wait until rising_edge(clk);
        end procedure;
    begin
        -- ============================================================
        -- 1. Reset
        -- ============================================================
        report "=== TEST: Reset ===" severity note;
        reset_n <= '0';
        wait for CLK_PERIOD * 5;
        reset_n <= '1';
        wait until rising_edge(clk);

        -- ============================================================
        -- 2. Program entries into memory via PROG interface
        -- ============================================================
        -- We'll program 2 active entries + 1 empty terminator.
        --
        -- Entry 0 (will end up in register 3 after init shift):
        --   stored=1, addr=0x001000, length=0x0100, data_addr=0x0200
        --
        -- Entry 1 (will end up in register 2 after init shift):
        --   stored=1, addr=0x002000, length=0x0080, data_addr=0x0400
        --
        -- Entry 2 (terminator, stored=0):
        --   stored=0, all zeros
        --
        -- Entry 3 (terminator, stored=0):
        --   stored=0, all zeros
        report "=== TEST: Programming entries ===" severity note;
        prog_en <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Entry 0: stored=1, addr=0x001000, length=0x0100, data_addr=0x0200
        prog_byte(x"80");  -- stored=1, reserved=0
        prog_byte(x"00");  -- addr[23:16]
        prog_byte(x"10");  -- addr[15:8]
        prog_byte(x"00");  -- addr[7:0]
        prog_byte(x"01");  -- length[15:8]
        prog_byte(x"00");  -- length[7:0]
        prog_byte(x"02");  -- data_addr[15:8]
        prog_byte(x"00");  -- data_addr[7:0]

        -- Terminator: stored=0
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");
        prog_byte(x"00");

        -- Also write some payload data at data addresses for readback test
        -- At data_addr 0x0200: write 0xAA
        -- At data_addr 0x0201: write 0xBB
        -- We need to set prog_address manually — but the prog interface
        -- auto-increments. We already wrote 32 bytes (addresses 0..31).
        -- Let's write padding up to address 0x0200.
        -- Actually, let's finish programming and write payload via a second
        -- programming session.

        prog_en <= '0';
        wait until rising_edge(clk);

        -- Second programming session to write payload data at specific addresses.
        -- We'll program from address 0 again, writing 0x0200 + a few bytes.
        -- This is wasteful but simple for the test. Let's instead just
        -- directly load the RAM array for payload data.

        -- Direct memory initialization for payload data (not via DUT)
        ram(16#0200#) <= x"AA";
        ram(16#0201#) <= x"BB";
        ram(16#0202#) <= x"CC";
        ram(16#0400#) <= x"DD";
        ram(16#0401#) <= x"EE";

        wait until rising_edge(clk);

        -- ============================================================
        -- 3. Initialization: let the FSM shift entries from memory
        -- ============================================================
        -- After PROG_EN goes low, the FSM goes to ST_PREINIT then ST_INIT.
        -- During ST_INIT, shift_en=1 and it reads memory sequentially.
        -- It terminates when it reads a byte with bit 7 = 0 at address 0x00
        -- (after prog_address_QQ wraps/settles to 0x00).
        report "=== TEST: Initialization ===" severity note;

        -- Wait for the state machine to reach ST_READY
        wait until armed = '1' for 200 us;
        assert armed = '1'
            report "FAIL: INJECTOR did not become armed within timeout"
            severity error;

        if armed = '1' then
            report "PASS: INJECTOR armed after initialization" severity note;
        end if;

        wait for CLK_PERIOD * 5;
        
        -- Debug: check what was loaded into memory
        report "DEBUG: Memory dump from 0x00 to 0x27 (40 bytes):" severity note;
        for i in 0 to 39 loop
            report "  mem[" & integer'image(i) & "] = 0x" & to_hstring(unsigned(ram(i))) severity note;
        end loop;
        
        -- Debug: Let's manually check by setting addresses and seeing what happens
        report "DEBUG: Testing address 0x001000 directly..." severity note;
        match_addr <= x"001000";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 1;
        report "DEBUG: After 1 cycle - match_valid=" & std_logic'image(match_valid) severity note;
        wait for CLK_PERIOD * 1;
        report "DEBUG: After 2 cycles - match_valid=" & std_logic'image(match_valid) & 
               " mem_addr=" & to_hstring(unsigned(mem_addr)) severity note;
        wait for CLK_PERIOD * 1;
        report "DEBUG: After 3 cycles - match_valid=" & std_logic'image(match_valid) &
               " mem_addr=" & to_hstring(unsigned(mem_addr)) severity note;

        -- ============================================================
        -- 4. Test address matching — Entry 0
        -- ============================================================
        -- Entry 0: addr=0x001000, length=0x0100, data_addr=0x0200
        -- Query: match_addr=0x001000, offset=0x000000
        -- Expected: match_valid=1, mem reads from 0x0200, match_data=0xAA
        report "=== TEST: Match entry 0 at base address ===" severity note;
        match_addr   <= x"001000";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;  -- allow combinational + memory latency

        if match_valid = '1' then
            report "PASS: match_valid asserted for addr 0x001000" severity note;
        else
            report "FAIL: match_valid not asserted for addr 0x001000, mem_addr=0x" & 
                   to_hstring(unsigned(mem_addr)) & ", armed=" & std_logic'image(armed) severity error;
        end if;

        -- Check data (need to wait for memory read latency)
        wait for CLK_PERIOD * 2;
        report "  match_data = 0x" & to_hstring(unsigned(match_data)) & 
               ", mem_addr=0x" & to_hstring(unsigned(mem_addr)) severity note;

        -- ============================================================
        -- 5. Test address matching — Entry 0, offset +1
        -- ============================================================
        report "=== TEST: Match entry 0 at offset +1 ===" severity note;
        match_addr   <= x"001001";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '1' then
            report "PASS: match_valid asserted for addr 0x001001" severity note;
        else
            report "FAIL: match_valid not asserted for addr 0x001001" severity error;
        end if;

        wait for CLK_PERIOD * 2;
        report "  match_data = 0x" & to_hstring(unsigned(match_data)) severity note;

        -- ============================================================
        -- 6. Test address matching — Entry 1
        -- ============================================================
        -- Entry 1: addr=0x002000, length=0x0080, data_addr=0x0400
        report "=== TEST: Match entry 1 at base address ===" severity note;
        match_addr   <= x"002000";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '1' then
            report "PASS: match_valid asserted for addr 0x002000" severity note;
        else
            report "FAIL: match_valid not asserted for addr 0x002000" severity error;
        end if;

        wait for CLK_PERIOD * 2;
        report "  match_data = 0x" & to_hstring(unsigned(match_data)) severity note;

        -- ============================================================
        -- 7. Test address NO match (outside any range)
        -- ============================================================
        report "=== TEST: No match for address 0x003000 ===" severity note;
        match_addr   <= x"003000";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '0' then
            report "PASS: match_valid correctly deasserted for 0x003000" severity note;
        else
            report "FAIL: match_valid incorrectly asserted for 0x003000" severity error;
        end if;

        -- ============================================================
        -- 8. Test with nonzero offset
        -- ============================================================
        report "=== TEST: Match with offset ===" severity note;
        match_addr   <= x"000FF0";
        match_offset <= x"000010";  -- effective = 0x001000, should match entry 0
        wait for CLK_PERIOD * 4;

        if match_valid = '1' then
            report "PASS: match_valid asserted for effective addr 0x001000 (with offset)" severity note;
        else
            report "FAIL: match_valid not asserted for effective addr 0x001000 (with offset)" severity error;
        end if;

        -- ============================================================
        -- 9. Test boundary: last address in range 0
        -- ============================================================
        -- Entry 0: addr=0x001000, length=0x0100 → last valid = 0x0010FF
        report "=== TEST: Match at last address in range (0x0010FF) ===" severity note;
        match_addr   <= x"0010FF";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '1' then
            report "PASS: match_valid asserted for last addr 0x0010FF" severity note;
        else
            report "FAIL: match_valid not asserted for last addr 0x0010FF" severity error;
        end if;

        -- ============================================================
        -- 10. Test boundary: first address past range 0
        -- ============================================================
        report "=== TEST: No match just past range (0x001100) ===" severity note;
        match_addr   <= x"001100";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '0' then
            report "PASS: match_valid correctly deasserted for 0x001100" severity note;
        else
            report "FAIL: match_valid incorrectly asserted for 0x001100" severity error;
        end if;

        -- ============================================================
        -- 11. Re-program test: enter programming mode and exit
        -- ============================================================
        report "=== TEST: Re-program cycle ===" severity note;
        prog_en <= '1';
        wait for CLK_PERIOD * 3;
        -- Program same entries again
        prog_byte(x"80"); prog_byte(x"00"); prog_byte(x"10"); prog_byte(x"00");
        prog_byte(x"01"); prog_byte(x"00"); prog_byte(x"02"); prog_byte(x"00");
        -- Terminator
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");
        prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00"); prog_byte(x"00");

        prog_en <= '0';
        wait until rising_edge(clk);

        -- Wait for re-init to complete
        wait until armed = '1' for 200 us;
        assert armed = '1'
            report "FAIL: INJECTOR did not re-arm after reprogramming"
            severity error;

        if armed = '1' then
            report "PASS: INJECTOR re-armed after reprogramming" severity note;
        end if;

        -- Verify match still works after reprogram
        match_addr   <= x"001000";
        match_offset <= x"000000";
        wait for CLK_PERIOD * 4;

        if match_valid = '1' then
            report "PASS: match still works after reprogram" severity note;
        else
            report "FAIL: match broken after reprogram" severity error;
        end if;

        -- ============================================================
        -- Done
        -- ============================================================
        report "=== ALL TESTS COMPLETE ===" severity note;
        wait for CLK_PERIOD * 10;
        done <= true;
        wait;
    end process;

end architecture;
