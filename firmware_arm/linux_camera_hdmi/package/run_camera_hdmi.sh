#!/usr/bin/env bash
# Run with: sudo bash run_camera_hdmi.sh --bars --frames 180
set -e
if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo bash run_camera_hdmi.sh [arguments]" >&2
    exit 1
fi
if [ -f /etc/profile.d/pynq_venv.sh ]; then
    source /etc/profile.d/pynq_venv.sh
fi
if [ -f /etc/profile.d/xrt_setup.sh ]; then
    source /etc/profile.d/xrt_setup.sh
elif [ -f /opt/xilinx/xrt/setup.sh ]; then
    source /opt/xilinx/xrt/setup.sh
fi
camera_python=$(command -v python3)
if [ -x /usr/local/share/pynq-venv/bin/python ]; then
    camera_python=/usr/local/share/pynq-venv/bin/python
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
"$camera_python" -c 'from pynq import Device; print("PYNQ devices:", Device.devices); assert Device.devices, "No FPGA device found: check XRT environment/kernel image"'
exec "$camera_python" camera_hdmi.py "$@"
