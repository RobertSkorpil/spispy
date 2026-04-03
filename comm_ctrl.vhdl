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
        READ_CLEAR     : out std_logic;

        -- Avalon-ST sink (we send bytes TO the SPI core for MISO)
        ST_SINK_DATA   : out std_logic_vector(7 downto 0);
        ST_SINK_VALID  : out std_logic;
        ST_SINK_READY  : in  std_logic;

        -- Avalon-ST source (we receive bytes FROM the SPI core, MOSI)
        ST_SOURCE_DATA  : in  std_logic_vector(7 downto 0);
        ST_SOURCE_VALID : in  std_logic;
        ST_SOURCE_READY : out std_logic;

        -- Active-low slave select, directly from the SPI bus
        SPI_SS_N       : in  std_logic;

        PROG_EN     : out std_logic;    
        PROG_DATA   : out std_logic_vector(7 downto 0);
        PROG_STROBE : out std_logic;
        PROG_DUMP   : out std_logic;

        DUMP_DATA   : in std_logic_vector(7 downto 0)
    );
end entity COMM_CTRL;

architecture RTL of COMM_CTRL is

    constant ALL_FF : std_logic_vector(63 downto 0) := (others => '1');

    type state_t is (S_IDLE, S_CMD, S_LATCH, S_PROG, S_DUMP, S_CLEAR_BUF, S_SEND, S_INVALID);

    signal state_D, state_Q         : state_t := S_IDLE;
    signal shift_reg_D, shift_reg_Q : std_logic_vector(63 downto 0) := (others => '1');
    signal byte_cnt_D, byte_cnt_Q   : unsigned(3 downto 0) := (others => '0');
    signal ss_n_ff1, ss_n_ff2, ss_n_Q : std_logic := '1';

begin

    -- Always accept source data (MOSI bytes) — we ignore them
    ST_SOURCE_READY <= '1';

    -- COMB_NEXT: Combinational logic for next state
    COMB_NEXT: process(all)
    begin
        -- Default: hold current values
        state_D     <= state_Q;
        shift_reg_D <= shift_reg_Q;
        byte_cnt_D  <= byte_cnt_Q;

        if ST_SINK_READY = '1' then
            shift_reg_D <= shift_reg_Q(55 downto 0) & x"FF";
        end if;

        if ss_n_Q = '1' then
            state_D <= S_IDLE;
            byte_cnt_D <= (others => '0');
        else
            case state_Q is
                when S_INVALID =>
                    null;
                when S_IDLE =>
                    state_D <= S_CMD;
                when S_CMD =>
                    if ST_SOURCE_VALID = '1' then
                        case ST_SOURCE_DATA(1 downto 0) is
                            when b"00" =>
                                state_D <= S_CLEAR_BUF;
                            when b"01" =>
                                state_D <= S_LATCH;
                            when b"10" =>
                                state_D <= S_PROG;
                            when b"11" =>
                                state_D <= S_DUMP;
                            when others =>
                                state_D <= S_INVALID;
                        end case;
                    end if;
                when S_PROG =>
                    if ST_SOURCE_VALID = '1' then
                        byte_cnt_D <= byte_cnt_Q + 1;
                    end if;
                when S_DUMP =>
                    null;
                when S_CLEAR_BUF =>
                    if ST_SOURCE_VALID = '1' then
                        state_D <= S_INVALID;
                    end if;
                when S_LATCH =>
                    -- Latch current BUFCTRL output
                    if READ_READY = '1' then
                        shift_reg_D <= READ_ADDR & READ_COUNT & READ_TIME;
                    else
                        shift_reg_D <= ALL_FF;
                    end if;
                    byte_cnt_D <= (others => '0');
                    state_D <= S_SEND;

                when S_SEND =>
                    if ST_SINK_READY = '1' then
                        if byte_cnt_Q /= 7 then
                            byte_cnt_D <= byte_cnt_Q + 1;
                        else
                            state_D <= S_INVALID;
                        end if;
                    end if;

                when others =>
                    state_D <= S_IDLE;
            end case;
        end if;
    end process COMB_NEXT;

    -- COMB_OUT: Combinational logic for outputs
    COMB_OUT: process(all)
    begin
        -- Defaults
        READ_NEXT     <= '0';
        READ_CLEAR    <= '0';
        PROG_EN       <= '0';
        PROG_DATA     <= ST_SOURCE_DATA;
        PROG_STROBE   <= '0';
        PROG_DUMP     <= '0';
        ST_SINK_VALID <= '0';
        ST_SINK_DATA  <= x"FF";

        case state_Q is
            when S_INVALID =>
                ST_SINK_DATA <= x"EE";
                ST_SINK_VALID <= '1';
                
            when S_IDLE =>
                null;
                
            when S_CMD =>
                ST_SINK_DATA <= x"CC";
                ST_SINK_VALID <= '1';

            when S_PROG =>
                PROG_EN <= '1';
                PROG_STROBE <= ST_SOURCE_VALID;
                ST_SINK_DATA <= b"0000" & std_logic_vector(byte_cnt_Q);
                ST_SINK_VALID <= '1';

            when S_DUMP =>
                PROG_DUMP <= '1';
                PROG_STROBE <= ST_SINK_READY;
                ST_SINK_DATA <= DUMP_DATA;
                ST_SINK_VALID <= '1';

            when S_CLEAR_BUF =>
                READ_CLEAR <= '1';
                ST_SINK_DATA <= x"AB";
                ST_SINK_VALID <= '1';

            when S_LATCH =>
                -- Pulse READ_NEXT to advance BUFCTRL pointer
                if READ_READY = '1' then
                    READ_NEXT <= '1';
                end if;

            when S_SEND =>
                ST_SINK_DATA <= shift_reg_Q(63 downto 56);
                ST_SINK_VALID <= '1';

            when others =>
                null;
        end case;
    end process COMB_OUT;

    -- SYNC: Synchronous state register
    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state_Q     <= S_IDLE;
                shift_reg_Q <= ALL_FF;
                byte_cnt_Q  <= (others => '0');
                ss_n_Q      <= '1';
                ss_n_ff1    <= '1';
                ss_n_ff2    <= '1';
            else
                -- Synchronizer chain for SS_N
                ss_n_ff1 <= SPI_SS_N;
                ss_n_ff2 <= ss_n_ff1;
                ss_n_Q   <= ss_n_ff2;

                -- State register updates
                state_Q     <= state_D;
                shift_reg_Q <= shift_reg_D;
                byte_cnt_Q  <= byte_cnt_D;
            end if;
        end if;
    end process SYNC;

end architecture RTL;
