library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity CLOCK is
    port (
        RESET_N  : in std_logic;
        CLK      : in std_logic; --50MHz, period 20ns
        TIME_OUT : out std_logic_vector(15 downto 0)
    );
end entity;

architecture RTL of CLOCK is
    signal clk_time_D, clk_time_Q : unsigned(15 downto 0) := (others => '0');
    signal ms_count_D, ms_count_Q : unsigned(15 downto 0);
begin
    COMB_OUT: process(all)
    begin
        TIME_OUT <= std_logic_vector(ms_count_Q);
    end process;

    COMB_NEXT: process(all)
        constant MS_PERIOD : unsigned(15 downto 0) := to_unsigned(50000, 16);
    begin
        clk_time_D <= clk_time_Q + 1;
        ms_count_D <= ms_count_Q;
        if clk_time_Q = MS_PERIOD then
            ms_count_D <= ms_count_Q + 1;
            clk_time_D <= (others => '0');
        end if;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                clk_time_Q <= (others => '0');
                ms_count_Q <= (others => '0');
            else
                clk_time_Q <= clk_time_D;
                ms_count_Q <= ms_count_D;
            end if;
        end if;
    end process;
end architecture RTL;
