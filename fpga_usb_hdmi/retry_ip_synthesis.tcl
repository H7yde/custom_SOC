# Source this file in the open project's Vivado Tcl Console.
# Preserve completed checkpoints and retry unfinished USB/HDMI IPs sequentially.
if {![llength [current_project -quiet]]} {
    error "Open SOC_HUFLIT_2026.xpr before sourcing this file."
}
set retry_ip_runs [get_runs -quiet usb_hdmi_system_*_synth_1]
if {![llength $retry_ip_runs]} {
    error "No USB/HDMI IP synthesis runs found. Generate Output Products first."
}
foreach retry_ip_run $retry_ip_runs {
    set retry_ip_status [get_property STATUS $retry_ip_run]
    if {[regexp -nocase {running|queued|launching} $retry_ip_status]} {
        error "Run $retry_ip_run is active ($retry_ip_status). Wait or cancel it before retrying."
    }
}
set_param general.maxThreads 2
set retry_ip_backup [file join [get_property DIRECTORY [current_project]] ip_retry_logs [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $retry_ip_backup
foreach retry_ip_run $retry_ip_runs {
    set retry_ip_status [get_property STATUS $retry_ip_run]
    # A run may finish successfully after reporting an error during startup.
    # Retry it too, so its message database and log no longer retain that error.
    set retry_ip_startup_error 0
    set retry_ip_run_log [file join [get_property DIRECTORY $retry_ip_run] runme.log]
    if {[file exists $retry_ip_run_log]} {
        set retry_ip_log_handle [open $retry_ip_run_log r]
        try {
            set retry_ip_log_text [read $retry_ip_log_handle]
        } finally {
            close $retry_ip_log_handle
        }
        set retry_ip_startup_error [regexp {\[Common 17-(354|1219|1257)\]} $retry_ip_log_text]
    }
    if {([string match {*Complete*} $retry_ip_status] ||
         $retry_ip_status eq {Using cached IP results}) &&
        ![get_property NEEDS_REFRESH $retry_ip_run] && !$retry_ip_startup_error} {
        puts "IP_RETRY_KEEP $retry_ip_run: $retry_ip_status"
        continue
    }
    set retry_ip_logdir [file join $retry_ip_backup $retry_ip_run]
    file mkdir $retry_ip_logdir
    foreach retry_ip_log [glob -nocomplain -directory [get_property DIRECTORY $retry_ip_run] *.log *.vds] {
        file copy -force $retry_ip_log $retry_ip_logdir
    }
    puts "IP_RETRY_START $retry_ip_run: $retry_ip_status"
    reset_run $retry_ip_run
    launch_runs $retry_ip_run -jobs 1
    wait_on_run $retry_ip_run
    set retry_ip_status [get_property STATUS $retry_ip_run]
    if {![string match {*Complete*} $retry_ip_status] &&
        $retry_ip_status ne {Using cached IP results}} {
        error "IP retry failed: $retry_ip_run ($retry_ip_status). Previous logs: $retry_ip_backup"
    }
    puts "IP_RETRY_PASS $retry_ip_run"
}
puts "USB_HDMI_IP_SYNTHESIS_PASS"
puts "Previous logs: $retry_ip_backup"
