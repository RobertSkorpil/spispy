library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity INJECTOR is
    generic (
        NUM_ENTRIES : integer := 16
    );
    port (
        RESET_N : in std_logic;
        CLK : in std_logic;

        REPLACE_IX    : in std_logic_vector(7 downto 0);
        REPLACE_ADDR  : in std_logic_vector(23 downto 0);
        REPLACE_DATA  : in std_logic_vector(63 downto 0);
        REPLACE_STORE : in std_logic;
        REPLACE_CLEAR : in std_logic;

        MATCH_ADDR    : in std_logic_vector(23 downto 0);
        MATCH_DATA    : out std_logic_vector(63 downto 0);
        MATCH_VALID   : out std_logic;
        
        ARMED         : out std_logic
    );
end entity;

architecture RTL of INJECTOR is
    type entry_t is record
        addr: std_logic_vector(23 downto 0);
        data: std_logic_vector(63 downto 0);
        stored: std_logic;
    end record;
    type entry_array_t is array(0 to NUM_ENTRIES-1) of entry_t;
    signal entries: entry_array_t := (others => (addr => (others => '0'), data => (others => '0'), stored => '0'));
    signal next_entries: entry_array_t := (others => (addr => (others => '0'), data => (others => '0'), stored => '0'));
begin
    COMB_NEXT: process(all)
    begin
        next_entries <= entries;
        if REPLACE_CLEAR = '1' then --clear all entries
            next_entries <= (others => (addr => (others => '0'), data => (others => '0'), stored => '0'));
        elsif REPLACE_STORE = '1' then --store new entry
            next_entries(to_integer(unsigned(REPLACE_IX))).addr <= REPLACE_ADDR;
            next_entries(to_integer(unsigned(REPLACE_IX))).data <= REPLACE_DATA;
            next_entries(to_integer(unsigned(REPLACE_IX))).stored <= '1';
        end if;
    end process;

    COMB_OUT: process(all)
    variable match_data_out: std_logic_vector(63 downto 0);
    variable match_valid_out: std_logic;
    variable armed_out: std_logic;
    begin
        armed_out := '0';
        match_data_out := (others => '0');
        match_valid_out := '0';
--        for i in 0 to NUM_ENTRIES-1 loop
--            if entries(i).stored = '1' then
--                armed_out := '1';
--                if MATCH_ADDR = entries(i).addr then
--                    match_data_out := match_data_out or entries(i).data;
--                    match_valid_out := '1';
--                end if;
--            end if;
--        end loop;
        ARMED <= armed_out;
        MATCH_DATA <= match_data_out;
        MATCH_VALID <= match_valid_out;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                entries <= (others => (addr => (others => '0'), data => (others => '0'), stored => '0'));
            else
                entries <= next_entries;
            end if;
        end if;
    end process;
end architecture;