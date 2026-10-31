# Select the CNN firmware and matching CPU/UART/CNN integration test.
# Run after: python firmware/build.py --app cnn
set cnn_fw_dir [file dirname [file normalize [info script]]]
set cnn_repo [file dirname $cnn_fw_dir]
set cnn_image [file join $cnn_fw_dir firmware.hex]
set cnn_tb [file join $cnn_fw_dir sim tb_firmware.v]
if {[llength [get_projects -quiet]] != 1} {error "Open the SoC project first."}
set cnn_project_dir [file normalize [get_property DIRECTORY [current_project]]]
if {![string equal -nocase [file dirname $cnn_project_dir] $cnn_repo] ||
    ![string match SOC_HUFLIT_2026_parallel_* [file tail $cnn_project_dir]]} {
    error "Open the original SOC_HUFLIT_2026 project before selecting CNN firmware."
}
set cnn_design_image [file join $cnn_project_dir [get_property NAME [current_project]].srcs sources_1 new firmware.hex]
foreach cnn_file [list $cnn_image $cnn_tb] {
    if {![file isfile $cnn_file]} {error "Missing $cnn_file; build CNN firmware first."}
}
file copy -force $cnn_image $cnn_design_image
if {[llength [get_files -quiet $cnn_design_image]] == 0} {
    add_files -fileset sources_1 -norecurse $cnn_design_image
}
set_property FILE_TYPE {Memory Initialization Files} [get_files $cnn_design_image]
set_property USED_IN_SYNTHESIS true [get_files $cnn_design_image]
set_property USED_IN_SIMULATION true [get_files $cnn_design_image]
set cnn_simset [current_fileset -simset]
if {[llength [get_files -quiet $cnn_tb]] == 0} {
    add_files -fileset $cnn_simset -norecurse $cnn_tb
}
set_property FILE_TYPE SystemVerilog [get_files $cnn_tb]
foreach cnn_frame_name {human_frames.mem nonhuman_frame.mem} {
    set cnn_frame_path [file join $cnn_repo CNN_RTL $cnn_frame_name]
    if {![file isfile $cnn_frame_path]} {error "Missing COCO example: $cnn_frame_path"}
    if {[llength [get_files -quiet $cnn_frame_path]] == 0} {
        add_files -fileset $cnn_simset -norecurse $cnn_frame_path
    }
    set_property FILE_TYPE {Memory Initialization Files} [get_files $cnn_frame_path]
    set_property USED_IN_SYNTHESIS false [get_files $cnn_frame_path]
    set_property USED_IN_SIMULATION true [get_files $cnn_frame_path]
}
set_property TOP tb_firmware $cnn_simset
set_property -name xsim.simulate.xsim.more_options -value {-testplusarg FULL_IMAGES} -objects $cnn_simset
set_property xsim.simulate.runtime all $cnn_simset
update_compile_order -fileset sources_1
puts "Selected CNN UART firmware and tb_firmware (FULL_IMAGES)."
puts "Rebuild synthesis/implementation/bitstream to run this firmware on the board."
