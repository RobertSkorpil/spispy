library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity SPISPY is
    port (
        RESET_N    : in  std_logic;
        CLK        : in  std_logic;
        
        SPI_CLK    : in  std_logic;
        SPI_CS_N   : in  std_logic;
        SPI_MOSI   : in  std_logic;
        SPI_MISO   : out std_logic;
        MOSI_EN    : out std_logic;
        
        ADDR_OUT   : out std_logic_vector(23 downto 0);
        BYTE_COUNT : out std_logic_vector(23 downto 0);
        STROBE     : out std_logic --;

        MATCH_DATA : in std_logic_vector(63 downto 0);
        MATCH_VALID: in std_logic
    );
end entity SPISPY;

architecture RTL of SPISPY is
    constant CMD_READ : std_logic_vector(7 downto 0) := x"03";
    
    type step_t is (IDLE, GET_CMD, GET_ADDR, COUNT_DATA, REPLACE_DATA);
    type state_t is record
        step        : step_t;
        shift_reg   : std_logic_vector(23 downto 0);
        count       : unsigned(23 downto 0);
        bit_count   : unsigned(2 downto 0);
        addr_byte   : unsigned(1 downto 0);
        replace_reg : std_logic_vector(63 downto 0);
        replace_count : unsigned(5 downto 0);
    end record;

    type spi_t is record
        clk       : std_logic;
        cs_n      : std_logic;
        mosi      : std_logic;
    end record;

    constant RESET_STATE : state_t := (step => IDLE, shift_reg => (others => '0'), count => (others => '0'), bit_count => (others => '0'), addr_byte => (others => '0'), replace_reg => (others => '0'), replace_count => (others => '0'));
    constant RESET_SPI_FF : spi_t := (clk => '0', cs_n => '1', mosi => '0');

    signal state : state_t := RESET_STATE;
    signal next_state : state_t := RESET_STATE;
    signal sync_spi_ff1 : spi_t := RESET_SPI_FF;
    signal sync_spi_ff2 : spi_t := RESET_SPI_FF;
    signal prev_spi : spi_t := RESET_SPI_FF;
    signal spi : spi_t := RESET_SPI_FF;
    signal addr : std_logic_vector(23 downto 0) := (others => '0');
    signal addr_enable : std_logic := '0';
begin
    SYNC_SPI: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                sync_spi_ff1 <= RESET_SPI_FF;
                sync_spi_ff2 <= RESET_SPI_FF;
                prev_spi <= RESET_SPI_FF;
                spi <= RESET_SPI_FF;
            else
                sync_spi_ff1.clk <= SPI_CLK;
                sync_spi_ff1.cs_n <= SPI_CS_N;
                sync_spi_ff1.mosi <= SPI_MOSI;
                sync_spi_ff2 <= sync_spi_ff1;
                spi <= sync_spi_ff2;
                prev_spi <= spi;
            end if;
        end if;
    end process;

    COMB_NEXT: process(spi, prev_spi, state)
    variable new_shift_reg : std_logic_vector(23 downto 0);
    begin
        next_state <= state;
        addr_enable <= '0';
        if prev_spi.cs_n = '1' and spi.cs_n = '0' then   
		      next_state.count <= (others => '0');
            next_state.step <= GET_CMD;
            next_state.bit_count <= (others => '0');
        elsif prev_spi.cs_n = '0' and spi.cs_n = '1' then
            next_state.step <= IDLE;
        elsif addr_enable = '1' and MATCH_VALID = '1' then
            next_state.step <= REPLACE_DATA;
            next_state.replace_reg <= MATCH_DATA;
            next_state.replace_count <= 0;
        elsif spi.clk = '1' and prev_spi.clk = '0' then
            new_shift_reg := state.shift_reg(22 downto 0) & spi.mosi;
            next_state.shift_reg <= new_shift_reg;
            case state.step is
                when GET_CMD =>
                    if state.bit_count = 7 then
                       if new_shift_reg(7 downto 0) = CMD_READ then
                            next_state.step <= GET_ADDR;
                            next_state.addr_byte <= "00";
                        else
                            next_state.step <= IDLE;
                        end if;
                    end if;
                    next_state.bit_count <= state.bit_count + 1;
                when GET_ADDR =>
                    if state.bit_count = 7 then
                        next_state.addr_byte <= state.addr_byte + 1;
                        case state.addr_byte is
                            when "10" =>
                                addr_enable <= '1';
                                next_state.step <= COUNT_DATA;
                            when others =>
                                null;
                        end case;
                    end if;
                    next_state.bit_count <= state.bit_count + 1;
                when COUNT_DATA =>
                    if state.bit_count = 7 then
                        next_state.count <= state.count + 1;
                    end if;
                    next_state.bit_count <= state.bit_count + 1;
                when REPLACE_DATA =>
                    if state.replace_count + 1 = 64 then
                        next_state.step <= IDLE;
                    else
                        next_state.replace_count <= state.replace_count + 1;
                        next_state.replace_reg <= state.replace_reg(63 downto 1) & '0';
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    COMB_OUT: process(spi, prev_spi, state, addr)
    begin
        ADDR_OUT <= addr;
        BYTE_COUNT <= std_logic_vector(state.count);
        STROBE <= '0';
        MOSI_EN <= '0';
        SPI_MISO <= state.replace_reg(63);
        if state.step = COUNT_DATA and prev_spi.cs_n = '0' and spi.cs_n = '1' and state.count > 0 then
            STROBE <= '1';
        elsif state.step = REPLACE_DATA then
            MOSI_EN <= '1';
            if prev_spi.clk = '0' and spi.clk = '1' state.replace_count = 0 then
                BYTE_COUNT <= (others => '1');
                STROBE <= '1';
            end if;
        end if;
    end process;

    SYNC_REG: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                state <= RESET_STATE;
                addr <= (others => '0');
            else
                state <= next_state;
                if addr_enable = '1' then
                    addr <= next_state.shift_reg(23 downto 0);
                end if;
            end if;
        end if;
    end process;

end architecture RTL;
