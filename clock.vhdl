library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity CLOCK is
    port (
        RESET_N  : in std_logic;
        CLK      : in std_logic;
        TIME_OUT : out std_logic_vector(15 downto 0)
    );
end entity;

architecture RTL of CLOCK is
    signal clk_time : unsigned(31 downto 0);
    signal next_clk_time : unsigned(31 downto 0);
begin
    COMB_OUT: process(clk_time)
        variable tmp : std_logic_vector(31 downto 0);
    begin
        tmp := std_logic_vector(clk_time);
        TIME_OUT <= tmp(31 downto 16);
    end process;

    COMB_NEXT: process(clk_time)
    begin
        next_clk_time <= clk_time + 1;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                clk_time <= (others => '0');
            else
                clk_time <= next_clk_time;
			   end if;
        end if;
    end process;
end architecture RTL;
