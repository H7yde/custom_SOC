set p [lindex [glob [file join [file dirname [info script]] .. .. SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]] 0]
open_project $p
open_bd_design [get_files */usb_hdmi_system.bd]
foreach name {reset_cnn_bridge/peripheral_aresetn cnn_axi_aresetn} {
    set pins [get_bd_pins -quiet $name]
    set ports [get_bd_ports -quiet $name]
    puts "PROBE $name pins=<$pins> ports=<$ports>"
    foreach obj [concat $pins $ports] {
        puts "OBJ=$obj class=[get_property CLASS $obj] nets=<[get_bd_nets -quiet -of_objects $obj]>"
    }
}
puts "NET_PINS=[get_bd_pins -of_objects [get_bd_nets reset_cnn_bridge_peripheral_aresetn]]"
puts "NET_PORTS=[get_bd_ports -of_objects [get_bd_nets reset_cnn_bridge_peripheral_aresetn]]"
close_project
exit
