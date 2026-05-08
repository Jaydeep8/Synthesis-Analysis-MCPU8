set_attribute hdl_search_path "./"
set_attribute library slow_vdd1v0_basicCells.lib
read_hdl -v2001 MCPU8_1.v
elaborate MCPU8_1
read_sdc MCPU8_1.sdc
check_design > check_design.rpt
#set_attribute syn_generic_effort medium
#set_attribute syn_map_effort medium
synthesize -to_generic
synthesize -to_mapped
#write_hdl -v2001 MCPU8 > netlist.v

report timing > timing.rpt
report area   > area.rpt
report power  > power.rpt
report gates  > gates.rpt
