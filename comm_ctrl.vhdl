library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- COMM_CTRL: Bridge between comm_spi Avalon-ST interface and BUFCTRL read port.
--
-- No command byte is used. As soon as the SPI master begins clocking,
-- this entity streams out the next available 64-bit data word
-- (READ_ADDR & READ_COUNT & READ_TIME) byte-by-byte, MSB first.
-- If no entry is available (READ_READY = '0'), all xFF bytes are sent.
-- After latching an entry, READ_NEXT is pulsed to advance the BUFCTRL
-- read pointer.

entity COMM_CTRL is
    port (
        CLK            : in  std_logic;
        RESET          : in  std_logic;

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
        SPI_SS_N       : in  std_logic
    );
end entity COMM_CTRL;

architecture RTL of COMM_CTRL is

    constant ALL_FF : std_logic_vector(63 downto 0) := (others => '1');

    type state_t is (S_IDLE, S_LATCH, S_SEND);

    signal state      : state_t := S_IDLE;
    signal shift_reg  : std_logic_vector(63 downto 0) := (others => '1');
    signal byte_cnt   : unsigned(2 downto 0) := (others => '0');
    signal read_next_i : std_logic := '0';
    signal ss_n_d     : std_logic := '1';

begin

    READ_NEXT <= read_next_i;

    -- Always accept source data (MOSI bytes) — we ignore them
    ST_SOURCE_READY <= '1';

    process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                state      <= S_IDLE;
                shift_reg  <= ALL_FF;
                byte_cnt   <= (others => '0');
                read_next_i <= '0';
                ss_n_d     <= '1';
                ST_SINK_VALID <= '0';
                ST_SINK_DATA  <= (others => '1');
            else
                ss_n_d <= SPI_SS_N;
                read_next_i <= '0';

                case state is
                    when S_IDLE =>
                        ST_SINK_VALID <= '0';
                        -- Detect falling edge of SS_N (start of transaction)
                        if ss_n_d = '1' and SPI_SS_N = '0' then
                            state <= S_LATCH;
                        end if;

                    when S_LATCH =>
                        -- Latch current BUFCTRL output and advance pointer
                        if READ_READY = '1' then
                            shift_reg <= READ_ADDR & READ_COUNT & READ_TIME;
                            read_next_i <= '1';
                        else
                            shift_reg <= ALL_FF;
                        end if;
                        byte_cnt <= (others => '0');
                        -- Present first byte immediately
                        ST_SINK_VALID <= '1';
                        if READ_READY = '1' then
                            ST_SINK_DATA <= READ_ADDR(23 downto 16);
                        else
                            ST_SINK_DATA <= x"FF";
                        end if;
                        state <= S_SEND;

                    when S_SEND =>
                        if SPI_SS_N = '1' then
                            -- Transaction ended
                            ST_SINK_VALID <= '0';
                            state <= S_IDLE;
                        elsif ST_SINK_READY = '1' then
                            -- SPI core consumed the byte, advance
                            if byte_cnt = 7 then
                                -- All 8 bytes sent, keep presenting xFF
                                -- until SS_N goes high
                                ST_SINK_DATA <= x"FF";
                                ST_SINK_VALID <= '1';
                            else
                                byte_cnt <= byte_cnt + 1;
                                -- Next byte from shift register
                                -- byte_cnt=0 means byte 0 was taken, present byte 1
                                case to_integer(byte_cnt + 1) is
                                    when 1 => ST_SINK_DATA <= shift_reg(55 downto 48);
                                    when 2 => ST_SINK_DATA <= shift_reg(47 downto 40);
                                    when 3 => ST_SINK_DATA <= shift_reg(39 downto 32);
                                    when 4 => ST_SINK_DATA <= shift_reg(31 downto 24);
                                    when 5 => ST_SINK_DATA <= shift_reg(23 downto 16);
                                    when 6 => ST_SINK_DATA <= shift_reg(15 downto 8);
                                    when 7 => ST_SINK_DATA <= shift_reg(7 downto 0);
                                    when others => ST_SINK_DATA <= x"FF";
                                end case;
                                ST_SINK_VALID <= '1';
                            end if;
                        end if;

                    when others =>
                        state <= S_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture RTL;
