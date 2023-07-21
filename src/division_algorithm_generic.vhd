-------------------------------------------------------------------------------------
-- division_algorithm_generic.vhd
-------------------------------------------------------------------------------------
-- Authors:     Hayden Drennen, Maxwell Phillips
-- Copyright:   Ohio Northern University, 2023.
-- License:     GPL v3
-- Description: High precision division algorithm.
-- Precision:   Generic (32 to 4096 bits)
-------------------------------------------------------------------------------------
--
-- Performs integer division on inputs of high bit precision.
-- Takes inputs and returns outputs in sign and magnitude representation.
-- Based on the algorithm introduced in the paper:
-- "High-Precision Priority Encoder Based Integer Division Algorithm"
--
-------------------------------------------------------------------------------------
-- Generics
-------------------------------------------------------------------------------------
--
-- [G_n]: Size of dividend and divisor.
--
-- [G_log_2_n]: (Floor of the) base 2 logarithm of [G_n], i.e., 
--              how many bits are needed to represent its maximum value.
--
-------------------------------------------------------------------------------------
-- Ports
-------------------------------------------------------------------------------------
--
-- [clk]: Hardware clock signal.
--
-- [reset]: Asynchronous reset signal.
--
-- [load]: Control signal for loading the hardware with the dividend and divisor.
--         The hardware begins processing once this goes low after being high.
--
-- [start]: Alternative control signal usually held for entire processing period.
--          Useful when hardware runs at a slower clock than the FPGA.
--
-- [s_dd]: Sign bit of the dividend.
--
-- [dividend]: Magnitude of the dividend.
--
-- [s_dr]: Sign bit of the divisor.
--
-- [divisor]: Magnitude of the divisor.
--
-- [done]: High once the hardware has finished processing.
--
-- [s_q]: Sign bit of the quotient.
--
-- [quotient]: Magnitude of the quotient.
--
-- [s_r]: Sign bit of the remainder.
--
-- [remainder]: Magnitude of the remainder.
-- 
-------------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  use IEEE.math_real.all;

entity division_algorithm_generic is
  generic (
    G_n       : integer := 1024
  );
  port (
    clk       : in    std_logic;
    reset     : in    std_logic;
    load      : in    std_logic;
    start     : in    std_logic;
    s_dd      : in    std_logic;
    dividend  : in    std_logic_vector(G_n - 1 downto 0);
    s_dr      : in    std_logic;
    divisor   : in    std_logic_vector(G_n - 1 downto 0);
    done      : out   std_logic;
    s_q       : out   std_logic;
    quotient  : out   std_logic_vector(G_n - 1 downto 0);
    s_r       : out   std_logic;
    remainder : out   std_logic_vector(G_n - 1 downto 0)
  );
end division_algorithm_generic;

