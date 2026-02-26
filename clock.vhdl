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
    signal clk_time : unsigned(15 downto 0);
    signal next_clk_time : unsigned(15 downto 0);
    signal ms_count : unsigned(15 downto 0);
    signal next_ms_count : unsigned(15 downto 0);
begin
    COMB_OUT: process(ms_count)
    begin
        TIME_OUT <= std_logic_vector(ms_count);
    end process;

    COMB_NEXT: process(clk_time)
	     constant MS_PERIOD : unsigned(15 downto 0) := to_unsigned(50000, 16);
    begin
        next_clk_time <= clk_time + 1;
        if clk_time = MS_PERIOD then
            next_ms_count <= ms_count + 1;
            next_clk_time <= (others => '0');
        end if;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                clk_time <= (others => '0');
                ms_count <= (others => '0');
            else
                clk_time <= next_clk_time;
                ms_count <= next_ms_count;
			   end if;
        end if;
    end process;
end architecture RTL;
