# Validate an isolated snapshot; never save the original project or BD.
set audit_dir [file dirname [file normalize [info script]]]
set audit_bd [file join $audit_dir usb_hdmi_audit usb_hdmi_system.bd]
create_project usb_hdmi_audit_project [file join $audit_dir usb_hdmi_audit_project] -part xc7z020clg400-1
set_property ip_repo_paths {D:/Vivado_IDE/lib/vivado-library-master} [current_project]
update_ip_catalog
add_files -norecurse $audit_bd
open_bd_design $audit_bd
puts "AUDIT_CELLS=[llength [get_bd_cells -quiet]]"
puts "AUDIT_NETS=[llength [get_bd_nets -quiet]]"
puts "AUDIT_INTERFACE_NETS=[llength [get_bd_intf_nets -quiet]]"
puts "AUDIT_PORTS=[llength [get_bd_ports -quiet]]"
puts "AUDIT_INTERFACE_PORTS=[llength [get_bd_intf_ports -quiet]]"
set audit_failed [catch {validate_bd_design} audit_message]
puts "AUDIT_VALIDATION_FAILED=$audit_failed"
puts "AUDIT_VALIDATION_MESSAGE=$audit_message"
close_project
if {$audit_failed} {exit 1}
