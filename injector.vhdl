library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.MUX_P.all;

entity INJECTOR is
generic (
    NUM_ENTRIES   : integer
);
port (
    RESET_N       : in std_logic;
    CLK           : in std_logic;

    PROG_EN       : in std_logic;
    PROG_DATA     : in std_logic_vector(7 downto 0);
    PROG_STROBE   : in std_logic;
    PROG_DUMP     : in std_logic;

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
type state_t is (ST_PREINIT, ST_INIT, ST_PROGRAM, ST_READY, ST_DUMP_LEN1, ST_DUMP_LEN2, ST_DUMP_BUF);

type shift_lines_t is array(0 to NUM_ENTRIES) of std_logic_vector(7 downto 0);

signal reset_regs_n : std_logic := '0';
signal state_D, state_Q : state_t := ST_PREINIT;
signal prog_address_D, prog_address_Q, prog_address_QQ: std_logic_vector(15 downto 0) := (others => '0');
signal arbiter_match_D, arbiter_match_Q: std_logic := '0';
signal buf_size_D, buf_size_Q: std_logic_vector(15 downto 0) := (others => '0');

signal effective_addr: unsigned(23 downto 0);
signal reg_match: std_logic_vector(NUM_ENTRIES-1 downto 0);
signal reg_selector: std_logic_vector(integer(ceil(log2(real(NUM_ENTRIES))))-1 downto 0);
signal armed_reg: std_logic_vector(NUM_ENTRIES-1 downto 0);
signal addr_outs: slv_array_t(0 to NUM_ENTRIES-1)(15 downto 0);
signal selected_addr_out : std_logic_vector(15 downto 0);
signal shift_lines: shift_lines_t;
signal shift_en: std_logic;

begin
    RR: for i in 0 to NUM_ENTRIES-1 generate
        REG: entity WORK.RANGE_REGISTER
        port map (
            RESET_N => reset_regs_n,
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
    generic map (
        NUM_ENTRIES => NUM_ENTRIES
    )
    port map (
        INPUT => reg_match,
        OUTPUT => reg_selector,
        VALID => arbiter_match_D
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
        buf_size_D <= buf_size_Q;

        case state_Q is
            when ST_READY =>
                if PROG_EN = '1' then
                    state_D <= ST_PROGRAM;
                    prog_address_D <= (others => '0');
                end if;
                if PROG_DUMP = '1' then
                    state_D <= ST_DUMP_LEN1;
                end if;
            when ST_DUMP_LEN1 =>
                prog_address_D <= (others => '0');
                if PROG_DUMP = '0' then
                    state_D <= ST_READY;
                end if;
                if PROG_STROBE = '1' then
                    state_D <= ST_DUMP_LEN2;
                end if;
            when ST_DUMP_LEN2 =>
                if PROG_DUMP = '0' then
                    state_D <= ST_READY;
                end if;
                if PROG_STROBE = '1' then
                    state_D <= ST_DUMP_BUF;
                end if;
            when ST_DUMP_BUF =>
                if PROG_DUMP = '0' then
                    state_D <= ST_READY;
                end if;
                if PROG_STROBE = '1' then
                    prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
                end if;
            when ST_PROGRAM =>
                if PROG_EN = '0' then
                    state_D <= ST_PREINIT;
                    prog_address_D <= (others => '0');
                    buf_size_D <= prog_address_Q;
                elsif PROG_STROBE = '1' then
                    prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
                end if;
            when ST_PREINIT =>
                if PROG_EN = '1' then
                    state_D <= ST_PROGRAM;
                    prog_address_D <= (others => '0');
                else
                    state_D <= ST_INIT;
                    prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
                end if;
            when ST_INIT =>
                if PROG_EN = '1' then
                    state_D <= ST_PROGRAM;
                    prog_address_D <= (others => '0');
                else
                    if prog_address_QQ(2 downto 0) = "000" and MEM_DATA_IN(7) = '0' then
                        state_D <= ST_READY;
                    end if;
                    prog_address_D <= std_logic_vector(unsigned(prog_address_Q) + 1);
                end if;
            when others =>
                null;
        end case;

    end process;

    COMB_OUT: process(all)
    begin
        effective_addr <= unsigned(MATCH_ADDR) + unsigned(MATCH_OFFSET);
        shift_lines(0) <= MEM_DATA_IN;
        shift_en <= '0';
        reset_regs_n <= '1';

        ARMED <= '0';
        MATCH_VALID <= '0';
        MEM_RDEN <= '0';
        MEM_WREN <= '0';
        MEM_ADDR <= (others => '0');
        MEM_DATA_OUT <= PROG_DATA;
        MATCH_DATA <= MEM_DATA_IN;
        case state_Q is
            when ST_READY =>
                if armed_reg /= (armed_reg'range => '0') then
                    ARMED <= '1';
                end if;
                MEM_ADDR <= selected_addr_out;
                MEM_RDEN <= '1';
                MATCH_VALID <= arbiter_match_Q;
            when ST_DUMP_LEN1 =>
                MATCH_DATA <= buf_size_Q(15 downto 8);
            when ST_DUMP_LEN2 =>
                MATCH_DATA <= buf_size_Q(7 downto 0);
                MEM_ADDR <= prog_address_Q;
                MEM_RDEN <= '1';
            when ST_DUMP_BUF =>
                MEM_ADDR <= prog_address_Q;
                MEM_RDEN <= '1';
            when ST_PROGRAM =>
                MEM_ADDR <= prog_address_Q;
                MEM_WREN <= PROG_STROBE;
            when ST_PREINIT =>
                MEM_ADDR <= prog_address_Q;
                MEM_RDEN <= '1';
                reset_regs_n <= '0';
            when ST_INIT =>
                MEM_ADDR <= prog_address_Q;
                MEM_RDEN <= '1';
                if state_D /= ST_READY then
                    shift_en <= '1';
                else
                    shift_en <= '0';
                end if;
            when others =>
                null;
        end case;
        if RESET_N = '0' then
            reset_regs_n <= '0';
        end if;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state_Q <= ST_PREINIT;
                prog_address_Q <= (others => '0');
                prog_address_QQ <= (others => '1');
                arbiter_match_Q <= '0';
                buf_size_Q <= (others => '0');
            else
                state_Q <= state_D;
                prog_address_Q <= prog_address_D;
                prog_address_QQ <= prog_address_Q;
                arbiter_match_Q <= arbiter_match_D;
                buf_size_Q <= buf_size_D;
            end if;
        end if;
    end process;
end architecture;
