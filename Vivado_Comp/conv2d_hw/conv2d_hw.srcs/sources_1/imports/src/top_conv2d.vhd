
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_conv2d is
    generic (
        IMG_W : integer := 512;
        IMG_H : integer := 512
    );
    port (
        clk: in  std_logic;
        rst_n: in  std_logic;   -- reset activ LOW

        -- AXI4-Stream Slave (pixeli de intrare)
        s_axis_tdata: in  std_logic_vector(7 downto 0);
        s_axis_tvalid: in  std_logic;
        s_axis_tlast: in  std_logic;
        s_axis_tready: out std_logic;

        -- AXI4-Stream Master (pixeli convolutionati)
        m_axis_tdata: out std_logic_vector(7 downto 0);
        m_axis_tvalid: out std_logic;
        m_axis_tlast: out std_logic;
        m_axis_tready: in  std_logic
    );
end entity top_conv2d;

architecture Behavioral of top_conv2d is

    -- FSM de intrare
    type state_t is (RUN, FLUSH);
    signal state: state_t := RUN;
    signal flush_cnt : integer range 0 to IMG_W := 0;   -- numara IMG_W + 1 cicluri

    -- intrarea in line_buffer
    signal lb_valid_in: std_logic;
    signal lb_pixel_in: std_logic_vector(7 downto 0);

    -- line_buffer -> window_3x3
    signal lb_row_top: std_logic_vector(7 downto 0);
    signal lb_row_mid: std_logic_vector(7 downto 0);
    signal lb_row_bot: std_logic_vector(7 downto 0);
    signal lb_valid_out: std_logic;

    -- window_3x3 -> conv_mac
    signal w00, w01, w02 : std_logic_vector(7 downto 0);
    signal w10, w11, w12 : std_logic_vector(7 downto 0);
    signal w20, w21, w22 : std_logic_vector(7 downto 0);
    signal win_valid : std_logic;

    -- iesirea din conv_mac
    signal mac_pixel : std_logic_vector(7 downto 0);
    signal mac_valid : std_logic;

    -- contor pixeli de iesire (pentru tlast)
    signal out_cnt : integer range 0 to IMG_W * IMG_H - 1 := 0;

    -- FIFO de iesire (backpressure): 32 cuvinte x (8 date + 1 tlast)
    -- se opreste intrarea cand are >= 16 cuvinte; raman ~8 pixeli in pipeline
    constant FIFO_DEPTH: integer := 32;
    constant FIFO_AFULL: integer := 16;
    type fifo_mem_t is array (0 to FIFO_DEPTH - 1) of std_logic_vector(8 downto 0);
    signal fifo_mem: fifo_mem_t := (others => (others => '0'));
    signal fifo_wr: integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_rd: integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_cnt: integer range 0 to FIFO_DEPTH := 0;
    signal fifo_push: std_logic;
    signal fifo_pop: std_logic;
    signal fifo_din: std_logic_vector(8 downto 0);
    signal can_go: std_logic;
    signal mac_last: std_logic;

    -- coeficienti Gaussian 3x3: 1 2 1 / 2 4 2 / 1 2 1 (suma 16, SHIFT = 4)
    constant K00 : signed(7 downto 0) := to_signed(1, 8);
    constant K01 : signed(7 downto 0) := to_signed(2, 8);
    constant K02 : signed(7 downto 0) := to_signed(1, 8);
    constant K10 : signed(7 downto 0) := to_signed(2, 8);
    constant K11 : signed(7 downto 0) := to_signed(4, 8);
    constant K12 : signed(7 downto 0) := to_signed(2, 8);
    constant K20 : signed(7 downto 0) := to_signed(1, 8);
    constant K21 : signed(7 downto 0) := to_signed(2, 8);
    constant K22 : signed(7 downto 0) := to_signed(1, 8);

