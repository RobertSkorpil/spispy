library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity CLOCK is
    port (
        RESET    : in std_logic;
        CLK      : in std_logic;
        TIME_OUT : out std_logic_vector(15 downto 0)
    );
end entity;

architecture RTL of CLOCK is
    signal clk_time : unsigned(31 downto 0);
    signal next_clk_time : unsigned(31 downto 0);
begin
    COMB_OUT: process(clk_time)
    begin
        TIME_OUT <= std_logic_vector(clk_time)(31 downto 16);
    end process;

    COMB_NEXT: process(clk_time)
    begin
        next_clk_time <= clk_time + 1;
    end process;

    SYNC: process(CLK, RESET)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                clk_time <= (others => '0');
            else
                clk_time <= next_clk_time;
			   end if;
        end if;
    end process;
end architecture RTL;
