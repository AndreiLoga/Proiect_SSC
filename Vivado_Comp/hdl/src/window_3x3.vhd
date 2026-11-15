----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/15/2026 04:53:03 PM
-- Design Name: 
-- Module Name: window_3x3 - Behavioral
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

entity window_3x3 is
    generic (
        IMG_W : integer := 8;
        IMG_H : integer := 8
    );
    port (
        clk: in  std_logic;
        rst_n: in  std_logic;

        valid_in: in  std_logic;
        row_top: in  std_logic_vector(7 downto 0);
        row_mid: in  std_logic_vector(7 downto 0);
        row_bot: in  std_logic_vector(7 downto 0);

        w00, w01, w02: out std_logic_vector(7 downto 0); --primul nr e randul, al doilea coloana 
        w10, w11, w12: out std_logic_vector(7 downto 0);
        w20, w21, w22: out std_logic_vector(7 downto 0);
        valid_out: out std_logic
    );
end entity window_3x3;

architecture Behavioral of window_3x3 is

type REG is array(0 to 2) of std_logic_vector(7 downto 0);
signal REG_R: REG:= (others => (others => '0')); --dreapta
signal REG_C: REG:= (others => (others => '0')); --centru
signal REG_L: REG:= (others => (others => '0')); --stanga

signal fill : integer range 0 to IMG_W + 1;

signal ccol : integer range 0 to IMG_W - 1;
signal crow : integer range 0 to IMG_H - 1;
signal m_left: std_logic := '0';
signal m_right: std_logic := '0'; 
signal m_top: std_logic := '0';
signal m_bot: std_logic := '0'; 
   
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then 
                REG_L <= (others => (others => '0'));
                REG_C <= (others => (others => '0'));
                REG_R <= (others => (others => '0'));
                fill <= 0;
                valid_out <= '0';
                ccol <=0;
                crow<=0;
                m_left <='0';
                m_right <='0';
                m_top <='0';
                m_bot <='0';
            else 
                valid_out <= '0';
                if valid_in ='1' then
                    if fill < IMG_W + 1 then
                        fill <= fill + 1;
                    else
                        valid_out <= '1';
                        -- steagurile ferestrei curente (din ccol/crow, inainte de avansare)
                        if ccol = 0 then
                            m_left <= '1';
                        else
                            m_left <= '0';
                        end if;

                        if ccol = IMG_W - 1 then
                            m_right <= '1';
                        else
                            m_right <= '0';
                        end if;

                        if crow = 0 then
                            m_top <= '1';
                        else
                            m_top <= '0';
                        end if;

                        if crow = IMG_H - 1 then
                            m_bot <= '1';
                        else
                            m_bot <= '0';
                        end if;

                        -- avansarea pozitiei ferestrei urmatoare
                        if ccol = IMG_W - 1 then
                            ccol <= 0;
                            if crow = IMG_H - 1 then
                                crow <= 0;
                                fill <= 0;        -- ultima fereastra: imaginea urmatoare reincepe
                            else
                                crow <= crow + 1;
                            end if;
                        else
                            ccol <= ccol + 1;
                        end if;
                    end if;
                    
                    REG_L <= REG_C;
                    REG_C <= REG_R;
                    REG_R(0) <= row_top;
                    REG_R(1) <= row_mid;
                    REG_R(2) <= row_bot;
                end if;
            end if;
        end if;
    end process;
    
    -- randul 0 (sus)
    w00 <= (others => '0') when (m_top = '1' or m_left  = '1') else REG_L(0);
    w01 <= (others => '0') when (m_top = '1') else REG_C(0);
    w02 <= (others => '0') when (m_top = '1' or m_right = '1') else REG_R(0);

    -- randul 1 (mijloc)
    w10 <= (others => '0') when (m_left  = '1') else REG_L(1);
    w11 <= REG_C(1);
    w12 <= (others => '0') when (m_right = '1') else REG_R(1);

    -- randul 2 (jos)
    w20 <= (others => '0') when (m_bot = '1' or m_left  = '1') else REG_L(2);
    w21 <= (others => '0') when (m_bot = '1') else REG_C(2);
    w22 <= (others => '0') when (m_bot = '1' or m_right = '1') else REG_R(2);
    
end Behavioral;
