# 2026-11-05T12:28:02.470499
import vitis

client = vitis.create_client()
client.set_workspace(path="custom_SOC-main")

platform = client.create_platform_component(name = "soc_platform",hw_design = "$COMPONENT_LOCATION/../SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

comp = client.create_app_component(name="arm_test",platform = "$COMPONENT_LOCATION/../soc_platform/export/soc_platform/soc_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="soc_platform")
status = platform.build()

comp = client.get_component(name="arm_test")
comp.build()

comp = client.get_component(name="arm_test")
status = comp.import_files(from_loc="$COMPONENT_LOCATION/../SOC_HUFLIT_2026_parallel_125MHz", files=["main.c"], dest_dir_in_cmp = "src", is_skip_copy_sources = False)

status = platform.build()

comp = client.get_component(name="arm_test")
comp.build()

vitis.dispose()

