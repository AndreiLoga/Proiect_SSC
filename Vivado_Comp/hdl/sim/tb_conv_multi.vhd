-- Testbench end-to-end: line_buffer -> window_3x3 -> conv_mac (Gaussian 3x3).
-- Compara fiecare pixel de iesire cu out_*.hex generat de codul C.
-- tb_conv_case  = un caz (dimensiune + fisiere hex), isi opreste singur ceasul.
-- tb_conv_multi = top; instantiaza toate cazurile. "run all" se opreste singur.
-- Set tb_conv_multi ca Simulation Top.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

------------------------------------------------------------------------
entity tb_conv_case is
    generic (
        NAME     : string;
        IMG_W    : integer;
        IMG_H    : integer;
        IN_FILE  : string;
        OUT_FILE : string
    );
end entity tb_conv_case;

architecture sim of tb_conv_case is

    constant N_PIX : integer := IMG_W * IMG_H;

    type img_t is array (0 to N_PIX - 1) of std_logic_vector(7 downto 0);

    impure function load_hex(fname : string) return img_t is
        file     f : text open read_mode is fname;
        variable l : line;
        variable v : std_logic_vector(7 downto 0);
        variable r : img_t := (others => (others => '0'));
        variable i : integer := 0;
    begin
        while (not endfile(f)) and (i < N_PIX) loop
            readline(f, l);
            hread(l, v);
            r(i) := v;
            i := i + 1;
        end loop;
        assert i = N_PIX
            report NAME & ": " & fname & " are " & integer'image(i) & " pixeli"
            severity failure;
        return r;
    end function;

    constant img_in  : img_t := load_hex(IN_FILE);
    constant img_ref : img_t := load_hex(OUT_FILE);

    -- Gaussian 3x3: 1 2 1 / 2 4 2 / 1 2 1
    constant K1 : signed(7 downto 0) := to_signed(1, 8);
    constant K2 : signed(7 downto 0) := to_signed(2, 8);
    constant K4 : signed(7 downto 0) := to_signed(4, 8);

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal valid_in  : std_logic := '0';
    signal pixel_in  : std_logic_vector(7 downto 0) := (others => '0');

    signal lb_top, lb_mid, lb_bot : std_logic_vector(7 downto 0);
    signal lb_valid               : std_logic;

    signal w00, w01, w02 : std_logic_vector(7 downto 0);
    signal w10, w11, w12 : std_logic_vector(7 downto 0);
    signal w20, w21, w22 : std_logic_vector(7 downto 0);
    signal win_valid     : std_logic;

    signal pixel_out : std_logic_vector(7 downto 0);
    signal out_valid : std_logic;

    signal errors  : integer := 0;
    signal checked : integer := 0;
    signal done    : boolean := false;

