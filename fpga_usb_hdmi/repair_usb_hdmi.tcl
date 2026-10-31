# Run in the open PYNQ-Z2 project. Repairs the existing USB/HDMI BD in place.
# It does not add the ARM/PicoRV32 CNN bridge or change the synthesis top.
# Back up the BD/IP directory first. The batch runner does this before execution.
namespace eval hdmi_repair {
    variable root [file dirname [file normalize [info script]]]
    proc object {path} {
        set found [get_bd_pins -quiet $path]
        if {![llength $found]} {set found [get_bd_ports -quiet $path]}
        if {[llength $found] != 1} {error "Expected one pin/port: $path"}
        return $found
    }
    proc wire {source destinations} {
        set src [object $source]
        foreach destination $destinations {
            set dst [object $destination]
            set src_net [get_bd_nets -quiet -of_objects $src]
            set dst_net [get_bd_nets -quiet -of_objects $dst]
            if {[llength $src_net] && $src_net eq $dst_net} {continue}
            if {[llength $dst_net]} {disconnect_bd_net $dst_net $dst}
            connect_bd_net $src $dst
        }
    }
    proc interface {source destination} {
        set src [get_bd_intf_pins -quiet $source]
        if {![llength $src]} {set src [get_bd_intf_ports -quiet $source]}
        set dst [get_bd_intf_pins -quiet $destination]
        if {![llength $dst]} {set dst [get_bd_intf_ports -quiet $destination]}
        if {[llength $src] != 1 || [llength $dst] != 1} {error "Missing interface: $source -> $destination"}
        set src_net [get_bd_intf_nets -quiet -of_objects $src]
        set dst_net [get_bd_intf_nets -quiet -of_objects $dst]
        if {[llength $src_net] && $src_net eq $dst_net} {return}
        if {[llength $dst_net]} {disconnect_bd_intf_net $dst_net $dst}
        connect_bd_intf_net $src $dst
    }
    proc optional_wire {source destination} {
        if {[llength [get_bd_pins -quiet $destination]]} {wire $source [list $destination]}
    }
    proc output {name pin {width 1}} {
        if {![llength [get_bd_ports -quiet $name]]} {
            if {$width == 1} {create_bd_port -dir O $name} else {
                create_bd_port -dir O -from [expr {$width - 1}] -to 0 $name
            }
        }
        wire $pin [list $name]
    }
    proc board_ps {ps} {
        variable root
        # Read parameter values only; never execute the old reference design Tcl.
        set handle [open [file join $root reference pynqz2_v2_7_0.tcl] r]
        set reference [read $handle]
        close $handle
        set settings [list]
        foreach line [split $reference "\n"] {
            if {![regexp {^\s*CONFIG\.(PCW_[A-Z0-9_]+)\s+\{([^\}]*)\}} $line -> name value]} {continue}
            if {[string match "PCW_UIPARAM_DDR_*" $name] ||
                $name in {PCW_CRYSTAL_PERIPHERAL_FREQMHZ PCW_DDR_RAM_HIGHADDR PCW_APU_PERIPHERAL_FREQMHZ PCW_PRESET_BANK0_VOLTAGE PCW_PRESET_BANK1_VOLTAGE PCW_SDIO_PERIPHERAL_FREQMHZ} ||
                [string match "PCW_SD0_*" $name] || [string match "PCW_UART0_*" $name] ||
                [string match "PCW_ENET0_*" $name] || [string match "PCW_QSPI_*" $name] ||
                [regexp {^PCW_MIO_[0-9]+_(IOTYPE|PULLUP|SLEW)$} $name]} {
                if {[lsearch -exact [list_property $ps] CONFIG.$name] >= 0} {
                    lappend settings CONFIG.$name $value
                }
            }
        }
        if {[llength $settings] < 40} {error "Incomplete PYNQ-Z2 reference parameters"}
        lappend settings CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_USE_S_AXI_GP0 0 \
            CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64 CONFIG.PCW_EN_CLK0_PORT 1 \
            CONFIG.PCW_EN_RST0_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 \
            CONFIG.PCW_GPIO_MIO_GPIO_ENABLE 1 CONFIG.PCW_USB0_PERIPHERAL_ENABLE 1 \
            CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} CONFIG.PCW_USB0_RESET_ENABLE 1 \
            CONFIG.PCW_USB0_RESET_IO {MIO 46} CONFIG.PCW_USB_RESET_POLARITY {Active Low}
        # Only byte lanes 0 and 1 exist on the 16-bit DDR interface. The older
        # reference retains negative skews for unused lanes 2/3; clear them.
        lappend settings CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 0 \
            CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 0
        set_property -dict $settings $ps
        if {[get_property CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH $ps] ne "16 Bit"} {
            error "PYNQ-Z2 DDR must use the reference 16-bit bus"
        }
    }
    proc run {} {
        variable root
        if {[llength [get_projects -quiet]] != 1} {error "Open the SoC project first"}
        if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "PYNQ-Z2 part required"}
        set bd [get_files -quiet */usb_hdmi_system.bd]
        if {[llength $bd] != 1} {error "Expected exactly one usb_hdmi_system.bd"}
        open_bd_design $bd
        board_ps [get_bd_cells processing_system7_0]
        set control_masters 3
        if {[llength [get_bd_cells -quiet arm_cnn_cdc]]} {set control_masters 4}
        foreach {name masters} [list control_bus $control_masters memory_bus 1] {
            set cell [get_bd_cells -quiet $name]
            if {[llength $cell] && [get_property VLNV $cell] ne "xilinx.com:ip:axi_interconnect:2.1"} {
                delete_bd_objs $cell
            }
            if {![llength [get_bd_cells -quiet $name]]} {
                create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 $name
            }
            set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI $masters] [get_bd_cells $name]
        }
        set_property -dict [list CONFIG.PRIMITIVE MMCM CONFIG.PRIM_IN_FREQ 100 \
            CONFIG.PRIM_SOURCE No_buffer CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 25.2 \
            CONFIG.CLKOUT2_USED true CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 126 \
            CONFIG.CLKOUT1_REQUESTED_PHASE 0 CONFIG.CLKOUT2_REQUESTED_PHASE 0 \
            CONFIG.USE_RESET true CONFIG.RESET_TYPE ACTIVE_LOW CONFIG.USE_LOCKED true \
            CONFIG.JITTER_OPTIONS PS CONFIG.CLKIN1_JITTER_PS 100] [get_bd_cells clk_wiz_0]
        foreach reset {reset_axi reset_pixel} {
            # External polarity is a BD-propagated read-only parameter. Wiring
            # PS FCLK_RESET0_N supplies ACTIVE_LOW metadata automatically.
            set_property CONFIG.C_AUX_RESET_HIGH 1 [get_bd_cells $reset]
        }
        set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] [get_bd_cells xlconstant_0]
        set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] [get_bd_cells xlconstant_1]
        foreach inverter {invert_hsync invert_vsync} {
            set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION not] [get_bd_cells $inverter]
        }
        set_property -dict [list CONFIG.kGenerateSerialClk false CONFIG.kRstActiveHigh false] [get_bd_cells rgb2dvi_0]
        set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_INPUTS 1 CONFIG.C_IS_DUAL 0 CONFIG.C_INTERRUPT_PRESENT 0] [get_bd_cells hdmi_hpd]
        set_property -dict [list CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 0 \
            CONFIG.c_m_axi_mm2s_data_width 64 CONFIG.c_m_axis_mm2s_tdata_width 24 \
            CONFIG.c_addr_width 32 CONFIG.c_num_fstores 3 CONFIG.c_use_mm2s_fsync 0 \
            CONFIG.c_mm2s_genlock_mode 0 CONFIG.c_mm2s_linebuffer_depth 1024] [get_bd_cells display_vdma]
        set_property -dict [list CONFIG.C_HAS_ASYNC_CLK 1 CONFIG.C_PIXELS_PER_CLOCK 1 \
            CONFIG.C_S_AXIS_VIDEO_FORMAT 2 CONFIG.C_S_AXIS_VIDEO_DATA_WIDTH 8 \
            CONFIG.C_NATIVE_COMPONENT_WIDTH 8 CONFIG.C_VTG_MASTER_SLAVE 0] [get_bd_cells video_out]
        set_property -dict [list CONFIG.VIDEO_MODE 480p CONFIG.enable_detection false \
            CONFIG.enable_generation true CONFIG.HAS_AXI4_LITE true \
            CONFIG.GEN_HSYNC_POLARITY High CONFIG.GEN_VSYNC_POLARITY High] [get_bd_cells video_timing1]

        interface processing_system7_0/M_AXI_GP0 control_bus/S00_AXI
        interface control_bus/M00_AXI display_vdma/S_AXI_LITE
        interface control_bus/M01_AXI video_timing1/ctrl
        interface control_bus/M02_AXI hdmi_hpd/S_AXI
        interface display_vdma/M_AXI_MM2S memory_bus/S00_AXI
        interface memory_bus/M00_AXI processing_system7_0/S_AXI_HP0
        interface display_vdma/M_AXIS_MM2S video_out/video_in
        interface video_timing1/vtiming_out video_out/vtiming_in
        wire processing_system7_0/FCLK_CLK0 {
            processing_system7_0/M_AXI_GP0_ACLK processing_system7_0/S_AXI_HP0_ACLK
            control_bus/ACLK control_bus/S00_ACLK control_bus/M00_ACLK control_bus/M01_ACLK control_bus/M02_ACLK
            memory_bus/ACLK memory_bus/S00_ACLK memory_bus/M00_ACLK
            display_vdma/s_axi_lite_aclk display_vdma/m_axi_mm2s_aclk display_vdma/m_axis_mm2s_aclk
            video_out/aclk video_timing1/s_axi_aclk hdmi_hpd/s_axi_aclk
            clk_wiz_0/clk_in1 reset_axi/slowest_sync_clk
        }
        wire processing_system7_0/FCLK_RESET0_N {clk_wiz_0/resetn reset_axi/ext_reset_in reset_pixel/ext_reset_in}
        wire clk_wiz_0/clk_out1 {video_timing1/clk video_out/vid_io_out_clk rgb2dvi_0/PixelClk reset_pixel/slowest_sync_clk}
        wire clk_wiz_0/clk_out2 {rgb2dvi_0/SerialClk}
        wire clk_wiz_0/locked {reset_axi/dcm_locked reset_pixel/dcm_locked}
        wire xlconstant_0/dout {reset_axi/aux_reset_in reset_axi/mb_debug_sys_rst reset_pixel/aux_reset_in reset_pixel/mb_debug_sys_rst}
        wire reset_axi/interconnect_aresetn {
            control_bus/ARESETN control_bus/S00_ARESETN control_bus/M00_ARESETN control_bus/M01_ARESETN control_bus/M02_ARESETN
            memory_bus/ARESETN memory_bus/S00_ARESETN memory_bus/M00_ARESETN
        }
        wire reset_axi/peripheral_aresetn {display_vdma/axi_resetn video_out/aresetn video_timing1/s_axi_aresetn hdmi_hpd/s_axi_aresetn}
        wire reset_pixel/peripheral_aresetn {video_timing1/resetn rgb2dvi_0/aRst_n}
        wire reset_pixel/peripheral_reset {video_out/vid_io_out_reset}
        foreach enable {video_out/aclken video_out/vid_io_out_ce video_timing1/clken video_timing1/s_axi_aclken} {
            optional_wire xlconstant_1/dout $enable
        }
        foreach zero {video_out/fid video_timing1/fsync_in} {optional_wire xlconstant_0/dout $zero}
        wire video_out/vtg_ce {video_timing1/gen_clken}
        wire video_out/vid_data {rgb2dvi_0/vid_pData}
        wire video_out/vid_active_video {rgb2dvi_0/vid_pVDE}
        wire video_out/vid_hsync {invert_hsync/Op1}
        wire video_out/vid_vsync {invert_vsync/Op1}
        wire invert_hsync/Res {rgb2dvi_0/vid_pHSync}
        wire invert_vsync/Res {rgb2dvi_0/vid_pVSync}

        if {![llength [get_bd_intf_ports -quiet DDR]]} {
            create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
        }
        if {![llength [get_bd_intf_ports -quiet FIXED_IO]]} {
            create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO
        }
        interface processing_system7_0/DDR DDR
        interface processing_system7_0/FIXED_IO FIXED_IO
        output hdmi_tx_clk_p rgb2dvi_0/TMDS_Clk_p
        output hdmi_tx_clk_n rgb2dvi_0/TMDS_Clk_n
        foreach clock_port {hdmi_tx_clk_p hdmi_tx_clk_n} {
            set_property CONFIG.FREQ_HZ 25200000 [get_bd_ports $clock_port]
        }
        output hdmi_tx_d_p rgb2dvi_0/TMDS_Data_p 3
        output hdmi_tx_d_n rgb2dvi_0/TMDS_Data_n 3
        if {![llength [get_bd_ports -quiet hdmi_tx_hpdn]]} {create_bd_port -dir I hdmi_tx_hpdn}
        wire hdmi_tx_hpdn {hdmi_hpd/gpio_io_i}
        assign_bd_address
        validate_bd_design
        foreach reset {reset_axi reset_pixel} {
            if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells $reset]] != 0} {
                error "$reset did not inherit active-low PS reset polarity"
            }
        }
        save_bd_design
        puts "USB_HDMI_REPAIR_VALIDATE_PASS"
        puts "NETS=[llength [get_bd_nets -quiet]] INTERFACE_NETS=[llength [get_bd_intf_nets -quiet]]"
        puts "ADDR_SEGS=[get_bd_addr_segs -quiet -hierarchical]"
    }
}
hdmi_repair::run
