library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

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
        MATCH_OFFSET  : in std_logic_vector(23 downto 0);
        MATCH_VALID   : out std_logic;
        MATCH_VF_ADDR : out std_logic_vector(15 downto 0);
        MATCH_DATA    : out std_logic_vector(7 downto 0);
        
        ARMED         : out std_logic
    );
end entity;

architecture RTL of INJECTOR is
    function log2(x: integer) return integer is
    begin
        return integer(ceil(log2(real(x))));
    end function;
    type entry_t is record
        addr: std_logic_vector(23 downto 0);
        length: std_logic_vector(15 downto 0);
        data_address: std_logic_vector(15 downto 0);
        stored: std_logic;

        out_address: std_logic_vector(15 downto 0);
        matched: std_logic;
    end record;
    type entry_array_t is array(0 to NUM_ENTRIES-1) of entry_t;
    constant EMPTY_ENTRY: entry_t := (addr => (others => '0'), length => (others => '0'), data_address => (others => '0'), stored => '0', out_address => (others => '0'), matched => '0');
    signal entries: entry_array_t := (others => EMPTY_ENTRY);
    signal next_entries: entry_array_t := (others => EMPTY_ENTRY);
begin
    COMB_NEXT: process(all)
    variable effective_addr: unsigned(23 downto 0);
    begin
        next_entries <= entries;
        if REPLACE_CLEAR = '1' then --clear all entries
            next_entries <= (others => EMPTY_ENTRY);
        elsif REPLACE_STORE = '1' then --store new entry
            --next_entries(to_integer(unsigned(REPLACE_IX))).addr <= REPLACE_ADDR;
            --next_entries(to_integer(unsigned(REPLACE_IX))).data <= REPLACE_DATA;
            --next_entries(to_integer(unsigned(REPLACE_IX))).stored <= '1';
        end if;

        effective_addr := unsigned(MATCH_ADDR) + unsigned(MATCH_OFFSET);
        for i in 0 to NUM_ENTRIES-1 loop
            next_entries(i).matched <= '0';
            if effective_addr >= unsigned(entries(i).addr) and effective_addr < unsigned(entries(i).addr) + unsigned(entries(i).length) then
                next_entries(i).out_address <= std_logic_vector(resize(effective_addr - unsigned(entries(i).addr) + unsigned(entries(i).data_address), 16));
                next_entries(i).matched <= entries(i).stored;
            end if;
        end loop;

    end process;

    COMB_OUT: process(all)
    variable match_data_out: std_logic_vector(7 downto 0);
    variable match_valid_out: std_logic;
    variable armed_out: std_logic;
    variable data_out_address: std_logic_vector(15 downto 0);
    begin
        armed_out := '0';
        match_data_out := (others => '0');
        match_valid_out := '0';
        data_out_address := (others => '0');
        for i in 0 to NUM_ENTRIES-1 loop
            if entries(i).stored = '1' then
                armed_out := armed_out or '1';
            end if;
            if entries(i).matched = '1' then
                data_out_address := data_out_address or entries(i).out_address;
                match_valid_out := match_valid_out or entries(i).matched;
            end if;
        end loop;

        ARMED <= armed_out;
        MATCH_VALID <= match_valid_out;
        MATCH_VF_ADDR <= data_out_address;
        MATCH_DATA <= (others => '0');
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                entries <= (others => EMPTY_ENTRY);
            else
                entries <= next_entries;
            end if;
        end if;
    end process;
end architecture;