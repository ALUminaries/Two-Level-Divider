-------------------------------------------------------------------------------------
-- cla_subtractor.vhd
-------------------------------------------------------------------------------------
-- Authors:     Hayden Drennen, Maxwell Phillips
-- Copyright:   Ohio Northern University, 2023.
-- License:     GPL v3
-- Description: High precision division algorithm.
-- Precision:   Generic
-------------------------------------------------------------------------------------
--
-- Subtraction wrapper for standard carry-look-ahead adder.
-- Takes two's complement of the second input by inverting it 
-- and incrementing by setting the carry-in of the adder to 1.
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
-- [minuend]: Minuend (operand to be subtracted from).
--
-- [subtrahend]: Subtrahend (operand to subtract from the minuend).
--           Will be negated and added to the minuend via two's complement.
--
-- [output]: Result of [minuend] - [subtrahend].
--
-- [c_out]: Top-level carry out of the carry-look-ahead adder.
-- 
-------------------------------------------------------------------------------------

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  use IEEE.std_logic_unsigned.all;

entity carry_lookahead_subtractor is
  generic (
    G_size : integer
  );
  port (
    minuend    : in    std_logic_vector(G_size - 1 downto 0);
    subtrahend : in    std_logic_vector(G_size - 1 downto 0);
    output     : out   std_logic_vector(G_size - 1 downto 0);
    c_out      : out   std_logic
  );
end carry_lookahead_subtractor;

architecture structural of carry_lookahead_subtractor is

  component cla_top is
    generic (
      G_size : integer
    );
    port (
      a      : in    std_logic_vector(G_size - 1 downto 0);
      b      : in    std_logic_vector(G_size - 1 downto 0);
      c_in   : in    std_logic; -- carry in
      sum    : out   std_logic_vector(G_size - 1 downto 0);
      c_out  : out   std_logic; -- carry out
      prop_g : out   std_logic; -- group propagate
      gen_g  : out   std_logic  -- group generate
    );
  end component;

  signal subtrahend_inv : std_logic_vector(G_size - 1 downto 0);

begin

  subtrahend_inv <= not subtrahend;

  cla : cla_top
    generic map (
      G_size => G_size
    )
    port map (
      a => minuend,
      b => subtrahend_inv,
      c_in => '1',
      sum => output,
      c_out => c_out,
      prop_g => open,
      gen_g => open
    );

end architecture structural;
