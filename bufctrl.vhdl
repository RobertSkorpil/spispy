library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity BUFCTRL is
    port 
    (
        RESET_N        : in std_logic;
        CLK            : in std_logic;

        CAP_ADDR       : in std_logic_vector(23 downto 0);
        CAP_COUNT      : in std_logic_vector(23 downto 0);
        CAP_STROBE     : in std_logic;
        CAP_TIME       : in std_logic_vector(15 downto 0);

        READ_ADDR      : out std_logic_vector(23 downto 0);
        READ_COUNT     : out std_logic_vector(23 downto 0);
        READ_TIME      : out std_logic_vector(15 downto 0);
        READ_READY     : out std_logic;
        READ_LOST      : out std_logic;
        READ_NEXT      : in std_logic;        
        READ_CLEAR      : in std_logic;

        MEM_ADDR_IN    : out std_logic_vector(8 downto 0);
        MEM_DATA_IN    : in std_logic_vector(63 downto 0);
        MEM_ADDR_OUT   : out std_logic_vector(8 downto 0);
        MEM_DATA_OUT   : out std_logic_vector(63 downto 0);
        MEM_WRITE      : out std_logic
    );
end entity BUFCTRL;

architecture RTL of BUFCTRL is
    signal read_ptr : unsigned(8 downto 0) := (others => '0');
    signal next_read_ptr: unsigned(8 downto 0) := (others => '0');
    signal write_ptr : unsigned(8 downto 0) := (others => '0');
    signal next_write_ptr: unsigned(8 downto 0) := (others => '0');
    signal overflow : std_logic := '0';
    signal set_overflow : std_logic := '0';
    signal clear_overflow : std_logic := '0';
begin
    CAP_COMB: process(CAP_ADDR, CAP_COUNT, CAP_STROBE, CAP_TIME, write_ptr, read_ptr)
    variable new_write_ptr : unsigned(8 downto 0);
    begin
        new_write_ptr := write_ptr + 1;
        MEM_ADDR_OUT <= std_logic_vector(write_ptr);
        MEM_DATA_OUT <= CAP_ADDR & CAP_COUNT & CAP_TIME;
        set_overflow <= '0';
        next_write_ptr <= write_ptr;
        MEM_WRITE <= '0';
        if CAP_STROBE = '1' then
            if new_write_ptr = read_ptr then
                set_overflow <= '1';
            else
                next_write_ptr <= new_write_ptr;
                MEM_WRITE <= '1';
            end if;
        end if;
    end process;

    READ_IN_COMB: process(READ_NEXT, read_ptr, write_ptr)
    variable new_read_ptr : unsigned(8 downto 0);
    begin
        new_read_ptr := read_ptr + 1;
        next_read_ptr <= read_ptr;
        if READ_CLEAR = '1' then
            next_read_ptr <= write_ptr;
            clear_overflow <= '1';
        elsif READ_NEXT = '1' and read_ptr /= write_ptr then
            clear_overflow <= '1';
            next_read_ptr <= new_read_ptr;
        else
            clear_overflow <= '0';
        end if;
    end process;

    READ_OUT_COMB: process(MEM_DATA_IN, overflow, read_ptr, write_ptr)
    begin
        MEM_ADDR_IN <= std_logic_vector(read_ptr);

        READ_ADDR <= MEM_DATA_IN(63 downto 40);
        READ_COUNT <= MEM_DATA_IN(39 downto 16);
        READ_TIME <= MEM_DATA_IN(15 downto 0);
        READ_LOST <= overflow;
        if read_ptr = write_ptr then
            READ_READY <= '0';
        else
            READ_READY <= '1';
        end if;
    end process;

    SYNC: process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                read_ptr <= (others => '0');
                write_ptr <= (others => '0');
                overflow <= '0';
            else
                read_ptr <= next_read_ptr;
                write_ptr <= next_write_ptr;
                if clear_overflow = '1' then
                    overflow <= '0';
                elsif set_overflow = '1' then
                    overflow <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture RTL;
