library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.MUX_P.all;

entity INJECTOR is
generic (
    NUM_ENTRIES   : integer := 16
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
constant ENTRY_BITS : integer := 64;

type shift_lines_t is array(0 to NUM_ENTRIES) of std_logic_vector(7 downto 0);

signal state_D, state_Q : state_t := ST_PREINIT;
signal prog_address_D, prog_address_Q, prog_address_QQ : std_logic_vector(15 downto 0) := (others => '0');
signal effective_addr: unsigned(23 downto 0);
signal reg_match: std_logic_vector(NUM_ENTRIES-1 downto 0);
signal reg_selector: std_logic_vector(integer(ceil(log2(real(NUM_ENTRIES))))-1 downto 0);
signal armed_reg: std_logic_vector(NUM_ENTRIES-1 downto 0);
signal arbiter_match: std_logic;
signal addr_outs: slv_array_t(0 to NUM_ENTRIES-1)(15 downto 0);
signal selected_addr_out : std_logic_vector(15 downto 0);
signal shift_lines: shift_lines_t;
signal shift_en: std_logic;

begin
    RR: for i in 0 to NUM_ENTRIES-1 generate
        REG: entity WORK.RANGE_REGISTER
        port map (
            RESET_N => RESET_N,
            CLK => CLK,
            ARMED => armed_reg(i),
            ADDR_IN => std_logic_vector(effective_addr),
            ADDR_MATCH => reg_match(i),
            ADDR_OUT => addr_outs(i),
            SHIFT_EN => shift_en,
            SHIFT_IN => shift_lines(i),
            SHIFT_OUT => shift_lines(i+1)
        );
    end generate;

    ARBITER: entity WORK.ARBITER
    port map (
        INPUT => reg_match,
        OUTPUT => reg_selector,
        VALID => arbiter_match
    );

    MUX: entity WORK.MUX
    generic map (
        N => NUM_ENTRIES,
        W => MEM_ADDR'length
    )
    port map (
        I => addr_outs,
        SEL => reg_selector,
        Q => selected_addr_out
    );

    COMB_NEXT: process(all)
    begin
        state_D <= state_Q;
        prog_address_D <= prog_address_Q;

        case state_Q is
            when ST_READY =>
                if PROG_EN = '1' then
                    state_D <= ST_PROGRAM;
                    prog_address_D <= (others => '0');
                else
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
                    end if;
                end if;
            when others =>
                null;
        end case;

    end process;

    COMB_OUT: process(all)
    variable armed_out : std_logic;
    begin
        effective_addr <= unsigned(MATCH_ADDR) + unsigned(MATCH_OFFSET);
        shift_lines(0) <= MEM_DATA_IN;
        shift_en <= '0';

        ARMED <= '0';
        MATCH_VALID <= '0';
        MEM_RDEN <= '0';
        MEM_WREN <= '0';
        MEM_ADDR <= (others => '0');
        MEM_DATA_OUT <= PROG_DATA;
        MATCH_DATA <= MEM_DATA_IN;
        case state_Q is
            when ST_READY =>
                if armed_reg = (armed_reg'range => '0') then
                    ARMED <= '1';
                end if;
                MEM_ADDR <= selected_addr_out;
                MEM_RDEN <= '1';
                MATCH_VALID <= arbiter_match;
            when ST_PROGRAM =>
                MEM_ADDR <= prog_address_Q;
                MEM_WREN <= PROG_STROBE;
            when ST_INIT =>
                shift_en <= '1';
            when others =>
                null;
        end case;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state_Q <= ST_PREINIT;
                prog_address_Q <= (others => '0');
                prog_address_QQ <= (others => '0');
            else
                state_Q <= state_D;
                prog_address_Q <= prog_address_D;
                prog_address_QQ <= prog_address_Q;
            end if;
        end if;
    end process;
end architecture;
