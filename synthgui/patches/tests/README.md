Reproducers for patches 0005 and 0006: each module is mapped, its netlist's module renamed
`<name>_map`, and the testbench runs RTL and netlist side by side in Verilator.

| Module | Testbench | What it shows | Before the patch |
|---|---|---|---|
| `win.sv` | `tbw.sv` | `v[16*n +: 32] = w`: a part-select write whose offset is not a multiple of its width | 2147 of 20000 random cases differ (the write is dropped for odd `n`) |
| `lram.sv` | `tbl.sv` | an `initial` loop filling a distributed RAM and an array kept as registers | every word of the 64 x 2 array reads 0 at power-up |

    mapper -Wno-fatal --quiet --top-module win --struct-only-report --map-only-output win.json \
        --map-only-verilog win_mapped.v --Mdir obj $SYNTHGUI/xc7/cells_sim.v $SYNTHGUI/xc7/cells_xtra.v win.sv
    sed 's/^module win\b/module win_map/' win_mapped.v > win_map.v
    verilator --binary -Wno-fatal --top-module tb tbw.sv win.sv win_map.v $SYNTHGUI/xc7/cells_sim.v $SYNTHGUI/xc7/cells_xtra.v
