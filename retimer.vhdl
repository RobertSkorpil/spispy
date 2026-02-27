library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- SPI retimer / delay-line pass-through.
-- Sample async SPI pins on fast_clk, then output delayed, registered versions.
--
-- Use cases:
--  - fix hold-time issues caused by unbalanced FPGA routing when used as "wire"
--  - tune skew by adding delay to selected signals (especially MISO)
--
-- Notes:
--  - fast_clk must be free-running and significantly faster than SPI SCK.
--  - This adds up to 1 tick of sampling uncertainty (quantization) + configured delay.
--  - For very high SPI speeds, use proper IO DDR/registering and timing constraints.

entity spi_retimer_delay is
  generic (
    G_FAST_HZ        : integer := 200_000_000; -- informational only
    -- Delay in fast_clk ticks (1 tick @ 200 MHz = 5 ns)
    G_DLY_SCK        : natural := 0;
    G_DLY_CSN        : natural := 0;
    G_DLY_MOSI       : natural := 0;
    G_DLY_MISO       : natural := 0;

    -- If true, keep SCK purely combinational (no sampling/quantization).
    -- Often best to leave TRUE and only delay data/CS.
    G_SCK_COMB       : boolean := true
  );
  port (
    fast_clk   : in  std_logic;
    rst_n      : in  std_logic;

    -- Upstream (master side) pins
    sck_up     : in  std_logic;
    csn_up     : in  std_logic;
    mosi_up    : in  std_logic;
    miso_up    : out std_logic;

    -- Downstream (flash side) pins
    sck_dn     : out std_logic;
    csn_dn     : out std_logic;
    mosi_dn    : out std_logic;
    miso_dn    : in  std_logic
  );
end entity;

architecture rtl of spi_retimer_delay is

  -- Shift-register delay line for single-bit signals.
  -- Returns signal delayed by N ticks (N=0 => combinational pass of sampled input).
  function f_len(n : natural) return natural is
  begin
    if n = 0 then return 1; else return n+1; end if;
  end function;

  -- sampled inputs (in fast_clk domain)
  signal sck_s    : std_logic := '0';
  signal csn_s    : std_logic := '1';
  signal mosi_s   : std_logic := '0';
  signal miso_s   : std_logic := '0';

  -- delay-line storage
  signal sck_pipe  : std_logic_vector(f_len(G_DLY_SCK)-1 downto 0)  := (others => '0');
  signal csn_pipe  : std_logic_vector(f_len(G_DLY_CSN)-1 downto 0)  := (others => '1');
  signal mosi_pipe : std_logic_vector(f_len(G_DLY_MOSI)-1 downto 0) := (others => '0');
  signal miso_pipe : std_logic_vector(f_len(G_DLY_MISO)-1 downto 0) := (others => '0');

  -- registered outputs
  signal sck_dn_r  : std_logic := '0';
  signal csn_dn_r  : std_logic := '1';
  signal mosi_dn_r : std_logic := '0';
  signal miso_up_r : std_logic := '0';

begin

  ------------------------------------------------------------------------------
  -- Sampling + delay lines
  ------------------------------------------------------------------------------
  p_sample_and_delay : process(fast_clk)
  begin
    if rising_edge(fast_clk) then
      if rst_n = '0' then
        sck_s  <= '0';
        csn_s  <= '1';
        mosi_s <= '0';
        miso_s <= '0';

        sck_pipe  <= (others => '0');
        csn_pipe  <= (others => '1');
        mosi_pipe <= (others => '0');
        miso_pipe <= (others => '0');

        sck_dn_r  <= '0';
        csn_dn_r  <= '1';
        mosi_dn_r <= '0';
        miso_up_r <= '0';
      else
        -- 1) sample raw pins (async → fast_clk domain)
        -- For SPI, this is acceptable because we are NOT interpreting the bus here,
        -- only creating a delayed, registered replica. Any metastability risk is
        -- reduced by the fact that downstream consumers see registered outputs.
        sck_s  <= sck_up;
        csn_s  <= csn_up;
        mosi_s <= mosi_up;
        miso_s <= miso_dn;

        -- 2) shift delay pipelines
        -- Each pipeline length is max(1, N+1). Tap is the last bit.
        sck_pipe(0)  <= sck_s;
        csn_pipe(0)  <= csn_s;
        mosi_pipe(0) <= mosi_s;
        miso_pipe(0) <= miso_s;

        for i in 1 to sck_pipe'length-1 loop
          sck_pipe(i) <= sck_pipe(i-1);
        end loop;

        for i in 1 to csn_pipe'length-1 loop
          csn_pipe(i) <= csn_pipe(i-1);
        end loop;

        for i in 1 to mosi_pipe'length-1 loop
          mosi_pipe(i) <= mosi_pipe(i-1);
        end loop;

        for i in 1 to miso_pipe'length-1 loop
          miso_pipe(i) <= miso_pipe(i-1);
        end loop;

        -- 3) register outputs (clean edges, controlled delay)
        if not G_SCK_COMB then
          sck_dn_r <= sck_pipe(sck_pipe'length-1);
        end if;

        csn_dn_r  <= csn_pipe(csn_pipe'length-1);
        mosi_dn_r <= mosi_pipe(mosi_pipe'length-1);
        miso_up_r <= miso_pipe(miso_pipe'length-1);
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Output assignment
  ------------------------------------------------------------------------------
  -- Often best: keep SCK combinational to avoid quantization/jitter on the clock,
  -- and instead delay MOSI/MISO/CS to meet setup/hold around the original clock edges.
  sck_dn  <= sck_up when G_SCK_COMB else sck_dn_r;

  csn_dn  <= csn_dn_r;
  mosi_dn <= mosi_dn_r;
  miso_up <= miso_up_r;

end architecture;