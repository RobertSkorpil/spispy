library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity INJECTOR is
    port (
        RESET_N : in std_logic;
        CLK : in std_logic;

        ADDR : in std_logic_vector(23 downto 0);
        DATA: in std_logic_vector(63 downto 0);
        PUSH: in std_logic;

        MATCH_ADDR: in std_logic(23 downto 0);
        MATCH_DATA: out std_logic(63 downto 0);
        MATCH_VALID: out std_logic;
    );
end entity;

architecture RTL of INJECTOR is
    signal inj_addr_reg: unsigned(23 downto 0) := (others => '0');
    signal next_inj_addr_reg: unsigned(23 downto 0) := (others => '0');
    signal inj_data_reg: std_logic_vector(63 downto 0) := (others => '0');
    signal next_inj_data_reg: std_logic_vector(63 downto 0) := (others => '0');
begin
    COMB_NEXT: process(ADDR, DATA, PUSH)
    begin
        if PUSH = '1' then
            next_inj_addr_reg <= ADDR;
            next_inj_data_reg <= DATA;
        else
            next_inj_addr_reg <= inj_addr_reg;
            next_inj_data_reg <= inj_data_reg;
        end if;
    end process;

    COMB_OUT: process(shift_reg)
    begin
        if MATCH_ADDR = inj_addr_reg then
            MATCH_DATA <= inj_data_reg;
            MATCH_VALID <= '1';
        else
            MATCH_DATA <= (others => '0');
            MATCH_VALID <= '0';
        end if;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                inj_addr_reg <= (others => '0');
                inj_data_reg <= (others => '0');
            else
                inj_addr_reg <= next_inj_addr_reg;
                inj_data_reg <= next_inj_data_reg;
            end if;
        end if;
    end process;
end architecture;