-- Testbench pentru top_conv2d (interfata AXI-Stream).
-- Trimite DOUA imagini la rand (A apoi B), cu pauze aleatoare in tvalid.
-- Daca BP = 1, m_axis_tready e aleator (backpressure), altfel mereu 1.
-- Compara fiecare pixel de iesire cu out_*.hex din C si verifica tlast.
-- tb_top_case = un caz, isi opreste singur ceasul.
-- tb_top_conv2d = top de simulare; instantiaza toate cazurile ("run all").
-- Set tb_top_conv2d ca Simulation Top.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

------------------------------------------------------------------------
entity tb_top_case is
    generic (
        NAME: string;
        IMG_W: integer;
        IMG_H: integer;
        IN_A: string;
        OUT_A: string;
        IN_B: string;
        OUT_B: string;
        BP: integer
    );
end entity tb_top_case;

architecture sim of tb_top_case is

    constant N_PIX: integer := IMG_W * IMG_H;
    constant N_TOT: integer := 2 * N_PIX;

    type img_t is array (0 to N_PIX - 1) of std_logic_vector(7 downto 0);

    impure function load_hex(fname: string) return img_t is
        file f: text open read_mode is fname;
        variable l: line;
        variable v: std_logic_vector(7 downto 0);
        variable r: img_t := (others => (others => '0'));
        variable i: integer := 0;
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

    constant data_a: img_t := load_hex(IN_A);
    constant ref_a: img_t := load_hex(OUT_A);
    constant data_b: img_t := load_hex(IN_B);
    constant ref_b: img_t := load_hex(OUT_B);

    signal clk: std_logic := '0';
    signal rst_n: std_logic := '0';

    signal s_axis_tdata: std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_tvalid: std_logic := '0';
    signal s_axis_tlast: std_logic := '0';
    signal s_axis_tready: std_logic;

    signal m_axis_tdata: std_logic_vector(7 downto 0);
    signal m_axis_tvalid: std_logic;
    signal m_axis_tlast: std_logic;
    signal m_axis_tready: std_logic := '1';

    signal errors: integer := 0;
    signal checked: integer := 0;
    signal tlast_cnt: integer := 0;
    signal done: boolean := false;
    signal timed_out: boolean := false;

