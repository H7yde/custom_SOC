puts "STARTUP_PROBE_BEGIN"
foreach name {APPDATA LOCALAPPDATA TEMP TMP HOMEDRIVE HOMEPATH USERPROFILE XILINX_TCLAPP_REPO} {
    if {[info exists ::env($name)]} {puts "$name=$::env($name)"}
}
create_project -in_memory -part xc7z020clg400-1
puts "STARTUP_PROBE_PASS"
close_project
exit
