library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TOP is
    port (
        RESET_N        : in std_logic;
        CLK            : in std_logic;

        MCU_SPI_SS_N   : in std_logic;
        MCU_SPI_CLK    : in std_logic;
        MCU_SPI_MOSI   : in std_logic;
        MCU_SPI_MISO   : out std_logic;

        SPI1_SS_N      : in std_logic;
        SPI1_CLK       : in std_logic;
        SPI1_MOSI      : in std_logic;
        SPI1_MISO      : out std_logic;

        FLASH_SPI_SS_N : out std_logic;
        FLASH_SPI_CLK  : out std_logic;
        FLASH_SPI_MOSI : out std_logic;
        FLASH_SPI_MISO : in std_logic;

        COMM_SPI_SS_N  : in std_logic;
        COMM_SPI_CLK   : in std_logic;
        COMM_SPI_MOSI  : in std_logic;
        COMM_SPI_MISO  : inout std_logic;

        SELECT_FLASH   : in std_logic;

        LED_READY      : out std_logic;
        LED_OVERFLOW   : out std_logic;
        LED_MCU_ACT    : out std_logic;
        LED_COMM_ACT   : out std_logic;
        
        GPIO_READY     : out std_logic;
        
        DBG_SPI_SS_N   : out std_logic;
        DBG_SPI_CLK    : out std_logic;
        DBG_SPI_MISO   : out std_logic 
    );
end entity;

architecture RTL of TOP is
    signal clk2 : std_logic;

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
    signal miso_inject    : std_logic;
    signal miso_inj_data  : std_logic;

    -- BUFCTRL read-side data
    signal read_addr      : std_logic_vector(23 downto 0);
    signal read_count     : std_logic_vector(23 downto 0);
    signal read_time      : std_logic_vector(15 downto 0);
    signal read_clear     : std_logic;

    -- Avalon-ST between comm_spi and spi_resp
    signal st_sink_data   : std_logic_vector(7 downto 0);
    signal st_sink_valid  : std_logic;
    signal st_sink_ready  : std_logic;
    signal st_source_data : std_logic_vector(7 downto 0);
    signal st_source_valid: std_logic;
    signal st_source_ready: std_logic;
    
    signal prog_en        : std_logic;
    signal prog_data      : std_logic_vector(7 downto 0);
    signal prog_strobe    : std_logic;
    signal prog_dump      : std_logic;

    signal vflash_addr    : std_logic_vector(15 downto 0);
    signal vflash_rden    : std_logic;
    signal vflash_wren    : std_logic;
    signal vflash_data_in : std_logic_vector(7 downto 0);
    signal vflash_data_out: std_logic_vector(7 downto 0);

    signal match_data     : std_logic_vector(7 downto 0);
    signal match_valid    : std_logic;
    
    signal inj_armed      : std_logic;

    signal flash_master_ss_n : std_logic;
    signal flash_master_clk  : std_logic;
    signal flash_master_mosi : std_logic;
    signal flash_master_miso : std_logic;
    signal flash_miso_retimed : std_logic;

    signal select_flash_FF1, select_flash_FF2, select_flash_Q : std_logic := '0';
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

    vflash: entity work.VFLASH
    port map (
        address => vflash_addr(13 downto 0),
        clock => CLK,
        data => vflash_data_out,
        rden => vflash_rden,
        wren => vflash_wren,
        q => vflash_data_in
    );

    
    injector: entity work.INJECTOR
    generic map (
        NUM_ENTRIES => 8
    )
    port map (
        RESET_N => RESET_N,
        CLK => CLK,
        
        PROG_EN => prog_en,
        PROG_DATA => prog_data,
        PROG_STROBE => prog_strobe,
        PROG_DUMP => prog_dump,

        MEM_ADDR => vflash_addr,
        MEM_RDEN => vflash_rden,
        MEM_WREN => vflash_wren,
        MEM_DATA_OUT => vflash_data_out,
        MEM_DATA_IN => vflash_data_in,
        
        MATCH_ADDR => spy_addr_out,
        MATCH_OFFSET => spy_byte_count,
        MATCH_DATA => match_data,
        MATCH_VALID => match_valid,

        ARMED => inj_armed
    );
    
    spispy: entity work.SPISPY
    port map (
        RESET_N => RESET_N,
        CLK => CLK,
        SPI_CS_N => flash_master_ss_n,
        SPI_CLK => flash_master_clk,
        SPI_MOSI => flash_master_mosi,       
        SPI_MISO => miso_inj_data,
        ADDR_OUT => spy_addr_out,
        BYTE_COUNT => spy_byte_count,
        STROBE => spy_strobe,
        MOSI_EN => miso_inject,
        MATCH_DATA => match_data,
        MATCH_VALID => match_valid
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
        READ_CLEAR => read_clear,
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
        READ_CLEAR => read_clear,
        ST_SINK_DATA   => st_sink_data,
        ST_SINK_VALID  => st_sink_valid,
        ST_SINK_READY  => st_sink_ready,
        ST_SOURCE_DATA  => st_source_data,
        ST_SOURCE_VALID => st_source_valid,
        ST_SOURCE_READY => st_source_ready,
        SPI_SS_N => COMM_SPI_SS_N,
        PROG_EN => prog_en,
        PROG_DATA => prog_data,
        PROG_STROBE => prog_strobe,
        PROG_DUMP => prog_dump,
        DUMP_DATA => match_data
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

    retimer: entity work.SPI_RETIMER_DELAY
    port map (
        FAST_CLK => CLK2,
        RST_N => RESET_N,
        SCK_UP => flash_master_clk,
        CSN_UP => flash_master_ss_n,
        MOSI_UP => flash_master_mosi,
        MISO_UP => flash_miso_retimed,

        SCK_DN => FLASH_SPI_CLK,
        CSN_DN => FLASH_SPI_SS_N,
        MOSI_DN => FLASH_SPI_MOSI,
        MISO_DN => flash_master_miso
    );
    
    clock2: entity work.PLLCLOCK
    port map(
        areset => '0',
        inclk0 => CLK,
        c0 => CLK2
    );
    
    LED_READY <= read_ready;
    LED_OVERFLOW <= not read_lost;
    LED_MCU_ACT <= MCU_SPI_SS_N;
    LED_COMM_ACT <= COMM_SPI_SS_N;
    GPIO_READY <= read_ready;
    
    DBG_SPI_SS_N <= COMM_SPI_SS_N;
    DBG_SPI_CLK <= COMM_SPI_CLK;
    DBG_SPI_MISO <= COMM_SPI_MISO;

    process(all)
    begin
        if select_flash_Q = '0' then
            flash_master_ss_n <= MCU_SPI_SS_N;
            flash_master_clk <= MCU_SPI_CLK;
            flash_master_mosi <= MCU_SPI_MOSI;
            MCU_SPI_MISO <= flash_miso_retimed;
            SPI1_MISO <= '0';
        else
            flash_master_ss_n <= SPI1_SS_N;
            flash_master_clk <= SPI1_CLK;
            flash_master_mosi <= SPI1_MOSI;
            SPI1_MISO <= flash_miso_retimed;
            MCU_SPI_MISO <= '0';
        end if;
    end process;

    process(all)
        if miso_inject = '1' then
            flash_master_miso <= miso_inj_data;
        else
            flash_master_miso <= FLASH_SPI_MISO;
        end if;
    end process;

    process(CLK)
    begin
        if rising_edge(CLK) then
            select_flash_FF1 <= SELECT_FLASH;
            select_flash_FF2 <= select_flash_FF1;
            select_flash_Q <= select_flash_FF2;
        end if;
    end process;
end architecture RTL;
