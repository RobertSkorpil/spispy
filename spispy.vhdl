library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spispy is
    port (
        RESET   : in  std_logic;
        CLK     : in  std_logic;
        CS_N    : in  std_logic;
        SPI_CLK : in  std_logic;
        MOSI    : in  std_logic;
        ADDR    : out std_logic_vector(23 downto 0);
        COUNT   : out std_logic_vector(23 downto 0);
        STROBE  : out std_logic
    );
end entity;

architecture RTL of spispy is
    type STATES is (IDLE, READ_CMD, READ_ADDR, COUNT_DATA);
    signal state      : STATES := IDLE;
    signal bit_ix     : unsigned(2 downto 0) := (others => '0');
    signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal acount     : unsigned(1 downto 0) := (others => '0');
    signal addr_reg   : std_logic_vector(23 downto 0) := (others => '0');
    signal count_reg  : unsigned(23 downto 0) := (others => '0');
    signal ready_reg  : std_logic := '0';
    signal ready_sync : std_logic_vector(3 downto 0) := (others => '0');
begin
    ADDR   <= addr_reg;
    COUNT  <= std_logic_vector(count_reg);
    STROBE <= ready_sync(2) and not ready_sync(3);

    -- Clock-domain crossing: synchronise ready_reg into CLK domain
    process(CLK)
    begin
        if rising_edge(CLK) then
            ready_sync <= ready_sync(2 downto 0) & ready_reg;
        end if;
    end process;

    -- SPI-domain process: captures command, address, and counts data bytes
    process(RESET, CS_N, SPI_CLK, state)
        variable shifted : std_logic_vector(7 downto 0);
    begin
        if RESET = '1' then
            shift_reg <= (others => '0');
            bit_ix    <= (others => '0');
            acount    <= (others => '0');
            addr_reg  <= (others => '0');
            count_reg <= (others => '0');
            ready_reg <= '0';
            state     <= IDLE;
        elsif CS_N = '1' then
            if state = COUNT_DATA then
                ready_reg <= '1';
            end if;
            state <= IDLE;
        elsif CS_N = '0' and state = IDLE then
            bit_ix    <= (others => '0');
            shift_reg <= (others => '0');
            state     <= READ_CMD;
        elsif rising_edge(SPI_CLK) then
            shifted := shift_reg(6 downto 0) & MOSI;
            shift_reg <= shifted;
            case state is
                when READ_CMD =>
                    if bit_ix = 7 then
                        if shifted = x"03" then
                            acount <= (others => '0');
                            state  <= READ_ADDR;
                        else
                            state <= IDLE;
                        end if;
                        shift_reg <= (others => '0');
                        bit_ix    <= (others => '0');
                    else
                        bit_ix <= bit_ix + 1;
                    end if;
                when READ_ADDR =>
                    ready_reg <= '0';
                    if bit_ix = 7 then
                        case acount is
                            when "00" =>
                                addr_reg(23 downto 16) <= shifted;
                            when "01" =>
                                addr_reg(15 downto 8) <= shifted;
                            when "10" =>
                                addr_reg(7 downto 0) <= shifted;
                                state     <= COUNT_DATA;
                                count_reg <= (others => '0');
                            when others =>
                                null;
                        end case;
                        acount <= acount + 1;
                        bit_ix <= (others => '0');
                        shift_reg <= (others => '0');
                    else
                        bit_ix <= bit_ix + 1;
                    end if;
                when COUNT_DATA =>
                    if bit_ix = 7 then
                        count_reg <= count_reg + 1;
                        bit_ix <= (others => '0');
                    else
                        bit_ix <= bit_ix + 1;
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;
end architecture;
