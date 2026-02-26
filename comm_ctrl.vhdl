library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- COMM_CTRL: Bridge between comm_spi Avalon-ST interface and BUFCTRL read port.
entity COMM_CTRL is
    port (
        CLK            : in  std_logic;
        RESET_N        : in  std_logic;

        -- BUFCTRL read interface
        READ_ADDR      : in  std_logic_vector(23 downto 0);
        READ_COUNT     : in  std_logic_vector(23 downto 0);
        READ_TIME      : in  std_logic_vector(15 downto 0);
        READ_READY     : in  std_logic;
        READ_LOST      : in  std_logic;
        READ_NEXT      : out std_logic;

        -- Avalon-ST sink (we send bytes TO the SPI core for MISO)
        ST_SINK_DATA   : out std_logic_vector(7 downto 0);
        ST_SINK_VALID  : out std_logic;
        ST_SINK_READY  : in  std_logic;

        -- Avalon-ST source (we receive bytes FROM the SPI core, MOSI)
        -- We don't need MOSI data, but must accept it to keep the
        -- streaming interface happy.
        ST_SOURCE_DATA  : in  std_logic_vector(7 downto 0);
        ST_SOURCE_VALID : in  std_logic;
        ST_SOURCE_READY : out std_logic;

        -- Active-low slave select, directly from the SPI bus
        SPI_SS_N       : in  std_logic;

        -- Replace data input
        REPLACE_IX     : out std_logic_vector(7 downto 0);
        REPLACE_ADDR   : out std_logic_vector(23 downto 0);
        REPLACE_DATA   : out std_logic_vector(63 downto 0);
        REPLACE_STORE  : out std_logic;
        REPLACE_CLEAR  : out std_logic
    );
end entity COMM_CTRL;

architecture RTL of COMM_CTRL is

    constant ALL_FF : std_logic_vector(63 downto 0) := (others => '1');

    type state_t is (S_IDLE, S_CMD, S_LATCH, S_REPLACE, S_CLEAR, S_SEND, S_INVALID);

    -- Current state registers
    signal state      : state_t := S_IDLE;
    signal shift_reg  : std_logic_vector(63 downto 0) := (others => '1');
    signal replace_reg  : std_logic_vector(95 downto 0) := (others => '1');
    signal byte_cnt   : unsigned(3 downto 0) := (others => '0');
    signal ss_n_ff1   : std_logic := '1';
    signal ss_n_prev   : std_logic := '1';
    signal ss_n       : std_logic := '1';

    -- Next state signals
    signal state_next      : state_t;
    signal shift_reg_next  : std_logic_vector(63 downto 0);
    signal replace_reg_next  : std_logic_vector(95 downto 0);
    signal byte_cnt_next   : unsigned(3 downto 0);

