library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity ARBITER is
generic (
    NUM_ENTRIES   : integer := 16
);
port (
    INPUT         : in std_logic_vector(NUM_ENTRIES-1 downto 0);
    OUTPUT        : out std_logic_vector(integer(ceil(log2(real(NUM_ENTRIES))))-1 downto 0);
    VALID         : out std_logic
);
end entity;

architecture RTL of ARBITER is
begin
    COMB_OUT: process(all)
    begin
        VALID <= '0';
        OUTPUT <= (others => '0');
        for i in 0 to NUM_ENTRIES-1 loop
            if INPUT(i) = '1' then
                VALID <= '1';
                OUTPUT <= std_logic_vector(to_unsigned(i, OUTPUT'length));
            end if;
            exit when INPUT(i) = '1';
        end loop;
    end process;
end architecture;

