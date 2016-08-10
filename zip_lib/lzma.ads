--  Items that are common to LZMA encoding and LZMA decoding.

with Interfaces;
with System;

package LZMA is

  --  Nothing public so far...

private

  use Interfaces;

  --  These integer types are defined in the LZMA specification
  --  (DRAFT version, 2015-06-14, by Igor Pavlov)

  subtype Byte is Unsigned_8;
  subtype UInt16 is Unsigned_16;
  subtype UInt32 is Unsigned_32;
  type Unsigned is mod 2 ** System.Word_Size;

  subtype Literal_context_bits_range is Integer range 0..8;
  subtype Literal_position_bits_range is Integer range 0..4;
  subtype Position_bits_range is Integer range 0..4;

  ----------------------------
  --  Finite state machine  --
  ----------------------------

  States_count : constant := 12;  --  LZMA specification name: "kNumStates"
  subtype State_range is Unsigned range 0..States_count-1;
  type Transition is array(State_range) of State_range;

  ------------------------------------ From ...  0  1  2  3  4  5  6   7   8   9  10  11
  Update_State_Literal  : constant Transition:= (0, 0, 0, 0, 1, 2, 3,  4,  5,  6,  4,  5);
  Update_State_Match    : constant Transition:= (7, 7, 7, 7, 7, 7, 7, 10, 10, 10, 10, 10);
  Update_State_Rep      : constant Transition:= (8, 8, 8, 8, 8, 8, 8, 11, 11, 11, 11, 11);
  Update_State_ShortRep : constant Transition:= (9, 9, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11);

  --  Context for improving compression of aligned data,
  --  modulo 2**n = 2, 4, 8 or 16 (max) bytes, or disabled: n = 0.
  Max_pos_bits : constant := 4;  --  LZMA specification name: "kNumPosBitsMax"
  Max_pos_states_count : constant := 2**Max_pos_bits;
  subtype Pos_state_range is Unsigned range 0 .. Max_pos_states_count-1;

  ----------------------------------------
  --  Probability model for bit coding  --
  ----------------------------------------

  Probability_model_bits  : constant:= 11;  --  LZMA specification name: "kNumBitModelTotalBits"
  Probability_model_count : constant:= 2 ** Probability_model_bits;

  Probability_change_bits : constant:= 5;   --  LZMA specification name: "kNumMoveBits"

  --  All probabilities are initialized with p=0.5. LZMA specification name: "PROB_INIT_VAL"
  Initial_probability : constant := Probability_model_count / 2;

  --  Type for storing probabilities, must be at least 11 bit.
  subtype CProb is UInt32;  --  LZMA specification recommends UInt16.
  type CProb_array is array(Unsigned range <>) of CProb;

  Align_bits       : constant := 4;  --  LZMA specification name: "kNumAlignBits"
  Align_table_size : constant := 2 ** Align_bits;
  Align_mask       : constant := Align_table_size - 1;

  subtype Bits_3_range is Unsigned range 0 .. 2**3 - 1;
  subtype Bits_6_range is Unsigned range 0 .. 2**6 - 1;
  subtype Bits_8_range is Unsigned range 0 .. 2**8 - 1;
  subtype Bits_NAB_range is Unsigned range 0 .. 2**Align_bits - 1;

  subtype Probs_3_bits is CProb_array(Bits_3_range);
  subtype Probs_6_bits is CProb_array(Bits_6_range);
  subtype Probs_8_bits is CProb_array(Bits_8_range);
  subtype Probs_NAB_bits is CProb_array(Bits_NAB_range);

  --------------------------------------------------
  --  Probabilities for the binary decision tree  --
  --------------------------------------------------

  type Probs_state is array(State_range) of CProb;
  type Probs_state_and_pos_state is array(State_range, Pos_state_range) of CProb;

  type Probs_for_switches is record
    --  This is the context for the switch between a Literal and a LZ Distance-Length code
    match     : Probs_state_and_pos_state:= (others => (others => Initial_probability));
    --  These are contexts for various repetition modes
    rep       : Probs_state:= (others => Initial_probability);
    rep_g0    : Probs_state:= (others => Initial_probability);
    rep_g1    : Probs_state:= (others => Initial_probability);
    rep_g2    : Probs_state:= (others => Initial_probability);
    rep0_long : Probs_state_and_pos_state:= (others => (others => Initial_probability));
  end record;

  ------------------------------------
  --  Probabilities for LZ lengths  --
  ------------------------------------

  type Low_mid_coder_probs is array(Pos_state_range) of Probs_3_bits;

  --  Probabilities used for encoding LZ lengths.
  --  LZMA specification name: "CLenDecoder"
  type Probs_for_LZ_Lengths is record
    choice_1   : CProb               := Initial_probability;  --  0: low coder; 1: mid or high
    choice_2   : CProb               := Initial_probability;  --  0: mid; 1: high
    low_coder  : Low_mid_coder_probs := (others => (others => Initial_probability));
    mid_coder  : Low_mid_coder_probs := (others => (others => Initial_probability));
    high_coder : Probs_8_bits        := (others => Initial_probability);
  end record;

  --------------------------------------
  --  Probabilities for LZ distances  --
  --------------------------------------

  Len_to_pos_states  : constant := 4;
  subtype Slot_coder_range is Unsigned range 0 .. Len_to_pos_states - 1;
  type Slot_coder_probs is array(Slot_coder_range) of Probs_6_bits;
  Dist_slot_bits: constant:= 6;  --  "kNumPosSlotBits"

  Start_dist_model_index : constant :=  4;  --  "kStartPosModelIndex"
  End_dist_model_index   : constant := 14;  --  LZMA specification name: "kEndPosModelIndex"
  Num_full_distances  : constant := 2 ** (End_dist_model_index / 2);  --  "kNumFullDistances"

  subtype Pos_coder_range is Unsigned range 0 .. Num_full_distances - End_dist_model_index;
  subtype Pos_coder_probs is CProb_array(Pos_coder_range);

  type Probs_for_LZ_Distances is record
    slot_coder  : Slot_coder_probs := (others => (others => Initial_probability));
    align_coder : Probs_NAB_bits   := (others => Initial_probability);
    pos_coder   : Pos_coder_probs  := (others => Initial_probability);
  end record;

  --------------------------------------
  --  All probabilities used by LZMA  --
  --------------------------------------

  type All_probabilities(last_lit_prob_index: Unsigned) is record
    --  Literals:
    lit     : CProb_array(0..last_lit_prob_index):= (others => Initial_probability);
    --  Distances:
    dist    : Probs_for_LZ_Distances;
    --  Lengths:
    len     : Probs_for_LZ_Lengths;
    rep_len : Probs_for_LZ_Lengths;
    --  Decision tree switches:
    switch  : Probs_for_switches;
  end record;

  -------------
  --  Misc.  --
  -------------

  --  Minimum dictionary (= plain text buffer of n previous bytes)
  --  size is 4096. LZMA specification name: "LZMA_DIC_MIN"
  Min_dictionary_size : constant := 2 ** 12;

  --  Log2-style encoding of LZ lengths
  Len_low_bits     : constant:= 3;
  Len_low_symbols  : constant:= 2 ** Len_low_bits;
  Len_mid_bits     : constant:= 3;
  Len_mid_symbols  : constant:= 2 ** Len_mid_bits;
  Len_high_bits    : constant:= 8;
  Len_high_symbols : constant:= 2 ** Len_high_bits;
  Len_symbols      : constant:= Len_low_symbols + Len_mid_symbols + Len_high_symbols;

  Min_match_length : constant:= 2;  --  "LZMA_MATCH_LEN_MIN"
  Max_match_length : constant:= Min_match_length + Len_symbols - 1;  --  "LZMA_MATCH_LEN_MAX"

  --------------------------------------------------
  --  Binary values of various decision switches  --
  --------------------------------------------------

  --  LZ literal vs. DL code
  literal_choice : constant:= 0;
  DL_code_choice : constant:= 1;

  --  Simple match vs . "Rep match"
  Simple_match_choice : constant:= 0;
  Rep_match_choice    : constant:= 1;

  --------------------
  --  Range coding  --
  --------------------

  --  Normalization threshold. When the range width is below that value,
  --  a shift is needed.
  width_threshold : constant := 2**24;  --  LZMA specification name: "kTopValue"

end LZMA;
