# -----------------------------------------------------------------------------
# Xuantie C908 CNN Accelerator top-level constraints
# Target device: xcvu440-flga2892-2-e
# -----------------------------------------------------------------------------

set_property PART xcvu440-flga2892-2-e [current_project]

create_clock -period 5.000 -name sys_clk [get_ports clk]
set_property PACKAGE_PIN AB12 [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports clk]

set_property PACKAGE_PIN AC34 [get_ports rst_b]
set_property IOSTANDARD LVCMOS18 [get_ports rst_b]
set_property PULLUP true [get_ports rst_b]

# COP interface pins (example bindings)
set_property PACKAGE_PIN AF23 [get_ports {pad_cop_req_vld}]
set_property PACKAGE_PIN AF22 [get_ports {cop_pad_resp_vld}]

# Add more pin mappings based on the SoC integration note.
