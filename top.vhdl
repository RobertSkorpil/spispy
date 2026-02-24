library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TOP is
    port (
        RESET_N       : in std_logic;
        CLK           : in std_logic;

        MCU_SPI_SS_N  : in std_logic;
        MCU_SPI_CLK   : in std_logic;
        MCU_SPI_MOSI  : in std_logic;
        MCU_SPI_MISO  : out std_logic;

        FLASH_SPI_SS_N : out std_logic;
        FLASH_SPI_CLK  : out std_logic;
        FLASH_SPI_MOSI : out std_logic;
        FLASH_SPI_MISO : in std_logic;

        COMM_SPI_SS_N : in std_logic;
        COMM_SPI_CLK  : in std_logic;
        COMM_SPI_MOSI : in std_logic;
        COMM_SPI_MISO : inout std_logic;

        LED_READY     : out std_logic;
        LED_OVERFLOW  : out std_logic;
        LED_MCU_ACT   : out std_logic;
        LED_COMM_ACT  : out std_logic;
		  
        GPIO_READY    : out std_logic;
		  
        DBG_SPI_SS_N  : out std_logic;
        DBG_SPI_CLK   : out std_logic;
        DBG_SPI_MISO  : out std_logic 
    );
end entity;

architecture RTL of TOP is
    signal time_val: std_logic_vector(15 downto 0);
	 
    signal spy_addr_out   : std_logic_vector(23 downto 0);
    signal spy_byte_count : std_logic_vector(23 downto 0);
    signal spy_strobe     : std_logic;
    signal read_next      : std_logic;
    signal read_ready     : std_logic;
    signal read_lost      : std_logic;
    signal mem_write      : std_logic;
    signal mem_addr_in    : std_logic_vector(8 downto 0);
    signal mem_addr_out   : std_logic_vector(8 downto 0);
    signal mem_data_in    : std_logic_vector(63 downto 0);
    signal mem_data_out   : std_logic_vector(63 downto 0);
    signal mosi_inject    : std_logic;
    signal mosi_inj_data  : std_logic;

    -- BUFCTRL read-side data
    signal read_addr      : std_logic_vector(23 downto 0);
    signal read_count     : std_logic_vector(23 downto 0);
    signal read_time      : std_logic_vector(15 downto 0);

    -- Avalon-ST between comm_spi and spi_resp
    signal st_sink_data   : std_logic_vector(7 downto 0);
    signal st_sink_valid  : std_logic;
    signal st_sink_ready  : std_logic;
    signal st_source_data : std_logic_vector(7 downto 0);
    signal st_source_valid: std_logic;
    signal st_source_ready: std_logic;
begin
    clock_unit: entity work.CLOCK
    port map (
        RESET_N => RESET_N,
        CLK => CLK,
        TIME_OUT => time_val
    );
	 
	comm_spi_inst: entity work.COMM_SPI
	port map (
        SYSCLK => CLK,
        NRESET => RESET_N,
        MOSI => COMM_SPI_MOSI,
        NSS => COMM_SPI_SS_N,
        MISO => COMM_SPI_MISO,
        SCLK => COMM_SPI_CLK,
        STSINKVALID   => st_sink_valid,
        STSINKDATA    => st_sink_data,
        STSINKREADY   => st_sink_ready,
        STSOURCEVALID => st_source_valid,
        STSOURCEDATA  => st_source_data,
        STSOURCEREADY => st_source_ready
    );
	
	mcu_spi: entity work.SPISPY
	port map (
	    RESET_N => RESET_N,
	    CLK => CLK,
	    SPI_CS_N => MCU_SPI_SS_N,
	    SPI_CLK => MCU_SPI_CLK,
	    SPI_MOSI => MCU_SPI_MOSI,		 
	    ADDR_OUT => spy_addr_out,
	    BYTE_COUNT => spy_byte_count,
	    STROBE => spy_strobe,
        MOSI_EN => mosi_inject
	);
	
	bufctrl: entity work.BUFCTRL
	port map (
        RESET_N => RESET_N,
        CLK => CLK,
        CAP_ADDR => spy_addr_out,
        CAP_COUNT => spy_byte_count,
        CAP_STROBE => spy_strobe,
        CAP_TIME => time_val,

        READ_ADDR  => read_addr,
        READ_COUNT => read_count,
        READ_TIME  => read_time,
        READ_READY => read_ready,
        READ_LOST => read_lost,
        READ_NEXT => read_next,
        MEM_ADDR_IN => mem_addr_in,
        MEM_DATA_IN => mem_data_in,
        MEM_ADDR_OUT => mem_addr_out,
        MEM_DATA_OUT => mem_data_out,
        MEM_WRITE => mem_write
	);

	comm_ctrl: entity work.COMM_CTRL
	port map (
        CLK => CLK,
        RESET_N => RESET_N,
        READ_ADDR  => read_addr,
        READ_COUNT => read_count,
        READ_TIME  => read_time,
        READ_READY => read_ready,
        READ_LOST  => read_lost,
        READ_NEXT  => read_next,
        ST_SINK_DATA   => st_sink_data,
        ST_SINK_VALID  => st_sink_valid,
        ST_SINK_READY  => st_sink_ready,
        ST_SOURCE_DATA  => st_source_data,
        ST_SOURCE_VALID => st_source_valid,
        ST_SOURCE_READY => st_source_ready
	); 

    memory: entity work.MEMORY
    port map(
        clock => CLK,
        data => mem_data_out,
        rdaddress => mem_addr_in,
        wraddress => mem_addr_out,
        wren => mem_write,
        q => mem_data_in
    );
    
	LED_READY <= not read_ready;
	LED_OVERFLOW <= not read_lost;
	LED_MCU_ACT <= MCU_SPI_SS_N;
	LED_COMM_ACT <= COMM_SPI_SS_N;
	GPIO_READY <= read_ready;
    
    DBG_SPI_SS_N <= COMM_SPI_SS_N;
    DBG_SPI_CLK <= COMM_SPI_CLK;
    DBG_SPI_MISO <= COMM_SPI_MISO;

    FLASH_SPI_SS_N <= MCU_SPI_SS_N;
    FLASH_SPI_CLK <= MCU_SPI_CLK;
    FLASH_SPI_MOSI <= MCU_SPI_MOSI;

    process(FLASH_SPI_MISO, mosi_inject, mosi_inj_data)
    begin
        if mosi_inject = '1' then
            MCU_SPI_MOSI <= mosi_inj_data
        else
            MCU_SPI_MOSI <= FLASH_SPI_MISO;
        end if;
    end process;

    MCU_SPI_MISO <= FLASH_SPI_MISO;
end architecture RTL;
