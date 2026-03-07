library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity INJECTOR is
generic (
    NUM_ENTRIES : integer := 16
);
port (
    RESET_N       : in std_logic;
    CLK           : in std_logic;

    PROG_EN       : in std_logic;
    PROG_DATA     : in std_logic_vector(7 downto 0);
    PROG_STROBE   : in std_logic;

    MATCH_ADDR    : in std_logic_vector(23 downto 0);
    MATCH_OFFSET  : in std_logic_vector(23 downto 0);
    MATCH_VALID   : out std_logic;
    MATCH_DATA    : out std_logic_vector(7 downto 0);

    -- signals to VFLASH
    MEM_ADDR      : out std_logic_vector(15 downto 0);
    MEM_RDEN      : out std_logic;
    MEM_WREN      : out std_logic;
    MEM_DATA_OUT  : out std_logic_vector(7 downto 0);
    MEM_DATA_IN   : in std_logic_vector(7 downto 0);
    
    ARMED         : out std_logic
);
end entity;

architecture RTL of INJECTOR is
type state_t is (ST_PREINIT, ST_INIT, ST_PROGRAM, ST_READY);

type entry_t is record
    stored: std_logic;
    reserved: std_logic_vector(6 downto 0);
    addr: std_logic_vector(23 downto 0);
    length: std_logic_vector(15 downto 0);
    data_address: std_logic_vector(15 downto 0);
end record;

type entry_array_t is array(0 to NUM_ENTRIES-1) of entry_t;

constant ENTRY_BITS : integer := 64;

function to_slv(e : entry_t) return std_logic_vector is
begin
    return e.stored & e.reserved & e.addr & e.length & e.data_address;
end function;

