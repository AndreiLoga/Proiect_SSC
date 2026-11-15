----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/15/2026 02:48:36 PM
-- Design Name: 
-- Module Name: line_buffer - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity line_buffer is
    generic (
        IMG_W: integer := 8);  -- latimea imaginii in pixeli 
    port (
        clk: in  std_logic;
        rst_n: in  std_logic;  -- reset sincron, activ pe 0

        valid_in: in  std_logic; -- pixel_in este valid
        pixel_in: in  std_logic_vector(7 downto 0);

        row_top: out std_logic_vector(7 downto 0);  -- randul r-2
        row_mid: out std_logic_vector(7 downto 0);  -- randul r-1
        row_bot: out std_logic_vector(7 downto 0);  -- randul r (curent)
        valid_out: out std_logic);
end line_buffer;

architecture Behavioral of line_buffer is

type MEM is array(0 to IMG_W-1) of std_logic_vector(7 downto 0); 
signal MEM_TOP : MEM := (others => (others => '0'));
signal MEM_MID: MEM := (others => (others => '0'));
signal col : integer range 0 to IMG_W - 1; 

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                col <= 0;
            elsif valid_in = '1' then
                if col = IMG_W - 1 then
                    col <= 0;
                else
                    col <= col + 1;
                end if; 
            end if;
        end if;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then 
                valid_out <= '0';
                row_top <= (others => '0');
                row_mid <= (others => '0');
                row_bot <= (others => '0');
            else 
                valid_out <= valid_in;
                if valid_in = '1' then
                    row_top <= MEM_TOP(col);
                    row_mid <= MEM_MID(col);
                    row_bot <= pixel_in;
                    
                    MEM_TOP(col) <= MEM_MID(col);
                    MEM_MID(col) <= pixel_in;            
                end if;
            end if;
        end if;
    end process;

end Behavioral;