begin

    clkgen: process
    begin
        while not (done or timed_out) loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process clkgen;

    u_dut: entity work.top_conv2d
        generic map (IMG_W => IMG_W, IMG_H => IMG_H)
        port map (
            clk => clk,
            rst_n => rst_n,
            s_axis_tdata => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tlast => s_axis_tlast,
            s_axis_tready => s_axis_tready,
            m_axis_tdata => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tlast => m_axis_tlast,
            m_axis_tready => m_axis_tready
        );

    ------------------------------------------------------------------
    -- Stimul: imaginea A, apoi imediat imaginea B, cu pauze aleatoare.
    -- Handshake corect: tvalid ramane 1 pana cand tready = 1 la front.
    ------------------------------------------------------------------
    stim: process
        variable seed: integer := 12345;
    begin
        rst_n <= '0';
        wait for 30 ns;
        wait until falling_edge(clk);
        rst_n <= '1';
        wait until falling_edge(clk);

        for img in 0 to 1 loop
            for k in 0 to N_PIX - 1 loop
                -- pauza aleatoare (aprox. 1 pixel din 3), de 1..3 cicluri
                seed := (seed * 75 + 74) mod 65537;
                if seed mod 3 = 0 then
                    s_axis_tvalid <= '0';
                    s_axis_tlast <= '0';
                    for g in 0 to (seed / 3) mod 3 loop
                        wait until rising_edge(clk);
                    end loop;
                end if;

                if img = 0 then
                    s_axis_tdata <= data_a(k);
                else
                    s_axis_tdata <= data_b(k);
                end if;
                if k = N_PIX - 1 then
                    s_axis_tlast <= '1';
                else
                    s_axis_tlast <= '0';
                end if;
                s_axis_tvalid <= '1';

                -- tine pixelul pana la handshake
                loop
                    wait until rising_edge(clk);
                    exit when s_axis_tready = '1';
                end loop;
            end loop;
        end loop;

        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';

        -- lasa pipeline-ul sa se goleasca
        for c in 1 to 4 * IMG_W + 300 loop
            wait until rising_edge(clk);
        end loop;
        done <= true;
        wait;
    end process stim;

    ------------------------------------------------------------------
    -- Backpressure pe iesire: tready aleator (~50%) cand BP = 1
    ------------------------------------------------------------------
    bp_gen: process(clk)
        variable seed: integer := 777;
    begin
        if rising_edge(clk) then
            if BP = 1 then
                seed := (seed * 75 + 74) mod 65537;
                if (seed / 7) mod 2 = 0 then
                    m_axis_tready <= '1';
                else
                    m_axis_tready <= '0';
                end if;
            else
                m_axis_tready <= '1';
            end if;
        end if;
    end process bp_gen;

    ------------------------------------------------------------------
    -- Verificare: pixel (A apoi B) si tlast la fiecare beat de iesire
    ------------------------------------------------------------------
    check: process(clk)
        variable k: integer := 0;
        variable nerr: integer := 0;
        variable nlast: integer := 0;
        variable expected: std_logic_vector(7 downto 0);
        variable exp_last: std_logic;
        variable pos: integer;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                k := 0;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then
                if k >= N_TOT then
                    nerr := nerr + 1;
                    if nerr <= 10 then
                        report NAME & ": beat in plus la iesire, index " & integer'image(k)
                            severity error;
                    end if;
                else
                    if k < N_PIX then
                        expected := ref_a(k);
                        pos := k;
                    else
                        expected := ref_b(k - N_PIX);
                        pos := k - N_PIX;
                    end if;
                    if pos = N_PIX - 1 then
                        exp_last := '1';
                    else
                        exp_last := '0';
                    end if;

                    if m_axis_tdata /= expected then
                        nerr := nerr + 1;
                        if nerr <= 10 then
                            report NAME & ": imaginea " & integer'image(k / N_PIX) &
                                " pixel " & integer'image(pos) &
                                " (r=" & integer'image(pos / IMG_W) &
                                ", c=" & integer'image(pos mod IMG_W) & "): astept " &
                                integer'image(to_integer(unsigned(expected))) & ", am " &
                                integer'image(to_integer(unsigned(m_axis_tdata)))
                                severity error;
                        end if;
                    end if;
                    if m_axis_tlast /= exp_last then
                        nerr := nerr + 1;
                        if nerr <= 10 then
                            report NAME & ": tlast gresit la imaginea " & integer'image(k / N_PIX) &
                                " pixel " & integer'image(pos)
                                severity error;
                        end if;
                    end if;
                end if;
                if m_axis_tlast = '1' then
                    nlast := nlast + 1;
                end if;
                k := k + 1;
                checked <= k;
            end if;
            errors <= nerr;
            tlast_cnt <= nlast;
        end if;
    end process check;

    ------------------------------------------------------------------
    -- Watchdog: daca DUT-ul se blocheaza, nu ramane simularea agatata
    ------------------------------------------------------------------
    watchdog: process
    begin
        wait for (10 * N_TOT + 20 * IMG_W + 2000) * 10 ns;
        if not done then
            report "FAIL [" & NAME & "]: timeout, simularea s-a blocat" severity error;
            timed_out <= true;
        end if;
        wait;
    end process watchdog;

    ------------------------------------------------------------------
    finish: process
    begin
        wait until done;
        if checked /= N_TOT then
            report "FAIL [" & NAME & "]: " & integer'image(checked) &
                   " pixeli iesiti din " & integer'image(N_TOT) severity error;
        elsif tlast_cnt /= 2 then
            report "FAIL [" & NAME & "]: " & integer'image(tlast_cnt) &
                   " impulsuri tlast, se asteptau 2" severity error;
        elsif errors = 0 then
            report "PASS [" & NAME & "]: 2 imagini la rand, " & integer'image(N_TOT) &
                   " pixeli identici cu referinta din C, tlast corect" severity note;
        else
            report "FAIL [" & NAME & "]: " & integer'image(errors) & " erori" severity error;
        end if;
        wait;
    end process finish;

end architecture sim;

------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_top_conv2d is
end entity tb_top_conv2d;

architecture sim of tb_top_conv2d is
    constant REF: string := "D:/000-UTCN/0-FACULTA_ANDREI/ANUL-3/SEM_1/SSC_P/Cod_C/ref/";
begin
    c1: entity work.tb_top_case generic map (
        "8x8 grad+rand", 8, 8,
        REF & "in_8x8_grad.hex", REF & "out_8x8_grad.hex",
        REF & "in_8x8_rand.hex", REF & "out_8x8_rand.hex", 0);
    c4: entity work.tb_top_case generic map (
        "8x8 grad+rand BP", 8, 8,
        REF & "in_8x8_grad.hex", REF & "out_8x8_grad.hex",
        REF & "in_8x8_rand.hex", REF & "out_8x8_rand.hex", 1);
    c2: entity work.tb_top_case generic map (
        "16x16 grad+rand", 16, 16,
        REF & "in_16x16_grad.hex", REF & "out_16x16_grad.hex",
        REF & "in_16x16_rand.hex", REF & "out_16x16_rand.hex", 0);
    c5: entity work.tb_top_case generic map (
        "16x16 grad+rand BP", 16, 16,
        REF & "in_16x16_grad.hex", REF & "out_16x16_grad.hex",
        REF & "in_16x16_rand.hex", REF & "out_16x16_rand.hex", 1);
    c3: entity work.tb_top_case generic map (
        "128x128 rand+rand", 128, 128,
        REF & "in_128x128_rand.hex", REF & "out_128x128_rand.hex",
        REF & "in_128x128_rand.hex", REF & "out_128x128_rand.hex", 0);
    c6: entity work.tb_top_case generic map (
        "128x128 rand+rand BP", 128, 128,
        REF & "in_128x128_rand.hex", REF & "out_128x128_rand.hex",
        REF & "in_128x128_rand.hex", REF & "out_128x128_rand.hex", 1);
end architecture sim;
