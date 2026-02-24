library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- COMM_CTRL: Bridge between comm_spi Avalon-ST interface and BUFCTRL read port.
--
-- Protocol: Master sends a command byte, then clocks out response bytes.
-- CMD_STATUS (0x00): Returns 2 bytes - READ_READY flag and READ_LOST flag
-- CMD_READ   (0x01): Returns 8 bytes - READ_ADDR(3) & READ_COUNT(3) & READ_TIME(2)
--                    Advances buffer pointer if entry was available.

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
        ST_SOURCE_DATA  : in  std_logic_vector(7 downto 0);
        ST_SOURCE_VALID : in  std_logic;
        ST_SOURCE_READY : out std_logic
    );
end entity COMM_CTRL;

architecture RTL of COMM_CTRL is

    constant CMD_STATUS : std_logic_vector(7 downto 0) := x"00";
    constant CMD_READ   : std_logic_vector(7 downto 0) := x"01";

    type state_t is (S_IDLE, S_READ_CMD, S_SEND);

    signal state, state_next : state_t;
    signal shift_reg, shift_reg_next : std_logic_vector(63 downto 0);
    signal read_next_i, read_next_next : std_logic;
    signal sink_data : std_logic_vector(7 downto 0);
    signal sink_valid : std_logic;

begin

    READ_NEXT <= read_next_i;
    ST_SINK_DATA <= sink_data;
    ST_SINK_VALID <= sink_valid;
    ST_SOURCE_READY <= '1';

    -- Process 1: State register (clocked)
    process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state       <= S_IDLE;
                shift_reg   <= (others => '1');
                read_next_i <= '0';
            else
                state       <= state_next;
                shift_reg   <= shift_reg_next;
                read_next_i <= read_next_next;
            end if;
        end if;
    end process;

    -- Process 2: Next state logic (combinational)
    process(state, ST_SOURCE_VALID, ST_SOURCE_DATA, ST_SINK_READY,
            READ_READY, READ_ADDR, READ_COUNT, READ_TIME, shift_reg)
    begin
        state_next     <= state;
        shift_reg_next <= shift_reg;
        read_next_next <= '0';

        case state is
            when S_IDLE =>
                if ST_SOURCE_VALID = '1' then
                    state_next <= S_READ_CMD;
                end if;

            when S_READ_CMD =>
                case ST_SOURCE_DATA is
                    when CMD_STATUS =>
                        shift_reg_next <= x"000000000000" &
                                          "0000000" & READ_READY &
                                          "0000000" & READ_LOST;
                        state_next <= S_SEND;

                    when CMD_READ =>
                        if READ_READY = '1' then
                            shift_reg_next <= READ_ADDR & READ_COUNT & READ_TIME;
                            read_next_next <= '1';
                        else
                            shift_reg_next <= (others => '1');
                        end if;
                        state_next <= S_SEND;

                    when others =>
                        state_next <= S_IDLE;
                end case;

            when S_SEND =>
                if ST_SOURCE_VALID = '0' then
                    state_next <= S_IDLE;
                elsif ST_SINK_READY = '1' then
                    shift_reg_next <= shift_reg(55 downto 0) & x"FF";
                end if;

            when others =>
                state_next <= S_IDLE;
        end case;
    end process;

    -- Process 3: Output logic (combinational)
    process(state, shift_reg)
    begin
        sink_valid <= '0';
        sink_data  <= x"FF";

        case state is
            when S_SEND =>
                sink_valid <= '1';
                sink_data  <= shift_reg(63 downto 56);

            when others =>
                null;
        end case;
    end process;

end architecture RTL;
