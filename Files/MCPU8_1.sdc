create_clock -name clk -period 10.0 [get_ports clk]

set_input_delay 0.2 -clock clk [all_inputs]


set_output_delay 0.2 -clock clk [get_ports { \
  PC_OUT      \
  MAR_OUT     \
  IR_OUT1     \
  IR_OUT2     \
  DATA_OUT1   \
  ADDR_OUT1   \
  COUNT_OUT   \
  ACCUMULATOR_OUT \
  DATA_OUTPUT \
  B_REG       \
  ALU_OUT     \
  OR_out      \
  CW          \
  EP CP LM CE LI EI CS LOAD CLR INC LA EA LB SU AD EU LO \
}]
