source [file join [file dirname [file normalize [info script]]] project_paths.tcl]
# Run in the existing Vivado project if it was open during file restoration:
# source D:/LAB/custom_SOC-main/firmware/restore_picorv32.tcl
set restore_repo [file normalize [file join [file dirname [info script]] ..]]
set restore_cpu [file join [soc_paths::project] SOC_HUFLIT_2026.srcs sources_1 new picorv32.v]
if {![file isfile $restore_cpu]} { error "Restored source missing: $restore_cpu" }
if {[llength [get_projects -quiet]] != 1} { error "Open the SoC project first." }
if {[llength [get_files -quiet $restore_cpu]] == 0} {
    add_files -fileset sources_1 -norecurse $restore_cpu
}
set_property used_in_synthesis true [get_files $restore_cpu]
set_property used_in_simulation true [get_files $restore_cpu]
update_compile_order -fileset sources_1
puts "picorv32.v restored in sources_1. Run synthesis again."
