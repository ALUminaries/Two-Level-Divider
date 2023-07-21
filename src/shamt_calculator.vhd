-------------------------------------------------------------------------------------
-- shamt_calculator.vhd
-------------------------------------------------------------------------------------
-- Authors:     Hayden Drennen, Maxwell Phillips
-- Copyright:   Ohio Northern University, 2023.
-- License:     GPL v3
-- Description: Shift amount calculator.
-- Precision:   Generic, but should be kept small (logarithm of some power of 2)
-------------------------------------------------------------------------------------
--
-- One's complement ripple-carry subtractor customized for use in our
-- high-precision division algorithm. This component is heavily optimized 
-- for our use case and as such can be oblique.
--
-- First, the inputs of this component are the positions of the most significant
-- high bits of the remainder (initially the dividend) and divisor, respectively.
-- Because this component takes the one's complement (logical negation) of [log_dr],
-- the subtrahend, and does *not* add 1 to the end, the result of the subtraction
-- is actually [log_rem] - [log_dr] - 1, *not* [log_rem] - [log_dr] as would be 
-- expected from a typical two's complement subtractor. In other words, [shamt] is 
-- the number of bits to shift the divisor to align it *one place right* of the 
-- remainder. This allows our algorithm to easily decide between shifting either 
-- [shamt] or [shamt] + 1 bits, such that the divisor is aligned one place right 
-- of the remainder, or aligned exactly with the remainder, respectively. This is 
-- necessary because when performing the primary shift for the subtraction, it is
-- possible that aligning the divisor directly with the remainder will result in the
-- value of the shifted divisor being greater than that of the remainder.
-- This means that we have shifted too far, and that we need to shift one place less
-- for `remainder - divisor * some power of 2` to yield a positive (valid) value. 
-- This is why [shamt] is 1 less than might be expected, since it is easier to 
-- work with this way.
--
-- Second, [c_out] is also important because it determines whether [shamt] is 
-- negative or not. If [shamt] is negative, there should *not* be a shift performed.
-- However, because [shamt] is *not* sign extended or two's complement, there is 
-- no easy way to tell if it is negative directly from its magnitude. Thus, [c_out]
-- dictates whether a shift should be performed ([c_out] = '1' and [shamt] > 0) 
-- or not ([c_out] = '0' and [shamt] < 0).
--
-- Finally, it is important to note that there is a special case where [shamt] = -1,
-- and therefore [log_rem] - [log_dr] = 0. In this case, the remainder and divisor
-- are already aligned, and no shift is necessary, *but* it is still necessary to
-- subtract `R - Dr`. This is handled by the multiplexers in the primary algorithm
-- file which consider [c_out] as the select signal.
--
-------------------------------------------------------------------------------------
-- Generics
-------------------------------------------------------------------------------------
--
-- [G_size]: Size of operands.
--
-------------------------------------------------------------------------------------
-- Ports
-------------------------------------------------------------------------------------
--
-- [log_rem]: Floor of the base 2 logarithm of the input remainder of the division
--            operation, the output of one priority encoder.
--
-- [log_dr]: Floor of the base 2 logarithm of the input divisor of the division
--           operation, the output of the other priority encoder.
--
-- [shamt]: Equal to [log_rem] - [log_dr] - 1. This is the number of bits that the 
--          divisor must be left shifted by to align with the remainder, *minus 1*.
--
-- [c_out]: Carry-out: if '0', shift amount is negative; if '1', shamt is positive.
-- 
-------------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  use IEEE.std_logic_unsigned.all;

entity shamt_calculator is
  generic (
    G_size : integer := 8
  );
  port (
    log_rem : in    std_logic_vector(G_size - 1 downto 0);
    log_dr  : in    std_logic_vector(G_size - 1 downto 0);
    shamt   : out   std_logic_vector(G_size - 1 downto 0);
    c_out   : out   std_logic
  );
end shamt_calculator;

architecture structural of shamt_calculator is

  component full_adder is
    port (
      a     : in    std_logic;
      b     : in    std_logic;
      c_in  : in    std_logic;
      sum   : out   std_logic;
      c_out : out   std_logic
    );
  end component;

  signal carry      : std_logic_vector(G_size - 1 downto 0);
  signal log_dr_inv : std_logic_vector(G_size - 1 downto 0);

begin

  -- One's Complement
  log_dr_inv <= not log_dr;

  -- Half Adder
  shamt(0) <= log_rem(0) xor log_dr_inv(0);
  carry(0) <= log_rem(0) and log_dr_inv(0);

  gen_adders : for i in 1 to (G_size - 1) generate
    fa : full_adder
      port map (
        a     => log_rem(i),
        b     => log_dr_inv(i),
        c_in  => carry(i - 1),
        sum   => shamt(i),
        c_out => carry(i)
      );
  end generate gen_adders;

  c_out <= carry(carry'left);

end architecture structural;
