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
    constant RESET_spi_FF : spi_t := (clk => '0', cs_n => '1', mosi => '0');

    signal state_Q, state_D : state_t := RESET_STATE;
    signal spi_FF1, spi_FF2, spi_Q, spi_QQ : spi_t := RESET_spi_FF;
begin
    SYNC_SPI: process(CLK)
    begin        
        if RESET_N = '0' then
             spi_FF1 <= RESET_spi_FF;
             spi_FF2 <= RESET_spi_FF;
             spi_QQ <= RESET_spi_FF;
             spi_Q  <= RESET_spi_FF;
        elsif rising_edge(CLK) then
             spi_FF1 <= (clk => SPI_CLK, cs_n => SPI_CS_N, mosi => SPI_MOSI);
             spi_FF2 <= spi_FF1;
             spi_Q <= spi_FF2;
             spi_QQ <= spi_Q;
        end if;        
    end process;

    COMB_NEXT: process(spi_Q, spi_QQ, state_Q)
    variable new_shift_reg : std_logic_vector(23 downto 0);
    begin
        state_D <= state_Q;
        if spi_QQ.cs_n = '1' and spi_Q.cs_n = '0' then   
            state_D.count <= (others => '0');
            state_D.step <= GET_CMD;
            state_D.bit_count <= (others => '0');
        elsif spi_QQ.cs_n = '0' and spi_Q.cs_n = '1' then
            state_D.step <= IDLE;
        else
            if spi_Q.clk = '1' and spi_QQ.clk = '0' then
                new_shift_reg := state_Q.shift_reg(22 downto 0) & spi_Q.mosi;
                if state_Q.step /= COUNT_DATA then
                    state_D.shift_reg <= new_shift_reg;
                end if;
                case state_Q.step is
                    when GET_CMD =>
                        if state_Q.bit_count = 7 then
                           if new_shift_reg(7 downto 0) = CMD_READ then
                                state_D.step <= GET_ADDR;
                                state_D.addr_byte <= "00";
                            else
                                state_D.step <= IDLE;
                            end if;
                        end if;
                        state_D.bit_count <= state_Q.bit_count + 1;
                    when GET_ADDR =>
                        if state_Q.bit_count = 7 then
                            state_D.addr_byte <= state_Q.addr_byte + 1;
                            case state_Q.addr_byte is
                                when "10" =>
                                    state_D.addr_reg <= new_shift_reg;
                                    state_D.step <= COUNT_DATA;
                                when others =>
                                    null;
                            end case;
                        end if;
                        state_D.bit_count <= state_Q.bit_count + 1;
                    when COUNT_DATA | REPLACE_DATA =>
                        if state_Q.bit_count = 7 then
                            state_D.count <= state_Q.count + 1;
                        end if;
                        state_D.bit_count <= state_Q.bit_count + 1;
                        state_D.replace_reg <= state_Q.replace_reg(6 downto 0) & '0';
                    when others =>
                        null;
                end case;
            elsif state_Q.step = COUNT_DATA or state_Q.step = REPLACE_DATA then
                if MATCH_VALID = '1' then
                    state_D.step <= REPLACE_DATA;
                    if state_Q.bit_count = 0 then
                        state_D.replace_reg <= MATCH_DATA;
                    end if;
                else
                    state_D.step <= COUNT_DATA;
                end if;
            end if;
        end if;
    end process;

    COMB_OUT: process(spi_Q, spi_QQ, state_Q)
    begin
        ADDR_OUT <= state_Q.addr_reg;
        BYTE_COUNT <= std_logic_vector(state_Q.count);
        STROBE <= '0';
        MOSI_EN <= '0';
        SPI_MISO <= state_Q.replace_reg(7);
        if (state_Q.step = COUNT_DATA or state_Q.step = REPLACE_DATA) and spi_QQ.cs_n = '0' and spi_Q.cs_n = '1' and state_Q.count > 0 then
            STROBE <= '1';
        end if;
        if state_Q.step = REPLACE_DATA then
            MOSI_EN <= '1';
        end if;
    end process;

    SYNC_REG: process(CLK,RESET_N)
    begin
        if RESET_N = '0' then
            state_Q <= RESET_STATE;
        elsif rising_edge(CLK) then
            state_Q <= state_D;
        end if;
    end process;

end architecture RTL;
