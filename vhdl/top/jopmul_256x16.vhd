--
--
--  This file is a part of JOP, the Java Optimized Processor
--
--  Copyright (C) 2001-2008, Martin Schoeberl (martin@jopdesign.com)
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
--


--
--	jop_256x16.vhd
--
--	top level for a 256x16 SRMA board (e.g. Altera DE2 board)
--
--	2006-08-06	adapted from jopcyc.vhd
--	2007-06-04	Use jopcpu and change component interface to records
--
--


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.jop_types.all;
use work.sc_pack.all;
use work.sc_arbiter_pack.all;
use work.jop_config.all;


entity jop is

generic (
	ram_cnt		: integer := 2;		-- clock cycles for external ram
--	rom_cnt		: integer := 3;		-- clock cycles for external rom OK for 20 MHz
	rom_cnt		: integer := 10;	-- clock cycles for external rom for 100 MHz
	jpc_width	: integer := 11;	-- address bits of java bytecode pc = cache size
	block_bits	: integer := 4;		-- 2*block_bits is number of cache blocks
	spm_width	: integer := 0;		-- size of scratchpad RAM (in number of address bits for 32-bit words)
	cpu_cnt		: integer := 4		-- number of cpus
);

port (
	clk				: in std_logic;
--
--	serial interface
--
	ser_txd			: out std_logic;
	ser_rxd			: in std_logic;

--
--	watchdog
--
	wd				: out std_logic;

--
--	only one ram bank
--
	rama_a		: out std_logic_vector(17 downto 0);
	rama_d		: inout std_logic_vector(15 downto 0);
	rama_ncs	: out std_logic;
	rama_noe	: out std_logic;
	rama_nlb	: out std_logic;
	rama_nub	: out std_logic;
	rama_nwe	: out std_logic

);
end jop;

architecture rtl of jop is

--
--	components:
--

component pll is
generic (multiply_by : natural; divide_by : natural);
port (
	inclk0		: in std_logic;
	c0			: out std_logic
);
end component;


--
--	Signals
--
	signal clk_int			: std_logic;

	signal int_res			: std_logic;
	signal res_cnt			: unsigned(2 downto 0) := "000";	-- for the simulation

	attribute altera_attribute : string;
	attribute altera_attribute of res_cnt : signal is "POWER_UP_LEVEL=LOW";

--
--	jopcpu connections
--
	signal sc_arb_out		: arb_out_type(0 to cpu_cnt-1);
	signal sc_arb_in		: arb_in_type(0 to cpu_cnt-1);
	
	signal sc_mem_out		: sc_out_type;
	signal sc_mem_in		: sc_in_type;
	
	signal sc_io_out		: sc_out_array_type(0 to cpu_cnt-1);
	signal sc_io_in			: sc_in_array_type(0 to cpu_cnt-1);
	signal irq_in			: irq_in_array_type(0 to cpu_cnt-1);
	signal irq_out			: irq_out_array_type(0 to cpu_cnt-1);
	signal exc_req			: exception_array_type(0 to cpu_cnt-1);

	signal xc_int : std_logic_vector(0 to cpu_cnt-1);
	type xc_out_array is array (0 to cpu_cnt-1) of std_logic_vector(cpu_cnt-1 downto 0);
    signal xc_out : xc_out_array;

--
--	IO interface
--
	type wd_out_array is array (0 to cpu_cnt-1) of std_logic;
	signal wd_out			: wd_out_array;
	
	-- for generation of internal reset
-- memory interface

	signal ram_addr			: std_logic_vector(17 downto 0);
	signal ram_dout			: std_logic_vector(15 downto 0);
	signal ram_din			: std_logic_vector(15 downto 0);
	signal ram_dout_en	: std_logic;
	signal ram_ncs			: std_logic;
	signal ram_noe			: std_logic;
	signal ram_nwe			: std_logic;
	
-- cmpsync

	signal sync_in_array	: sync_in_array_type(0 to cpu_cnt-1);
	signal sync_out_array	: sync_out_array_type(0 to cpu_cnt-1);

-- signals for UART arbitration
	signal uart_out			: arb_out_type(0 to cpu_cnt-1);
	signal uart_in			: arb_in_type(0 to cpu_cnt-1);
    signal sc_uart_out		: sc_out_type;
    signal sc_uart_in		: sc_in_type;
    signal sc_uart_tf_ready	: std_logic;
    signal sc_uart_rf_avail : std_logic;
    signal sc_uart_pa_error : std_logic;

-- not available at this board:
	signal ser_ncts			: std_logic;
	signal ser_nrts			: std_logic;
	
-- remove the comment for RAM access counting
-- signal ram_count		: std_logic;

begin

--
--	intern reset
--	no extern reset, epm7064 has too less pins
--

process(clk_int)
begin
	if rising_edge(clk_int) then
		if (res_cnt/="111") then
			res_cnt <= res_cnt+1;
		end if;

		int_res <= not res_cnt(0) or not res_cnt(1) or not res_cnt(2);
	end if;
end process;

--
--	components of jop
--
	pll_inst : pll generic map(
		multiply_by => pll_mult,
		divide_by => pll_div
	)
	port map (
		inclk0	 => clk,
		c0	 => clk_int
	);
-- clk_int <= clk;