architecture structural of division_algorithm_generic is

  constant G_log_2_n : integer := integer(round(log2(real(G_n))));              -- Base 2 Logarithm of input length n
  constant G_q       : integer := integer(round(2 ** (log2(sqrt(real(G_n)))))); -- q is the least power of 2 greater than sqrt(n).
  constant G_log_2_q : integer := integer(round(log2(real(G_q))));              -- Base 2 Logarithm of q
  constant G_k       : integer := G_n / G_q;                                    -- k is defined as n/q, if n is a perfect square, then k = sqrt(n) = q
  constant G_log_2_k : integer := integer(round(log2(real(G_k))));              -- Base 2 Logarithm of k

  component priority_encoder_generic is
    generic (
      G_n       : integer;
      G_log_2_n : integer;
      G_q       : integer;
      G_log_2_q : integer;
      G_k       : integer;
      G_log_2_k : integer
    );
    port (
      input  : in    std_logic_vector(G_n - 1 downto 0);
      output : out   std_logic_vector(G_log_2_n - 1 downto 0)
    );
  end component priority_encoder_generic;

  component barrel_shifter_generic is
    generic (
      G_n       : integer;
      G_log_2_n : integer;
      G_m       : integer;
      G_q       : integer;
      G_log_2_q : integer;
      G_k       : integer;
      G_log_2_k : integer
    );
    port (
      input  : in    std_logic_vector(G_m - 1 downto 0);
      shamt  : in    std_logic_vector(G_log_2_n - 1 downto 0);
      output : out   std_logic_vector(G_m + G_n - 1 downto 0)
    );
  end component barrel_shifter_generic;

  component decoder_generic is
    generic (
      G_input_size  : integer;
      G_coarse_size : integer;
      G_fine_size   : integer
    );
    port (
      input  : in    std_logic_vector(G_input_size - 1 downto 0);
      output : out   std_logic_vector((2 ** G_input_size) - 1 downto 0)
    );
  end component decoder_generic;

  component carry_lookahead_subtractor is
    generic (
      G_size : integer
    );
    port (
      minuend    : in    std_logic_vector(G_size - 1 downto 0);
      subtrahend : in    std_logic_vector(G_size - 1 downto 0);
      output     : out   std_logic_vector(G_size - 1 downto 0);
      c_out      : out   std_logic
    );
  end component;

  component shamt_calculator is
    generic (
      G_size : integer
    );
    port (
      log_rem : in    std_logic_vector(G_size - 1 downto 0);
      log_dr  : in    std_logic_vector(G_size - 1 downto 0);
      shamt   : out   std_logic_vector(G_size - 1 downto 0);
      c_out   : out   std_logic
    );
  end component;

  signal decoder_mux_output : std_logic_vector(G_n - 1 downto 0);
  signal remainder_reg      : std_logic_vector(G_n - 1 downto 0); -- Latch 1 in paper
  signal next_remainder_reg : std_logic_vector(G_n - 1 downto 0);
  signal quotient_reg       : std_logic_vector(G_n - 1 downto 0); -- Latch 2 in paper
  signal next_quotient_reg  : std_logic_vector(G_n - 1 downto 0);

  signal dr_encoder_output  : std_logic_vector(G_log_2_n - 1 downto 0); -- floor(log_2(divisor))
  signal rem_encoder_output : std_logic_vector(G_log_2_n - 1 downto 0); -- floor(log_2(remainder))

  -- `shamt ` is the number of bits to shift the divisor to align it *one place right* of the remainder (important!). 
  -- Alternatively, it is floor(log_2(remainder)) - floor(log_2(divisor)) - 1, or n_i - 1 in the paper. 
  -- This can be confusing - see shamt_calculator.vhd for more details.
  signal shamt      : std_logic_vector(G_log_2_n - 1 downto 0); 
  signal shamt_cout : std_logic; -- '0' if shift amount is negative, '1' if shift amount is positive

  signal decoder_out_buf : std_logic_vector(G_n - 1 downto 0);
  signal decoder_out     : std_logic_vector(G_n - 1 downto 0);
  signal decoder_out_shl : std_logic_vector(G_n - 1 downto 0);

  signal shifter_out             : std_logic_vector(G_n * 2 - 1 downto 0);
  signal dr_shifted_shamt        : std_logic_vector(G_n - 1 downto 0);
  signal dr_shifted_shamt_plus_1 : std_logic_vector(G_n - 1 downto 0);

  signal s2_output    : std_logic_vector(G_n - 1 downto 0);
  signal s3_output    : std_logic_vector(G_n - 1 downto 0);
  signal s2_carry_out : std_logic; -- C_2 in paper
  signal s3_carry_out : std_logic; -- C_3 in paper

  signal loaded     : std_logic;
  signal done_int   : std_logic; -- Internal done signal
  signal done_latch : std_logic; -- Keeps [done] high even if `done_int` changes