begin

    clkgen : process
    begin
        while not done loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process clkgen;

    u_lb : entity work.line_buffer
        generic map (IMG_W => IMG_W)
        port map (
            clk => clk, rst_n => rst_n,
            valid_in => valid_in, pixel_in => pixel_in,
            row_top => lb_top, row_mid => lb_mid, row_bot => lb_bot,
            valid_out => lb_valid
        );

    u_win : entity work.window_3x3
        generic map (IMG_W => IMG_W, IMG_H => IMG_H)
        port map (
            clk => clk, rst_n => rst_n,
            valid_in => lb_valid,
            row_top => lb_top, row_mid => lb_mid, row_bot => lb_bot,
            w00 => w00, w01 => w01, w02 => w02,
            w10 => w10, w11 => w11, w12 => w12,
            w20 => w20, w21 => w21, w22 => w22,
            valid_out => win_valid
        );

    u_mac : entity work.conv_mac
        generic map (SHIFT => 4)
        port map (
            clk => clk, rst_n => rst_n,
            valid_in => win_valid,
            w00 => w00, w01 => w01, w02 => w02,
            w10 => w10, w11 => w11, w12 => w12,
            w20 => w20, w21 => w21, w22 => w22,
            k00 => K1, k01 => K2, k02 => K1,
            k10 => K2, k11 => K4, k12 => K2,
            k20 => K1, k21 => K2, k22 => K1,
            pixel_out => pixel_out,
            valid_out => out_valid
        );

    ------------------------------------------------------------------
    -- Stimul: reset, pixelii cu pauze, apoi IMG_W + 1 pixeli dummy
    ------------------------------------------------------------------
    stim : process
    begin
        rst_n <= '0';
        wait for 30 ns;
        wait until falling_edge(clk);
        rst_n <= '1';
        wait until falling_edge(clk);

        for k in 0 to N_PIX - 1 loop
            valid_in <= '1';
            pixel_in <= img_in(k);
            wait until falling_edge(clk);
            if (k mod 7 = 6) or (k = 30) then
                valid_in <= '0';
                pixel_in <= x"FF";
                wait until falling_edge(clk);
                wait until falling_edge(clk);
            end if;
        end loop;

        for k in 0 to IMG_W loop           -- flush
            valid_in <= '1';
            pixel_in <= x"AA";
            wait until falling_edge(clk);
        end loop;

        valid_in <= '0';
        wait for 200 ns;
        done <= true;
        wait;
    end process stim;

    ------------------------------------------------------------------
    -- Verificare: fiecare pixel de iesire fata de out_*.hex din C
    ------------------------------------------------------------------
    check : process(clk)
        variable k    : integer := 0;
        variable nerr : integer := 0;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                k := 0;
            elsif out_valid = '1' then
                if k >= N_PIX then
                    nerr := nerr + 1;
                    if nerr <= 10 then
                        report NAME & ": valid_out in plus, pixel " & integer'image(k)
                            severity error;
                    end if;
                elsif pixel_out /= img_ref(k) then
                    nerr := nerr + 1;
                    if nerr <= 10 then
                        report NAME & ": pixel " & integer'image(k) &
                            " (r=" & integer'image(k / IMG_W) &
                            ", c=" & integer'image(k mod IMG_W) & "): astept " &
                            integer'image(to_integer(unsigned(img_ref(k)))) & ", am " &
                            integer'image(to_integer(unsigned(pixel_out)))
                            severity error;
                    end if;
                end if;
                k := k + 1;
                checked <= k;
            end if;
            errors <= nerr;
        end if;
    end process check;

    ------------------------------------------------------------------
    finish : process
    begin
        wait until done;
        if checked /= N_PIX then
            report "FAIL [" & NAME & "]: " & integer'image(checked) &
                   " pixeli iesiti din " & integer'image(N_PIX) severity error;
        elsif errors = 0 then
            report "PASS [" & NAME & "]: " & integer'image(N_PIX) &
                   " pixeli identici cu referinta din C" severity note;
        else
            report "FAIL [" & NAME & "]: " & integer'image(errors) & " erori" severity error;
        end if;
        wait;
    end process finish;

end architecture sim;

------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_conv_multi is
end entity tb_conv_multi;

architecture sim of tb_conv_multi is
    constant REF : string := "D:/000-UTCN/0-FACULTA_ANDREI/ANUL-3/SEM_1/SSC_P/Cod_C/ref/";
begin
    c1 : entity work.tb_conv_case generic map ("8x8 grad",     8,   8,   REF & "in_8x8_grad.hex",     REF & "out_8x8_grad.hex");
    c2 : entity work.tb_conv_case generic map ("8x8 rand",     8,   8,   REF & "in_8x8_rand.hex",     REF & "out_8x8_rand.hex");
    c3 : entity work.tb_conv_case generic map ("16x16 grad",   16,  16,  REF & "in_16x16_grad.hex",   REF & "out_16x16_grad.hex");
    c4 : entity work.tb_conv_case generic map ("16x16 rand",   16,  16,  REF & "in_16x16_rand.hex",   REF & "out_16x16_rand.hex");
    c5 : entity work.tb_conv_case generic map ("128x128 rand", 128, 128, REF & "in_128x128_rand.hex", REF & "out_128x128_rand.hex");
    c6 : entity work.tb_conv_case generic map ("256x256 rand", 256, 256, REF & "in_256x256_rand.hex", REF & "out_256x256_rand.hex");
    c7 : entity work.tb_conv_case generic map ("512x512 rand", 512, 512, REF & "in_512x512_rand.hex", REF & "out_512x512_rand.hex");
end architecture sim;
