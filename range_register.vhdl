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
    SHIFT_OUT     : out std_logic_vector(7 downto 0)
);
end entity;

architecture RTL of RANGE_REGISTER is
    signal addr_in_Q : std_logic_vector(23 downto 0);
    signal stored_D, stored_Q: std_logic := '0';
    signal reserved_D, reserved_Q: std_logic_vector(6 downto 0) := (others => '0');
    signal addr_D, addr_Q: std_logic_vector(23 downto 0) := (others => '0');
    signal length_D, length_Q: std_logic_vector(15 downto 0) := (others => '0');
    signal data_address_D, data_address_Q: std_logic_vector(15 downto 0) := (others => '0');
    signal addr_match_D, addr_match_Q: std_logic := '0';
    signal addr_out_D, addr_out_Q: std_logic_vector(15 downto 0) := (others => '0');
begin
    COMB_NEXT: process(all)
    begin
        stored_D <= stored_Q;
        reserved_D <= reserved_Q;
        addr_D <= addr_Q;
        length_D <= length_Q;
        data_address_D <= data_address_Q;
        addr_match_D <= '0';
        addr_out_D <= addr_out_Q;
        if SHIFT_EN = '1' then
            stored_D <= addr_Q(23);
            reserved_D <= addr_Q(22 downto 16);
            addr_D <= addr_Q(15 downto 0) & length_Q(15 downto 8);
            length_D <= length_Q(7 downto 0) & data_address_Q(15 downto 8);
            data_address_D <= data_address_Q(7 downto 0) & SHIFT_IN;
        else
            if unsigned(addr_in_Q) >= unsigned(addr_Q) and unsigned(addr_in_Q) < unsigned(addr_Q) + unsigned(length_Q) then
                addr_match_D <= '1';
            end if;
            addr_out_D <= std_logic_vector(resize(unsigned(addr_in_Q) - unsigned(addr_Q) + unsigned(data_address_Q), 16));
        end if;
    end process;

    COMB_OUT: process(all)
    begin
        ARMED <= stored_Q;
        ADDR_MATCH <= addr_match_Q;
        ADDR_OUT <= addr_out_Q;
        SHIFT_OUT <= stored_Q & reserved_Q;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                addr_in_Q <= (others => '0');
                stored_Q <= '0';
                reserved_Q <= (others => '0');
                addr_Q <= (others => '0');
                length_Q <= (others => '0');
                data_address_Q <= (others => '0');
                addr_match_Q <= '0';
                addr_out_Q <= (others => '0');
            else
                addr_in_Q <= ADDR_IN;
                stored_Q <= stored_D;
                reserved_Q <= reserved_D;
                addr_Q <= addr_D;
                length_Q <= length_D;
                data_address_Q <= data_address_D;
                addr_match_Q <= addr_match_D;
                addr_out_Q <= addr_out_D;
            end if;
        end if;
    end process;
end architecture;