begin

  -- Primary Outputs
  s_r <= s_dd;
  s_q <= s_dd xor s_dr;
  quotient  <= quotient_reg;
  remainder <= remainder_reg;

  -- Priority Encoders
  dr_encoder : priority_encoder_generic
    generic map (
      G_n       => G_n,
      G_log_2_n => G_log_2_n,
      G_q       => G_q,
      G_log_2_q => G_log_2_q,
      G_k       => G_k,
      G_log_2_k => G_log_2_k
    )
    port map (
      input  => divisor,
      output => dr_encoder_output -- floor(log_2(divisor))
    );

  rem_encoder : priority_encoder_generic
    generic map (
      G_n       => G_n,
      G_log_2_n => G_log_2_n,
      G_q       => G_q,
      G_log_2_q => G_log_2_q,
      G_k       => G_k,
      G_log_2_k => G_log_2_k
    )
    port map (
      input  => remainder_reg,
      output => rem_encoder_output -- floor(log_2(remainder))
    );

  -- Subtractor 1
  -- Calculates amount to shift divisor left to align with remainder, *minus 1*
  sub_1 : shamt_calculator
    generic map (
      G_size => G_log_2_n
    )
    port map (
      log_rem => rem_encoder_output,
      log_dr  => dr_encoder_output,
      shamt   => shamt,
      c_out   => shamt_cout
    );

  -- Barrel Shifter and Divisor Shift
  shifter : barrel_shifter_generic
    generic map (
      G_n       => G_n,
      G_log_2_n => G_log_2_n,
      G_m       => G_n,
      G_q       => G_q,
      G_log_2_q => G_log_2_q,
      G_k       => G_k,
      G_log_2_k => G_log_2_k
    )
    port map (
      input  => divisor,
      shamt  => shamt,
      output => shifter_out
    );

  -- If the carry out is zero, that means the shift amount is negative, so we do not want to shift.
  dr_shifted_shamt <= divisor when (shamt_cout = '0') else 
                      shifter_out(G_n - 1 downto 0);

  dr_shifted_shamt_plus_1 <= divisor when (shamt_cout = '0') else
                             shifter_out(G_n - 2 downto 0) & '0';

  -- Decoder
  decode : decoder_generic
    generic map (
      G_input_size  => G_log_2_n,
      G_coarse_size => G_log_2_k,
      G_fine_size   => G_log_2_q
    )
    port map (
      input   => shamt,
      output  => decoder_out_buf
    );

  -- Similar to the barrel shifter, if the shift amount is negative, the result should be 2^0 = 1.
  -- If this is not set explicitly, the result may not be 1 (especially `decoder_out_shl`, which is never 1, only 2^1 (10) at the least).
  decoder_out <= (0 => '1', others => '0') when (shamt_cout = '0') else 
                 decoder_out_buf;

  decoder_out_shl <= (0 => '1', others => '0') when (shamt_cout = '0') else 
                     decoder_out(decoder_out'left - 1 downto 0) & '0';

  -- Subtractors 2 & 3
  sub_2 : carry_lookahead_subtractor
    generic map (
      G_size => G_n
    )
    port map (
      minuend    => remainder_reg,
      subtrahend => dr_shifted_shamt_plus_1,
      output     => s2_output,
      c_out      => s2_carry_out
    );

  sub_3 : carry_lookahead_subtractor
    generic map (
      G_size => G_n
    )
    port map (
      minuend    => remainder_reg,
      subtrahend => dr_shifted_shamt,
      output     => s3_output,
      c_out      => s3_carry_out
    );

  -- Quotient and Remainder Update Logic
  -- The carry-out of S2 determines which output is selected (for both quotient and remainder).
  -- This is because if the result of S2 is negative (s2_carry_out = '0'),
  -- then we have essentially shifted one bit too far [shamt + 1], 
  -- so take the results that have been shifted only [shamt] bits.
  decoder_mux_output <= decoder_out_shl when s2_carry_out = '1' else
                        decoder_out;

  -- The quotient can be updated using an OR gate because we can only shift by powers of two
  -- using the barrel shifter, so in each iteration, `decoder_mux_output` contains only 
  -- a single high bit (as expected from a decoder). Therefore, there is never a carry or overflow
  -- since `decoder_mux_output` is never the same twice (think about long division - you never
  -- divide by the same value twice) and the maximum value of `decoder_mux_output` is the same
  -- size as `quotient_reg`.
  next_quotient_reg <= quotient_reg or decoder_mux_output;

  next_remainder_reg <= s2_output when s2_carry_out = '1' else 
                        s3_output;

  -- Done Logic
  -- The algorithm is complete when the carry-out of both subtractors is negative ('0').
  -- This means that both (remainder - divisor * 2^(shamt + 1)) and (remainder - divisor * 2^(shamt)) 
  -- are negative, meaning the remainder is less than the divisor (the termination condition for division).
  -- The `nor divisor` prevents the hardware from looping infinitely when the divisor is zero.
  done_int <= (s2_carry_out nor s3_carry_out) or (nor divisor);
  
  process (clk, reset) begin
    if (reset = '1') then
      remainder_reg <= (others => '0');
      quotient_reg  <= (others => '0');
      loaded        <= '0';
      done          <= '0';
      done_latch    <= '0';
    elsif (clk'event and clk = '1') then
      if (load = '1' or (start = '1' and loaded = '0')) then
        remainder_reg <= dividend; -- initial remainder is dividend
        quotient_reg  <= (others => '0');
        loaded        <= '1';
      elsif (loaded = '1') then
        if (done_int = '1' or done_latch = '1') then
          done_latch <= '1';
          done       <= '1';
        else
          remainder_reg <= next_remainder_reg;
          quotient_reg  <= next_quotient_reg;
        end if;
      end if;
    end if;
  end process;
end architecture structural;