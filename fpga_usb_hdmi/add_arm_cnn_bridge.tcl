# Add an AXI4-Lite ARM aperture at 0x40004000. Call in the open project.
if {![llength [current_project -quiet]]} {error "Open the SoC project first"}
set bridge_bd [get_files -quiet */usb_hdmi_system.bd]
if {[llength $bridge_bd] != 1} {error "Expected usb_hdmi_system.bd"}
open_bd_design $bridge_bd
set_property CONFIG.NUM_MI 4 [get_bd_cells control_bus]
if {![llength [get_bd_cells -quiet arm_cnn_cdc]]} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 arm_cnn_cdc
}
set_property -dict [list CONFIG.PROTOCOL AXI4LITE CONFIG.DATA_WIDTH 32 CONFIG.ADDR_WIDTH 32 CONFIG.ACLK_ASYNC 1 CONFIG.SYNCHRONIZATION_STAGES 3] [get_bd_cells arm_cnn_cdc]
foreach {name type} {cnn_axi_clk clk cnn_core_resetn rst} {
    if {![llength [get_bd_ports -quiet $name]]} {create_bd_port -dir I -type $type $name}
}
set_property -dict [list CONFIG.FREQ_HZ 125000000 CONFIG.ASSOCIATED_BUSIF ARM_CNN CONFIG.ASSOCIATED_RESET cnn_axi_aresetn] [get_bd_ports cnn_axi_clk]
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports cnn_core_resetn]
if {![llength [get_bd_ports -quiet cnn_axi_aresetn]]} {
    create_bd_port -dir O -type rst cnn_axi_aresetn
}
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports cnn_axi_aresetn]
if {![llength [get_bd_intf_ports -quiet ARM_CNN]]} {
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 ARM_CNN
}
# Interface FREQ_HZ is propagated/read-only; cnn_axi_clk supplies 125 MHz.
set_property -dict [list CONFIG.PROTOCOL AXI4LITE CONFIG.ADDR_WIDTH 32 CONFIG.DATA_WIDTH 32 CONFIG.HAS_BRESP 1 CONFIG.HAS_RRESP 1 CONFIG.HAS_WSTRB 1] [get_bd_intf_ports ARM_CNN]
namespace eval arm_cnn_setup {
    proc pin {name} {
        # Vivado may also return a proxy bd_pin for a top-level port. Prefer
        # the actual bd_port: only it has the existing external net attached.
        set p [get_bd_ports -quiet $name]
        if {![llength $p]} {set p [get_bd_pins -quiet $name]}
        if {[llength $p] != 1} {error "Missing $name"}
        return $p
    }
    proc wire {source destination} {
        set a [pin $source]; set b [pin $destination]
        set an [get_bd_nets -quiet -of_objects $a]
        set bn [get_bd_nets -quiet -of_objects $b]
        if {[llength $an] && [llength $bn] &&
            [string trimleft [get_property NAME [lindex $an 0]] /] eq
            [string trimleft [get_property NAME [lindex $bn 0]] /]} {return}
        if {[llength $bn]} {disconnect_bd_net $bn $b}
        connect_bd_net $a $b
    }
    proc bus {source destination} {
        set a [get_bd_intf_pins -quiet $source]
        set b [get_bd_intf_ports -quiet $destination]
        if {![llength $b]} {set b [get_bd_intf_pins $destination]}
        set an [get_bd_intf_nets -quiet -of_objects $a]
        set bn [get_bd_intf_nets -quiet -of_objects $b]
        if {[llength $an] && [llength $bn] &&
            [string trimleft [get_property NAME [lindex $an 0]] /] eq
            [string trimleft [get_property NAME [lindex $bn 0]] /]} {return}
        if {[llength $bn]} {disconnect_bd_intf_net $bn $b}
        connect_bd_intf_net $a $b
    }
}
foreach {reset clock} {reset_arm_cnn processing_system7_0/FCLK_CLK0 reset_cnn_bridge cnn_axi_clk} {
    if {![llength [get_bd_cells -quiet $reset]]} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $reset
    }
    set_property CONFIG.C_AUX_RESET_HIGH 0 [get_bd_cells $reset]
    arm_cnn_setup::wire $clock $reset/slowest_sync_clk
    arm_cnn_setup::wire cnn_core_resetn $reset/ext_reset_in
    arm_cnn_setup::wire reset_axi/peripheral_aresetn $reset/aux_reset_in
    arm_cnn_setup::wire xlconstant_1/dout $reset/dcm_locked
    arm_cnn_setup::wire xlconstant_0/dout $reset/mb_debug_sys_rst
}
arm_cnn_setup::wire processing_system7_0/FCLK_CLK0 control_bus/M03_ACLK
arm_cnn_setup::wire reset_axi/interconnect_aresetn control_bus/M03_ARESETN
arm_cnn_setup::wire processing_system7_0/FCLK_CLK0 arm_cnn_cdc/s_axi_aclk
arm_cnn_setup::wire cnn_axi_clk arm_cnn_cdc/m_axi_aclk
arm_cnn_setup::wire reset_arm_cnn/peripheral_aresetn arm_cnn_cdc/s_axi_aresetn
arm_cnn_setup::wire reset_cnn_bridge/peripheral_aresetn arm_cnn_cdc/m_axi_aresetn
arm_cnn_setup::wire reset_cnn_bridge/peripheral_aresetn cnn_axi_aresetn
arm_cnn_setup::bus control_bus/M03_AXI arm_cnn_cdc/S_AXI
arm_cnn_setup::bus arm_cnn_cdc/M_AXI ARM_CNN
set bridge_seg [get_bd_addr_segs -quiet ARM_CNN/Reg]
if {[llength $bridge_seg] != 1} {error "Expected external memory segment ARM_CNN/Reg"}
assign_bd_address -offset 0x40004000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] $bridge_seg -force
validate_bd_design
foreach reset {reset_arm_cnn reset_cnn_bridge} {
    if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells $reset]] != 0} {error "Wrong reset polarity: $reset"}
}
save_bd_design
set bridge_rtl [file join [get_property DIRECTORY [current_project]] [get_property NAME [current_project]].srcs sources_1 new cnn_axi_bridge.v]
if {![llength [get_files -quiet $bridge_rtl]]} {add_files -norecurse $bridge_rtl}
generate_target all $bridge_bd
update_compile_order -fileset sources_1
puts "ARM_CNN_BD_BRIDGE_PASS"