begin

    -- Always accept source data (MOSI bytes) — we ignore them
    ST_SOURCE_READY <= '1';

    -- COMB_NEXT: Combinational logic for next state
    COMB_NEXT: process(all)
    begin
        -- Default: hold current values
        state_next     <= state;
        shift_reg_next <= shift_reg;
        byte_cnt_next  <= byte_cnt;
        replace_reg_next <= replace_reg;

        if ss_n = '1' then
            state_next <= S_IDLE;
            byte_cnt_next <= (others => '0');
        else
            case state is
                when S_INVALID =>
                    null;
                when S_IDLE =>
                    state_next <= S_CMD;
                when S_CMD =>
                    if ST_SOURCE_VALID = '1' then
                        case ST_SOURCE_DATA(1 downto 0) is
                            when b"01" =>
                                state_next <= S_LATCH;
                            when b"10" =>
                                state_next <= S_REPLACE;
                            when b"11" =>
                                state_next <= S_CLEAR;
                            when others =>
                                state_next <= S_INVALID;
                        end case;
                    end if;
                when S_REPLACE =>
                    if byte_cnt = 1 + 3 + 8 then
                        state_next <= S_INVALID;
                    elsif ST_SOURCE_VALID = '1' then
                        replace_reg_next <= replace_reg(87 downto 0) & ST_SOURCE_DATA;
                        byte_cnt_next <= byte_cnt + 1;
                    end if;
                when S_CLEAR =>
                    if ST_SOURCE_VALID = '1' then
                        state_next <= S_INVALID;
                    end if;
                when S_LATCH =>
                    -- Latch current BUFCTRL output
                    if READ_READY = '1' then
                        shift_reg_next <= READ_ADDR & READ_COUNT & READ_TIME;
                    else
                        shift_reg_next <= ALL_FF;
                    end if;
                    byte_cnt_next <= (others => '0');
                    state_next <= S_SEND;

                when S_SEND =>
                    if ST_SINK_READY = '1' then
                        if byte_cnt /= 7 then
                            byte_cnt_next <= byte_cnt + 1;
                        else
                            state_next <= S_INVALID;
                        end if;
                    end if;

                when others =>
                    state_next <= S_IDLE;
            end case;
        end if;
    end process COMB_NEXT;

    -- COMB_OUT: Combinational logic for outputs
    COMB_OUT: process(all)
    begin
        -- Defaults
        READ_NEXT     <= '0';
        REPLACE_STORE <= '0';
        REPLACE_CLEAR <= '0';
        REPLACE_IX <= (others => '1');
        REPLACE_ADDR <= (others => '0');
        REPLACE_DATA <= (others => '0');
        ST_SINK_VALID <= '0';
        ST_SINK_DATA  <= x"FF";


        case state is
            when S_INVALID =>
                ST_SINK_DATA <= x"EE";
                ST_SINK_VALID <= '1';
                
            when S_IDLE =>
                null;
                
            when S_CMD =>
                ST_SINK_DATA <= x"CC";
                ST_SINK_VALID <= '1';

            when S_REPLACE =>
                if byte_cnt = 1 + 3 + 8 then
                    REPLACE_IX <= replace_reg(95 downto 88);
                    REPLACE_ADDR <= replace_reg(87 downto 64);
                    REPLACE_DATA <= replace_reg(63 downto 0);
                    REPLACE_STORE <= '1';
                else
                    ST_SINK_DATA <= b"0000" & std_logic_vector(byte_cnt);
                    ST_SINK_VALID <= '1';
                end if;

            when S_CLEAR =>
                REPLACE_CLEAR <= '1';
                ST_SINK_DATA <= x"AC";
                ST_SINK_VALID <= '1';

            when S_LATCH =>
                -- Pulse READ_NEXT to advance BUFCTRL pointer
                if READ_READY = '1' then
                    READ_NEXT <= '1';
                    ST_SINK_DATA <= READ_ADDR(23 downto 16);
                else
                    ST_SINK_DATA <= x"FF";
                end if;
                ST_SINK_VALID <= '1';

            when S_SEND =>
                if ss_n = '1' then
                    ST_SINK_VALID <= '0';
                else
                    ST_SINK_VALID <= '1';
                    ST_SINK_DATA <= shift_reg(63 downto 56);
                    case to_integer(byte_cnt(2 downto 0)) is
                        when 0 => ST_SINK_DATA <= shift_reg(63 downto 56);
                        when 1 => ST_SINK_DATA <= shift_reg(55 downto 48);
                        when 2 => ST_SINK_DATA <= shift_reg(47 downto 40);
                        when 3 => ST_SINK_DATA <= shift_reg(39 downto 32);
                        when 4 => ST_SINK_DATA <= shift_reg(31 downto 24);
                        when 5 => ST_SINK_DATA <= shift_reg(23 downto 16);
                        when 6 => ST_SINK_DATA <= shift_reg(15 downto 8);
                        when 7 => ST_SINK_DATA <= shift_reg(7 downto 0);
                        when others => null;
                    end case;
                end if;

            when others =>
                null;
        end case;
    end process COMB_OUT;

    -- SYNC: Synchronous state register
    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state     <= S_IDLE;
                shift_reg <= ALL_FF;
                byte_cnt  <= (others => '0');
                replace_reg <= (others => '1');
                ss_n      <= '1';
                ss_n_ff1  <= '1';
                ss_n_prev  <= '1';
            else
                -- Synchronizer chain for SS_N
                ss_n_ff1 <= SPI_SS_N;
                ss_n_prev <= ss_n_ff1;
                ss_n <= ss_n_prev;

                -- State register updates
                state     <= state_next;
                shift_reg <= shift_reg_next;
                byte_cnt  <= byte_cnt_next;
                replace_reg <= replace_reg_next;
            end if;
        end if;
    end process SYNC;

end architecture RTL;
