# 2026-11-05T11:51:21.908248600
import vitis

client = vitis.create_client()
client.set_workspace(path="custom_SOC-main")

vitis.dispose()