function to_slv(arr : entry_array_t) return std_logic_vector is
    variable result : std_logic_vector(arr'length * ENTRY_BITS - 1 downto 0);
begin
    for i in arr'range loop
        result((arr'length - i) * ENTRY_BITS - 1 downto (arr'length - 1 - i) * ENTRY_BITS) := to_slv(arr(i));
    end loop;
    return result;
end function;

function to_entry(v : std_logic_vector(ENTRY_BITS - 1 downto 0)) return entry_t is
    variable e : entry_t;
begin
    e.stored       := v(63);
    e.reserved     := v(62 downto 56);
    e.addr         := v(55 downto 32);
    e.length       := v(31 downto 16);
    e.data_address := v(15 downto 0);
    return e;
end function;

function to_entry_array(v : std_logic_vector) return entry_array_t is
    variable arr : entry_array_t;
    variable norm : std_logic_vector(v'length - 1 downto 0) := v;
begin
    assert v'length = NUM_ENTRIES * ENTRY_BITS
        report "to_entry_array: vector length mismatch"
        severity failure;
    for i in arr'range loop
        arr(i) := to_entry(norm((arr'length - i) * ENTRY_BITS - 1 downto (arr'length - 1 - i) * ENTRY_BITS));
    end loop;
    return arr;
end function;

constant EMPTY_ENTRY: entry_t := (
    stored => '0', 
    reserved => (others => '0'),
    addr => (others => '0'), 
    length => (others => '0'), 
    data_address => (others => '0')
);

type entry_state_t is record
    out_address: std_logic_vector(15 downto 0);
    matched: std_logic;
end record;

type entry_state_array_t is array(0 to NUM_ENTRIES-1) of entry_state_t;

constant EMPTY_ENTRY_STATE: entry_state_t := (
    out_address => (others => '0'), 
    matched => '0'
);

signal entries_D, entries_Q: entry_array_t := (others => EMPTY_ENTRY);
signal entry_states_D, entry_states_Q: entry_state_array_t := (others => EMPTY_ENTRY_STATE);
signal state_D, state_Q : state_t := ST_PREINIT;
signal prog_address_D, prog_address_Q, prog_address_QQ : std_logic_vector(15 downto 0) := (others => '0');
begin
COMB_NEXT: process(all)
variable effective_addr: unsigned(23 downto 0);
begin
    entries_D <= entries_Q;
    entry_states_D <= entry_states_Q;
    state_D <= state_Q;
    prog_address_D <= prog_address_Q;

    case state_Q is
        when ST_READY =>
            if PROG_EN = '1' then
                state_D <= ST_PROGRAM;
                prog_address_D <= (others => '0');
            else
                effective_addr := unsigned(MATCH_ADDR) + unsigned(MATCH_OFFSET);
                for i in 0 to NUM_ENTRIES-1 loop
                    entry_states_D(i).matched <= '0';
                    if effective_addr >= unsigned(entries_Q(i).addr) and effective_addr < unsigned(entries_Q(i).addr) + unsigned(entries_Q(i).length) then
                        entry_states_D(i).out_address <= std_logic_vector(resize(effective_addr - unsigned(entries_Q(i).addr) + unsigned(entries_Q(i).data_address), 16));
                        entry_states_D(i).matched <= entries_Q(i).stored;
                    end if;
                end loop;
            end if;
        when ST_PROGRAM =>
            if PROG_EN = '0' then
                state_D <= ST_PREINIT;
                prog_address_D <= (others => '0');
            elsif PROG_STROBE = '1' then
                prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
            end if;
        when ST_PREINIT =>
            if PROG_EN = '1' then
                state_D <= ST_PROGRAM;
                prog_address_D <= (others => '0');
            else
                state_D <= ST_INIT;
            end if;
        when ST_INIT =>
            if PROG_EN = '1' then
                state_D <= ST_PROGRAM;
                prog_address_D <= (others => '0');
            else
                if prog_address_QQ = x"00" and MEM_DATA_IN(7) = '0' then
                    state_D <= ST_READY;
                else
                    entries_D <= to_entry_array(to_slv(entries_Q)(NUM_ENTRIES * ENTRY_BITS - 8 - 1 downto 0) & MEM_DATA_IN);
                    prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
                end if;
                end if;
            when others =>
                null;
        end case;

    end process;

    COMB_OUT: process(all)
    variable match_valid_out: std_logic;
    variable armed_out: std_logic;
    variable data_out_address: std_logic_vector(15 downto 0);
    begin
        ARMED <= '0';
        MATCH_VALID <= '0';
        MEM_RDEN <= '0';
        MEM_WREN <= '0';
        MEM_ADDR <= (others => '0');
        MEM_DATA_OUT <= PROG_DATA;
        MATCH_DATA <= MEM_DATA_IN;
        case state_Q is
            when ST_READY =>
                armed_out := '0';
                match_valid_out := '0';
                data_out_address := (others => '0');
                for i in 0 to NUM_ENTRIES-1 loop
                    if entries_Q(i).stored = '1' then
                        armed_out := armed_out or '1';
                    end if;
                    if entry_states_Q(i).matched = '1' then
                        data_out_address := data_out_address or entry_states_Q(i).out_address;
                        match_valid_out := match_valid_out or entry_states_Q(i).matched;
                    end if;
                end loop;

                ARMED <= armed_out;
                MEM_ADDR <= data_out_address;
                MEM_RDEN <= '1';
                MATCH_VALID <= match_valid_out;
            when ST_PROGRAM =>
                MEM_ADDR <= prog_address_Q;
                MEM_WREN <= PROG_STROBE;
            when others =>
                null;
        end case;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state_Q <= ST_PREINIT;
                entries_Q <= (others => EMPTY_ENTRY);
                entry_states_Q <= (others => EMPTY_ENTRY_STATE);
                prog_address_Q <= (others => '0');
                prog_address_QQ <= (others => '0');
            else
                state_Q <= state_D;
                entries_Q <= entries_D;
                entry_states_Q <= entry_states_D;
                prog_address_Q <= prog_address_D;
                prog_address_QQ <= prog_address_Q;
            end if;
        end if;
    end process;
end architecture;
