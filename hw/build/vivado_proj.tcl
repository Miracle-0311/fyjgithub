# Vivado batch project script for Xuantie C908 CNN accelerator
# Usage: vivado -mode batch -source vivado_proj.tcl -tclargs <output_dir>

set script_dir [file dirname [info script]]
set proj_dir   [file normalize [lindex $argv 0]]
if {![file exists $proj_dir]} {
  file mkdir $proj_dir
}

set part "xcvu440-flga2892-2-e"
create_project cnn_accel $proj_dir -part $part -force
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $script_dir/../rtl/*.v]
add_files -fileset sources_1 [glob $script_dir/../sim/*.sv]
add_files -fileset constrs_1 [glob $script_dir/../constr/*.xdc]

read_ip $script_dir/../ip/Xilinx_spram2048_32_e8b4.xci
read_checkpoint $script_dir/../ip/ddr4/axi_ddr4.dcp

synth_design -top cnn_accel_top -part $part -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force $proj_dir/cnn_accel_impl.dcp
write_bitstream -force $proj_dir/cnn_accel.bit
