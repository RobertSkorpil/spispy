library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity RANGE_REGISTER is
port (
    RESET_N       : in std_logic;
    CLK           : in std_logic;

    ARMED         : out std_logic;

    ADDR_IN       : in std_logic_vector(23 downto 0);
    ADDR_MATCH    : out std_logic;
    ADDR_OUT      : out std_logic_vector(15 downto 0);

    SHIFT_EN      : in std_logic;
    SHIFT_IN      : in std_logic_vector(7 downto 0);
    SHIFT_OUT     : out std_logic_vector(7 downto 0) --;
);
end entity;

architecture RTL of RANGE_REGISTER is
    signal stored_D, stored_Q: std_logic := '0';
    signal reserved_D, reserved_Q: std_logic_vector(6 downto 0) := (others => '0');
    signal addr_D, addr_Q: std_logic_vector(23 downto 0) := (others => '0');
    signal length_D, length_Q: std_logic_vector(15 downto 0) := (others => '0');
    signal data_address_D, data_address_Q: std_logic_vector(15 downto 0) := (others => '0');
begin
    COMB_NEXT: process(all)
    begin
        stored_D <= stored_Q;
        reserved_D <= reserved_Q;
        addr_D <= addr_Q;
        length_D <= length_Q;
        data_address_D <= data_address_Q;
        if SHIFT_EN = '1' then
            stored_D <= addr_Q(23);
            reserved_D <= addr_Q(22 downto 16);
            addr_D <= addr_Q(15 downto 0) & length_Q(15 downto 8);
            length_D <= length_Q(7 downto 0) & data_address_Q(15 downto 8);
            data_address_D <= data_address_Q(7 downto 0) & SHIFT_IN;
        end if;
    end process;

    COMB_OUT: process(all)
    begin
        ARMED <= stored_Q;
        ADDR_MATCH <= '0';
        if unsigned(ADDR_IN) >= unsigned(addr_Q) and unsigned(ADDR_IN) < unsigned(addr_Q) + unsigned(length_Q) then
            ADDR_MATCH <= '1';
        end if;
        ADDR_OUT <= std_logic_vector(resize(unsigned(ADDR_IN) - unsigned(addr_Q) + unsigned(data_address_Q), 16));
        SHIFT_OUT <= stored_Q & reserved_Q;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                stored_Q <= '0';
                reserved_Q <= (others => '0');
                addr_Q <= (others => '0');
                length_Q <= (others => '0');
                data_address_Q <= (others => '0');
            else
                stored_Q <= stored_D;
                reserved_Q <= reserved_D;
                addr_Q <= addr_D;
                length_Q <= length_D;
                data_address_Q <= data_address_D;
            end if;
        end if;
    end process;
end architecture;

