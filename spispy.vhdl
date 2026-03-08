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
        STROBE     : out std_logic;

        MATCH_DATA : in std_logic_vector(7 downto 0);
        MATCH_VALID: in std_logic
    );
end entity SPISPY;

architecture RTL of SPISPY is
    constant CMD_READ : std_logic_vector(7 downto 0) := x"03";
    
    type step_t is (IDLE, GET_CMD, GET_ADDR, COUNT_DATA, REPLACE_DATA);
    type state_t is record
        step        : step_t;
        shift_reg   : std_logic_vector(23 downto 0);
        addr_reg    : std_logic_vector(23 downto 0);
        count       : unsigned(23 downto 0);
        bit_count   : unsigned(2 downto 0);
        addr_byte   : unsigned(1 downto 0);
        replace_reg : std_logic_vector(7 downto 0);
    end record;

    type spi_t is record
        clk       : std_logic;
        cs_n      : std_logic;
        mosi      : std_logic;
    end record;

    constant RESET_STATE : state_t := (step => IDLE, shift_reg => (others => '0'), addr_reg => (others => '0'), count => (others => '0'), bit_count => (others => '0'), addr_byte => (others => '0'), replace_reg => (others => '0'));
    constant RESET_SPI_FF : spi_t := (clk => '0', cs_n => '1', mosi => '0');

    signal state : state_t := RESET_STATE;
    signal next_state : state_t := RESET_STATE;
    signal sync_spi_ff1 : spi_t := RESET_SPI_FF;
    signal sync_spi_ff2 : spi_t := RESET_SPI_FF;
    signal prev_spi : spi_t := RESET_SPI_FF;
    signal spi : spi_t := RESET_SPI_FF;
begin
    SYNC_SPI: process(CLK)
    begin        
        if RESET_N = '0' then
             sync_spi_ff1 <= RESET_SPI_FF;
             sync_spi_ff2 <= RESET_SPI_FF;
             prev_spi <= RESET_SPI_FF;
             spi <= RESET_SPI_FF;
        elsif rising_edge(CLK) then
             sync_spi_ff1.clk <= SPI_CLK;
             sync_spi_ff1.cs_n <= SPI_CS_N;
             sync_spi_ff1.mosi <= SPI_MOSI;
             sync_spi_ff2 <= sync_spi_ff1;
             spi <= sync_spi_ff2;
             prev_spi <= spi;
        end if;        
    end process;

    COMB_NEXT: process(spi, prev_spi, state)
    variable new_shift_reg : std_logic_vector(23 downto 0);
    begin
        next_state <= state;
        if prev_spi.cs_n = '1' and spi.cs_n = '0' then   
            next_state.count <= (others => '0');
            next_state.step <= GET_CMD;
            next_state.bit_count <= (others => '0');
        elsif prev_spi.cs_n = '0' and spi.cs_n = '1' then
            next_state.step <= IDLE;
        else
            if spi.clk = '1' and prev_spi.clk = '0' then
                new_shift_reg := state.shift_reg(22 downto 0) & spi.mosi;
                if state.step /= COUNT_DATA then
                    next_state.shift_reg <= new_shift_reg;
                end if;
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
                                    next_state.addr_reg <= new_shift_reg;
                                    next_state.step <= COUNT_DATA;
                                when others =>
                                    null;
                            end case;
                        end if;
                        next_state.bit_count <= state.bit_count + 1;
                    when COUNT_DATA | REPLACE_DATA =>
                        if state.bit_count = 7 then
                            next_state.count <= state.count + 1;
                        end if;
                        next_state.bit_count <= state.bit_count + 1;
                        next_state.replace_reg <= state.replace_reg(6 downto 0) & '0';
                    when others =>
                        null;
                end case;
            elsif state.step = COUNT_DATA or state.step = REPLACE_DATA then
                if MATCH_VALID = '1' then
                    next_state.step <= REPLACE_DATA;
                    if state.bit_count = 0 then
                        next_state.replace_reg <= MATCH_DATA;
                    end if;
                else
                    next_state.step <= COUNT_DATA;
                end if;
            end if;
        end if;
    end process;

    COMB_OUT: process(spi, prev_spi, state)
    begin
        ADDR_OUT <= state.addr_reg;
        BYTE_COUNT <= std_logic_vector(state.count);
        STROBE <= '0';
        MOSI_EN <= '0';
        SPI_MISO <= state.replace_reg(7);
        if (state.step = COUNT_DATA or state.step = REPLACE_DATA) and prev_spi.cs_n = '0' and spi.cs_n = '1' and state.count > 0 then
            STROBE <= '1';
        elsif state.step = REPLACE_DATA then
            MOSI_EN <= '1';
        end if;
    end process;

    SYNC_REG: process(CLK,RESET_N)
    begin
		if RESET_N = '0' then
			 state <= RESET_STATE;
       elsif rising_edge(CLK) then
			 state <= next_state;
        end if;
    end process;

end architecture RTL;
