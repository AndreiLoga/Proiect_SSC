-- Testbench auto-verificabil pentru line_buffer.
-- Citeste ref/in_8x8_grad.hex, il trimite pixel cu pixel (cu pauze) si compara
-- row_top / row_mid / row_bot cu valorile asteptate. Raporteaza PASS / FAIL.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity tb_line_buffer is
end entity tb_line_buffer;

architecture sim of tb_line_buffer is

    constant IMG_W    : integer := 8;
    constant IMG_H    : integer := 8;
    constant N_PIX    : integer := IMG_W * IMG_H;
    constant CLK_PER  : time    := 10 ns;
    -- Calea catre fisierul hex (cu /, chiar pe Windows)
    constant HEX_FILE : string  :=
        "D:/000-UTCN/0-FACULTA_ANDREI/ANUL-3/SEM_1/SSC_P/Cod_C/ref/in_8x8_grad.hex";

    type img_t is array (0 to N_PIX - 1) of std_logic_vector(7 downto 0);
    signal img : img_t := (others => (others => '0'));

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal valid_in  : std_logic := '0';
    signal pixel_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal row_top   : std_logic_vector(7 downto 0);
    signal row_mid   : std_logic_vector(7 downto 0);
    signal row_bot   : std_logic_vector(7 downto 0);
    signal valid_out : std_logic;

    signal errors    : integer := 0;
    signal checked   : integer := 0;
    signal done      : boolean := false;
    signal loaded    : boolean := false;

begin

    clk <= not clk after CLK_PER / 2;

    dut : entity work.line_buffer
        generic map (IMG_W => IMG_W)
        port map (
            clk       => clk,
            rst_n     => rst_n,
            valid_in  => valid_in,
            pixel_in  => pixel_in,
            row_top   => row_top,
            row_mid   => row_mid,
            row_bot   => row_bot,
            valid_out => valid_out
        );

    ------------------------------------------------------------------
    -- Stimul: incarca hex-ul, reset, apoi trimite pixelii cu pauze
    ------------------------------------------------------------------
    stim : process
        file     f    : text;
        variable l    : line;
        variable v    : std_logic_vector(7 downto 0);
        variable st   : file_open_status;
        variable i    : integer := 0;
    begin
        file_open(st, f, HEX_FILE, read_mode);
        assert st = open_ok
            report "Nu pot deschide " & HEX_FILE severity failure;
        while (not endfile(f)) and (i < N_PIX) loop
            readline(f, l);
            hread(l, v);
            img(i) <= v;
            i := i + 1;
        end loop;
        file_close(f);
        assert i = N_PIX
            report "Fisier hex cu numar gresit de pixeli: " & integer'image(i)
            severity failure;
        wait for 1 ns;   -- lasa semnalul img sa se actualizeze

        -- reset
        rst_n <= '0';
        wait for 3 * CLK_PER;
        wait until falling_edge(clk);
        rst_n <= '1';
        wait until falling_edge(clk);

        -- trimite pixelii; la fiecare 5 pixeli sau mai mult facem o pauza
        for k in 0 to N_PIX - 1 loop
            valid_in <= '1';
            pixel_in <= img(k);
            wait until falling_edge(clk);
            if (k mod 5 = 4) or (k = 20) then
                valid_in <= '0';
                pixel_in <= x"FF";            -- date de umplutura, trebuie ignorate
                wait until falling_edge(clk);
                wait until falling_edge(clk);
            end if;
        end loop;

        valid_in <= '0';
        wait for 5 * CLK_PER;
        done <= true;
        wait;
    end process stim;

    ------------------------------------------------------------------
    -- Verificare: la fiecare front, daca valid_out = 1, compara tripletul
    ------------------------------------------------------------------
    check : process(clk)
        variable n   : integer := 0;      -- al catelea pixel valid
        variable exp : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                n := 0;
            elsif valid_out = '1' then
                -- row_bot = pixelul n
                exp := img(n);
                if row_bot /= exp then
                    errors <= errors + 1;
                    report "row_bot pixel " & integer'image(n) & ": astept " &
                        integer'image(to_integer(unsigned(exp))) & ", am " &
                        integer'image(to_integer(unsigned(row_bot)))
                        severity error;
                end if;
                -- row_mid = pixelul n - IMG_W (sau 0 pe primul rand)
                if n >= IMG_W then exp := img(n - IMG_W); else exp := x"00"; end if;
                if row_mid /= exp then
                    errors <= errors + 1;
                    report "row_mid pixel " & integer'image(n) & ": astept " &
                        integer'image(to_integer(unsigned(exp))) & ", am " &
                        integer'image(to_integer(unsigned(row_mid)))
                        severity error;
                end if;
                -- row_top = pixelul n - 2*IMG_W (sau 0 pe primele doua randuri)
                if n >= 2 * IMG_W then exp := img(n - 2 * IMG_W); else exp := x"00"; end if;
                if row_top /= exp then
                    errors <= errors + 1;
                    report "row_top pixel " & integer'image(n) & ": astept " &
                        integer'image(to_integer(unsigned(exp))) & ", am " &
                        integer'image(to_integer(unsigned(row_top)))
                        severity error;
                end if;
                n := n + 1;
                checked <= n;
            end if;
        end if;
    end process check;

    ------------------------------------------------------------------
    -- Rezultat final
    ------------------------------------------------------------------
    finish : process
    begin
        wait until done;
        if checked /= N_PIX then
            report "FAIL: verificate " & integer'image(checked) &
                   " pixeli din " & integer'image(N_PIX) severity error;
        elsif errors = 0 then
            report "PASS: toti cei " & integer'image(N_PIX) & " pixeli corecti" severity note;
        else
            report "FAIL: " & integer'image(errors) & " erori" severity error;
        end if;
        wait;
    end process finish;

end architecture sim;
