library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- COMM_SPI_SLAVE: Custom SPI slave controller (replaces Avalon-ST IP).
--
-- SPI Mode 0 (CPOL=0, CPHA=0): sample MOSI on rising SCLK, shift MISO on falling SCLK.
-- All external SPI inputs (SCLK, SS_N, MOSI) pass through a two-stage synchronizer.
--
-- Byte interface to the rest of the design:
--   RX_DATA / RX_VALID / RX_READY  — received byte from master (MOSI), active-high strobe
--   TX_DATA / TX_VALID / TX_READY  — byte to send to master (MISO), consumed on handshake
--
-- Between CS assertion and deassertion the core clocks bytes in and out continuously.
-- The TX side pre-loads a byte whenever TX_VALID is high and the core is ready for the
-- next byte; if no byte is provided, 0xFF is sent (bus idle / default high).

entity COMM_SPI_SLAVE is
    port (
        CLK        : in  std_logic;
        RESET_N    : in  std_logic;

        -- SPI bus (directly from pads)
        SPI_SCLK   : in  std_logic;
        SPI_SS_N   : in  std_logic;
        SPI_MOSI   : in  std_logic;
        SPI_MISO   : out std_logic;

        -- Received byte from master (MOSI direction)
        RX_DATA    : out std_logic_vector(7 downto 0);
        RX_VALID   : out std_logic;
        RX_READY   : in  std_logic;

        -- Byte to transmit to master (MISO direction)
        TX_DATA    : in  std_logic_vector(7 downto 0);
        TX_VALID   : in  std_logic;
        TX_READY   : out std_logic
    );
end entity COMM_SPI_SLAVE;

architecture RTL of COMM_SPI_SLAVE is

    -- ----------------------------------------------------------------
    -- Two-stage synchronizer flip-flops
    -- ----------------------------------------------------------------
    signal sclk_ff1, sclk_ff2 : std_logic := '0';
    signal ss_n_ff1, ss_n_ff2 : std_logic := '1';
    signal mosi_ff1, mosi_ff2 : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of sclk_ff1 : signal is "TRUE";
    attribute ASYNC_REG of sclk_ff2 : signal is "TRUE";
    attribute ASYNC_REG of ss_n_ff1 : signal is "TRUE";
    attribute ASYNC_REG of ss_n_ff2 : signal is "TRUE";
    attribute ASYNC_REG of mosi_ff1 : signal is "TRUE";
    attribute ASYNC_REG of mosi_ff2 : signal is "TRUE";

    -- Synchronized & previous-cycle versions for edge detection
    signal sclk_s, sclk_prev : std_logic := '0';
    signal ss_n_s, ss_n_prev : std_logic := '1';
    signal mosi_s            : std_logic := '0';

    -- Shift register and bit counter
    signal shift_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal shift_out  : std_logic_vector(7 downto 0) := (others => '1');
    signal bit_cnt    : unsigned(2 downto 0) := (others => '0');

    -- RX holding register
    signal rx_data_r  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_r : std_logic := '0';

    -- TX handshake
    signal tx_ready_r   : std_logic := '0';
    signal tx_loaded    : std_logic := '0';  -- a fresh TX byte has been loaded into shift_out

    -- Edge helpers
    signal sclk_rise : std_logic;
    signal sclk_fall : std_logic;
    signal ss_assert : std_logic;  -- CS just went active  (falling edge of SS_N)
    signal ss_deassert : std_logic; -- CS just went inactive (rising edge of SS_N)

