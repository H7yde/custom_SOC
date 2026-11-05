# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\diskio.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\ff.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\ffconf.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\sleep.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilffs.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilffs_config.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilrsa.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xiltimer.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xtimer_config.h"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxilffs.a"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxilrsa.a"
  "D:\\LAB\\custom_SOC-main\\soc_platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxiltimer.a"
  )
endif()