-- process(wd_out)
-- variable wd_help : std_logic;
-- 	begin
-- 		wd_help := '0';
-- 		for i in 0 to cpu_cnt-1 loop
-- 			wd_help := wd_help or wd_out(i);
-- 		end loop;
-- 		wd <= wd_help;
-- end process;

	wd <= wd_out(0);

	gen_cpu: for i in 0 to cpu_cnt-1 generate
		cpu: entity work.jopcpu
			generic map(
				jpc_width => jpc_width,
				block_bits => block_bits,
				spm_width => spm_width
			)
			port map(clk_int, int_res,
				sc_arb_out(i), sc_arb_in(i),
				sc_io_out(i), sc_io_in(i),
				irq_in(i), irq_out(i), exc_req(i));
	end generate;
	
	arbiter: entity work.arbiter
		generic map(
			addr_bits => SC_ADDR_SIZE,
			cpu_cnt => cpu_cnt
		)
		port map(clk_int, int_res,
			sc_arb_out, sc_arb_in,
			sc_mem_out, sc_mem_in);

	-- io for processor 0
	io: entity work.scio generic map (
			cpu_id => 0,
			cpu_cnt => cpu_cnt
		)
		port map (clk_int, int_res,
			sc_io_out(0), sc_io_in(0),
			irq_in(0), irq_out(0), exc_req(0),

			sync_out => sync_out_array(0),
			sync_in => sync_in_array(0),

			uart_out => uart_out(0),
			uart_in => uart_in(0),
				  
			xc_int => xc_int(0),
			xc_out => xc_out(0),

			wd => wd_out(0),
			l => open,
			r => open,
			t => open,
			b => open
			-- remove the comment for RAM access counting
			-- ram_cnt => ram_count
		);
		
	-- io for other processors
	gen_io: for i in 1 to cpu_cnt-1 generate
		io2: entity work.scio generic map (
			cpu_id => i,
			cpu_cnt => cpu_cnt
		)
		port map (clk_int, int_res,
			sc_io_out(i), sc_io_in(i),
			irq_in(i), irq_out(i), exc_req(i),

			sync_out => sync_out_array(i),
			sync_in => sync_in_array(i),

			uart_out => uart_out(i),
			uart_in => uart_in(i),

			xc_int => xc_int(i),
			xc_out => xc_out(i),
			
			wd => open,
			l => open,
			r => open,
			t => open,
			b => open
			-- remove the comment for RAM access counting
			-- ram_cnt => ram_count
		);
	end generate;

	xc: process (xc_out)
		variable t : std_logic;
	begin  -- process xc
		for i in 0 to cpu_cnt-1 loop
			t := '0';
			for k in 0 to cpu_cnt-1 loop
				t := t or xc_out(k)(i);
			end loop;  -- k
			xc_int(i) <= t;
		end loop;  -- i
	end process xc;
			
	scm: entity work.sc_mem_if
		generic map (
			ram_ws => ram_cnt-1,
			addr_bits => 18
		)
		port map (clk_int, int_res,
			sc_mem_out, sc_mem_in,

			ram_addr => ram_addr,
			ram_dout => ram_dout,
			ram_din => ram_din,
			ram_dout_en	=> ram_dout_en,
			ram_ncs => ram_ncs,
			ram_noe => ram_noe,
			ram_nwe => ram_nwe
		);
		
   -- shared access to UART
	cmpua : entity work.sc_cmpuart
		generic map (
			addr_bits => 1,
			cpu_cnt	  => cpu_cnt
			)
		port map (
			clk		 => clk_int,
			reset	 => int_res,
			-- SimpCon interfaces
			arb_out	 => uart_out,
			arb_in	 => uart_in,
			uart_out => sc_uart_out,
			uart_in	 => sc_uart_in,
			-- signals to UART
			tf_ready => sc_uart_tf_ready,
			rf_avail => sc_uart_rf_avail,
			pa_error => sc_uart_pa_error
			);

	ua: entity work.sc_uart
		generic map (
			addr_bits => 1,
			clk_freq => clk_freq,
			baud_rate => 115200,
			txf_depth => 32,
			txf_thres => 16,
			rxf_depth => 32,
			rxf_thres => 16
			)
		port map(
			clk => clk_int,
			reset => int_res,
			-- SimpCon interface
			address => sc_uart_out.address(0 downto 0),
			wr_data => sc_uart_out.wr_data,
			rd => sc_uart_out.rd,
			wr => sc_uart_out.wr,
			rd_data => sc_uart_in.rd_data,
			rdy_cnt => sc_uart_in.rdy_cnt,
			-- signals for UART arbiter
			tf_ready => sc_uart_tf_ready,
			rf_avail => sc_uart_rf_avail,
			pa_error => sc_uart_pa_error,
			-- interface to environment
			txd	 => ser_txd,
			rxd	 => ser_rxd,
			ncts => ser_ncts,
			nrts => ser_nrts
			);

	ser_ncts <= '0';
		
	-- syncronization of processors
	sync: entity work.cmpsync generic map (
		cpu_cnt => cpu_cnt)
		port map
		(
			clk => clk_int,
			reset => int_res,
			sync_in_array => sync_in_array,
			sync_out_array => sync_out_array
		);
		
		
	process(ram_dout_en, ram_dout)
	begin
		if ram_dout_en='1' then
			rama_d <= ram_dout;
		else
			rama_d <= (others => 'Z');
		end if;
	end process;

	ram_din <= rama_d;
	
	-- remove the comment for RAM access counting
	-- ram_count <= ram_ncs;

--
--	To put this RAM address in an output register
--	we have to make an assignment (FAST_OUTPUT_REGISTER)
--
	rama_a <= ram_addr;
	rama_ncs <= ram_ncs;
	rama_noe <= ram_noe;
	rama_nwe <= ram_nwe;
	rama_nlb <= '0';
	rama_nub <= '0';


end rtl;
