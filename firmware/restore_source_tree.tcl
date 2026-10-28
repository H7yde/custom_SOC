# Restore the original Vivado Sources hierarchy in the OPEN SoC project.
# No files, module instances, firmware image, or simulation top are changed.
set tree_project [current_project -quiet]
if {[llength $tree_project] == 0} { error "Open the SoC Vivado project first" }
set_property -name source_mgmt_mode -value DisplayOnly -objects $tree_project
update_compile_order -fileset sources_1
set tree_simset [current_fileset -simset]
if {[llength $tree_simset] > 0} {
    update_compile_order -fileset $tree_simset
}
puts {Sources hierarchy restored: testbench -> dut -> child modules.}