begin

    ------------------------------------------------------------------
    -- FSM de intrare: RUN (accepta pixeli) / FLUSH (impinge dummy)
    ------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= RUN;
                flush_cnt <= 0;
            else
                case state is
                    when RUN =>
                        -- handshake = tvalid and tready (tready = can_go)
                        if s_axis_tvalid = '1' and s_axis_tlast = '1' and can_go = '1' then
                            state <= FLUSH;
                            flush_cnt <= 0;
                        end if;
                    when FLUSH =>
                        -- dummy-urile avanseaza doar cand FIFO-ul are loc
                        if can_go = '1' then
                            if flush_cnt = IMG_W then       -- al (IMG_W + 1)-lea dummy
                                state <= RUN;
                                flush_cnt <= 0;
                            else
                                flush_cnt <= flush_cnt + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- pipeline-ul nu are stall: intrarea se opreste cand FIFO-ul e aproape plin
    can_go <= '1' when fifo_cnt < FIFO_AFULL else '0';

    s_axis_tready <= '1' when (state = RUN and rst_n = '1' and can_go = '1') else '0';

    -- in RUN pixelul vine de pe stream; in FLUSH se trimite dummy cu valid = 1
    -- (cand FIFO-ul e aproape plin nu se trimite nimic, nici dummy)
    lb_valid_in <= (s_axis_tvalid and can_go) when state = RUN else can_go;
    lb_pixel_in <= s_axis_tdata  when state = RUN else (others => '0');

    ------------------------------------------------------------------
    -- Lantul de procesare
    ------------------------------------------------------------------
    u_lb : entity work.line_buffer
        generic map (IMG_W => IMG_W)
        port map (
            clk => clk,
            rst_n => rst_n,
            valid_in => lb_valid_in,
            pixel_in => lb_pixel_in,
            row_top => lb_row_top,
            row_mid => lb_row_mid,
            row_bot => lb_row_bot,
            valid_out => lb_valid_out
        );

    u_win : entity work.window_3x3
        generic map (IMG_W => IMG_W, IMG_H => IMG_H)
        port map (
            clk => clk,
            rst_n => rst_n,
            valid_in => lb_valid_out,
            row_top => lb_row_top,
            row_mid => lb_row_mid,
            row_bot => lb_row_bot,
            w00 => w00, w01 => w01, w02 => w02,
            w10 => w10, w11 => w11, w12 => w12,
            w20 => w20, w21 => w21, w22 => w22,
            valid_out => win_valid
        );

    u_mac : entity work.conv_mac
        generic map (SHIFT => 4)
        port map (
            clk => clk,
            rst_n => rst_n,
            valid_in => win_valid,
            w00 => w00, w01 => w01, w02 => w02,
            w10 => w10, w11 => w11, w12 => w12,
            w20 => w20, w21 => w21, w22 => w22,
            k00 => K00, k01 => K01, k02 => K02,
            k10 => K10, k11 => K11, k12 => K12,
            k20 => K20, k21 => K21, k22 => K22,
            pixel_out => mac_pixel,
            valid_out => mac_valid
        );

    ------------------------------------------------------------------
    -- tlast pe ultimul pixel (index IMG_W*IMG_H - 1), apoi FIFO de iesire
    ------------------------------------------------------------------
    mac_last <= '1' when (mac_valid = '1' and out_cnt = IMG_W * IMG_H - 1) else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                out_cnt <= 0;
            elsif mac_valid = '1' then
                if out_cnt = IMG_W * IMG_H - 1 then
                    out_cnt <= 0;
                else
                    out_cnt <= out_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    fifo_push <= mac_valid;
    fifo_din <= mac_last & mac_pixel;
    fifo_pop <= '1' when (fifo_cnt > 0 and m_axis_tready = '1') else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                fifo_wr <= 0;
                fifo_rd <= 0;
                fifo_cnt <= 0;
            else
                if fifo_push = '1' then
                    fifo_mem(fifo_wr) <= fifo_din;
                    if fifo_wr = FIFO_DEPTH - 1 then
                        fifo_wr <= 0;
                    else
                        fifo_wr <= fifo_wr + 1;
                    end if;
                end if;
                if fifo_pop = '1' then
                    if fifo_rd = FIFO_DEPTH - 1 then
                        fifo_rd <= 0;
                    else
                        fifo_rd <= fifo_rd + 1;
                    end if;
                end if;
                if fifo_push = '1' and fifo_pop = '0' then
                    fifo_cnt <= fifo_cnt + 1;
                elsif fifo_push = '0' and fifo_pop = '1' then
                    fifo_cnt <= fifo_cnt - 1;
                end if;
            end if;
        end if;
    end process;

    m_axis_tvalid <= '1' when fifo_cnt > 0 else '0';
    m_axis_tdata <= fifo_mem(fifo_rd)(7 downto 0);
    m_axis_tlast <= fifo_mem(fifo_rd)(8) when fifo_cnt > 0 else '0';

end Behavioral;
