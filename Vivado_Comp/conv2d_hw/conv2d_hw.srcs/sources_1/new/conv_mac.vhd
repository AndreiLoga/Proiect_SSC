----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/15/2026 06:05:13 PM
-- Design Name: 
-- Module Name: conv_mac - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity conv_mac is
    generic (
        SHIFT : integer := 4          -- normalizare: impartire la 2**SHIFT
    );
    port (
        clk: in  std_logic;
        rst_n: in  std_logic;

        valid_in: in  std_logic;
        w00, w01, w02: in std_logic_vector(7 downto 0);   -- fereastra, pixeli fara semn
        w10, w11, w12: in std_logic_vector(7 downto 0);
        w20, w21, w22: in std_logic_vector(7 downto 0);

        k00, k01, k02: in signed(7 downto 0);              -- coeficienti cu semn
        k10, k11, k12: in signed(7 downto 0);
        k20, k21, k22: in signed(7 downto 0);

        pixel_out: out std_logic_vector(7 downto 0);
        valid_out: out std_logic
    );
end entity conv_mac;

architecture Behavioral of conv_mac is

type prod_arr is array (0 to 8) of signed(16 downto 0);
signal prod : prod_arr:= (others => (others => '0'));

type rsum_arr is array (0 to 2) of signed(18 downto 0);
signal rsum : rsum_arr := (others => (others => '0'));   -- E2: 3 sume de rand

signal total : signed(19 downto 0) := (others => '0');    -- E3: suma totala

signal v1, v2, v3 : std_logic := '0';

begin

    process(clk)
        variable sh : signed(19 downto 0);
    begin
        if rising_edge(clk) then
            -- E1: cele 9 produse
            prod(0) <= signed('0' & w00) * k00;
            prod(1) <= signed('0' & w01) * k01;
            prod(2) <= signed('0' & w02) * k02;
            prod(3) <= signed('0' & w10) * k10;
            prod(4) <= signed('0' & w11) * k11;
            prod(5) <= signed('0' & w12) * k12;
            prod(6) <= signed('0' & w20) * k20;
            prod(7) <= signed('0' & w21) * k21;
            prod(8) <= signed('0' & w22) * k22;

            -- E2: suma pe fiecare rand (3 produse), extinse la 19 biti inainte de adunare
            rsum(0) <= resize(prod(0), 19) + resize(prod(1), 19) + resize(prod(2), 19);
            rsum(1) <= resize(prod(3), 19) + resize(prod(4), 19) + resize(prod(5), 19);
            rsum(2) <= resize(prod(6), 19) + resize(prod(7), 19) + resize(prod(8), 19);

            -- E3: suma totala, extinsa la 20 de biti
            total <= resize(rsum(0), 20) + resize(rsum(1), 20) + resize(rsum(2), 20);
            
            -- E4: shift aritmetic (>> SHIFT), apoi saturare la 0..255
            sh := shift_right(total, SHIFT);
            if sh < 0 then
                pixel_out <= (others => '0');
            elsif sh > 255 then
                pixel_out <= (others => '1');
            else
                pixel_out <= std_logic_vector(sh(7 downto 0));
            end if;
            
            -- valid insoteste datele, un registru pe etaj
            if rst_n = '0' then
                v1 <= '0';
                v2 <= '0';
                v3 <= '0';
                valid_out <= '0';
            else
                v1 <= valid_in;
                v2 <= v1;
                v3 <= v2;
                valid_out <= v3;
            end if;
        end if;
    end process;

end Behavioral;
