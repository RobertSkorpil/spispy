-- arbiter_tb.vhdl — Testbench for ARBITER module
-- Verifies priority encoding: OUTPUT = index of lowest set bit in INPUT,
-- VALID is asserted when any bit is set.
-- Simulator: nvc (VHDL-2008)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity arbiter_tb is
end entity;

architecture sim of arbiter_tb is

    constant NUM_ENTRIES : integer := 8;
    constant OUT_WIDTH   : integer := integer(ceil(log2(real(NUM_ENTRIES))));

    signal input_vec : std_logic_vector(NUM_ENTRIES-1 downto 0) := (others => '0');
    signal output_idx : std_logic_vector(OUT_WIDTH-1 downto 0);
    signal valid      : std_logic;

    signal done : boolean := false;

    -- Helper: check arbiter output against expected values
    procedure check(
        signal   inp   : in std_logic_vector(NUM_ENTRIES-1 downto 0);
        signal   outp  : in std_logic_vector(OUT_WIDTH-1 downto 0);
        signal   v     : in std_logic;
        constant exp_v : in std_logic;
        constant exp_o : in integer;
        constant tag   : in string
    ) is
    begin
        assert v = exp_v
            report tag & ": VALID expected " & std_logic'image(exp_v) &
                   " got " & std_logic'image(v)
            severity failure;
        if exp_v = '1' then
            assert to_integer(unsigned(outp)) = exp_o
                report tag & ": OUTPUT expected " & integer'image(exp_o) &
                       " got " & integer'image(to_integer(unsigned(outp)))
                severity failure;
        end if;
    end procedure;

begin

    -- ---------------------------------------------------------------
    -- DUT instantiation
    -- ---------------------------------------------------------------
    DUT: entity work.arbiter
        generic map (NUM_ENTRIES => NUM_ENTRIES)
        port map (
            INPUT  => input_vec,
            OUTPUT => output_idx,
            VALID  => valid
        );

    -- ---------------------------------------------------------------
    -- Stimulus process
    -- ---------------------------------------------------------------
    STIM: process
    begin
        -- Test 1: All zeros — no valid output
        input_vec <= (others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '0', 0, "T1 all-zeros");

        -- Test 2: Only bit 0 set — should select index 0
        input_vec <= (0 => '1', others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 0, "T2 bit0");

        -- Test 3: Only MSB set — should select index NUM_ENTRIES-1
        input_vec <= (NUM_ENTRIES-1 => '1', others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', NUM_ENTRIES-1, "T3 MSB");

        -- Test 4: Bits 0 and 3 set — priority goes to bit 0
        input_vec <= (0 => '1', 3 => '1', others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 0, "T4 bit0+bit3");

        -- Test 5: Bits 2 and 5 set — priority goes to bit 2
        input_vec <= (2 => '1', 5 => '1', others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 2, "T5 bit2+bit5");

        -- Test 6: All ones — priority goes to bit 0
        input_vec <= (others => '1');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 0, "T6 all-ones");

        -- Test 7: Only bit 4 set
        input_vec <= (4 => '1', others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 4, "T7 bit4");

        -- Test 8: Bits 3,4,5,6,7 set — priority to bit 3
        input_vec <= "11111000";
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 3, "T8 upper-half");

        -- Test 9: Only bit 7 set
        input_vec <= "10000000";
        wait for 10 ns;
        check(input_vec, output_idx, valid, '1', 7, "T9 bit7");

        -- Test 10: Walk a single bit across all positions
        for i in 0 to NUM_ENTRIES-1 loop
            input_vec <= (others => '0');
            input_vec(i) <= '1';
            wait for 10 ns;
            check(input_vec, output_idx, valid, '1', i,
                  "T10 walk bit " & integer'image(i));
        end loop;

        -- Test 11: Back to zeros to confirm VALID de-asserts
        input_vec <= (others => '0');
        wait for 10 ns;
        check(input_vec, output_idx, valid, '0', 0, "T11 re-zero");

        report "*** All arbiter tests PASSED ***" severity note;
        done <= true;
        wait;
    end process;

end architecture;