begin

    -- ----------------------------------------------------------------
    -- Synchronizer + edge-detect register
    -- ----------------------------------------------------------------
    process (CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                sclk_ff1  <= '0';
                sclk_ff2  <= '0';
                ss_n_ff1  <= '1';
                ss_n_ff2  <= '1';
                mosi_ff1  <= '0';
                mosi_ff2  <= '0';
                sclk_prev <= '0';
                ss_n_prev <= '1';
            else
                -- Stage 1
                sclk_ff1 <= SPI_SCLK;
                ss_n_ff1 <= SPI_SS_N;
                mosi_ff1 <= SPI_MOSI;
                -- Stage 2
                sclk_ff2 <= sclk_ff1;
                ss_n_ff2 <= ss_n_ff1;
                mosi_ff2 <= mosi_ff1;
                -- Previous cycle (for edge detection)
                sclk_prev <= sclk_s;
                ss_n_prev <= ss_n_s;
            end if;
        end if;
    end process;

    sclk_s <= sclk_ff2;
    ss_n_s <= ss_n_ff2;
    mosi_s <= mosi_ff2;

    sclk_rise  <= '1' when sclk_s = '1' and sclk_prev = '0' else '0';
    sclk_fall  <= '1' when sclk_s = '0' and sclk_prev = '1' else '0';
    ss_assert  <= '1' when ss_n_s = '0' and ss_n_prev = '1' else '0';
    ss_deassert <= '1' when ss_n_s = '1' and ss_n_prev = '0' else '0';

    -- ----------------------------------------------------------------
    -- SPI shift engine + byte-level handshake
    -- ----------------------------------------------------------------
    process (CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                shift_in   <= (others => '0');
                shift_out  <= (others => '1');
                bit_cnt    <= (others => '0');
                rx_data_r  <= (others => '0');
                rx_valid_r <= '0';
                tx_ready_r <= '0';
                tx_loaded  <= '0';
            else
                -- Default: clear one-cycle strobes
                -- RX_VALID stays high until consumed by RX_READY
                if rx_valid_r = '1' and RX_READY = '1' then
                    rx_valid_r <= '0';
                end if;

                -- --------------------------------------------------------
                -- CS asserted: reset bit counter, pre-load first TX byte
                -- --------------------------------------------------------
                if ss_assert = '1' then
                    bit_cnt   <= (others => '0');
                    tx_loaded <= '0';

                    -- Try to grab the first TX byte immediately
                    if TX_VALID = '1' then
                        shift_out <= TX_DATA;
                        tx_loaded <= '1';
                    else
                        shift_out <= x"FF";
                    end if;
                    tx_ready_r <= '0';

                -- --------------------------------------------------------
                -- CS deasserted: go idle
                -- --------------------------------------------------------
                elsif ss_deassert = '1' then
                    tx_ready_r <= '0';
                    tx_loaded  <= '0';

                -- --------------------------------------------------------
                -- CS is active: process SPI clocks
                -- --------------------------------------------------------
                elsif ss_n_s = '0' then

                    -- Rising SCLK: sample MOSI
                    if sclk_rise = '1' then
                        shift_in <= shift_in(6 downto 0) & mosi_s;

                        if bit_cnt = 7 then
                            -- Completed a full byte
                            rx_data_r  <= shift_in(6 downto 0) & mosi_s;
                            rx_valid_r <= '1';
                            bit_cnt    <= (others => '0');

                            -- Signal we're ready for next TX byte
                            tx_ready_r <= '1';
                            tx_loaded  <= '0';
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;

                    -- Falling SCLK: shift out MISO
                    if sclk_fall = '1' then
                        shift_out <= shift_out(6 downto 0) & '1';
                    end if;

                    -- TX loading: when tx_ready_r is asserted, latch next byte
                    if tx_ready_r = '1' and TX_VALID = '1' then
                        shift_out  <= TX_DATA;
                        tx_ready_r <= '0';
                        tx_loaded  <= '1';
                    end if;

                end if;  -- ss_n_s = '0'
            end if;  -- RESET_N
        end if;  -- rising_edge
    end process;

    -- ----------------------------------------------------------------
    -- Output assignments
    -- ----------------------------------------------------------------
    SPI_MISO  <= shift_out(7) when ss_n_s = '0' else 'Z';
    RX_DATA   <= rx_data_r;
    RX_VALID  <= rx_valid_r;
    TX_READY  <= tx_ready_r;

end architecture RTL;
