library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

package MUX_P is
    type slv_array_t is array (natural range <>) of std_logic_vector;
end package;

package body MUX_P is
end package body;

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.MUX_P;

entity MUX is
generic (
    N : natural;
    W : natural
);
port (
    I     : in mux_p.slv_array_t(0 to N - 1)(W-1 downto 0);
    SEL   : in std_logic_vector(integer(ceil(log2(real(N))))-1 downto 0);
    Q     : out std_logic_vector(W-1 downto 0)
);
end entity;

architecture RTL of MUX is
begin
    Q <= I(to_integer(unsigned(SEL)));
end architecture;
