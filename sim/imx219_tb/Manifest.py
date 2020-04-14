action = "simulation"
sim_tool = "modelsim"
sim_top = "imx219_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c imx219_tb"

modules = {
  "local" : [ "../../test/" ],
}
