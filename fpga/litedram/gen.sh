#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Regenerate the LiteDRAM core: fpga/litedram/build/gateware/litedram_core.v and the CSR headers.
set -e
cd "$(dirname "$0")"
# The generator and what it is built on are the submodules under third_party/; the Python
# packages those need in turn (pyyaml and so on) come from a virtual environment if there is one.
[ -f ../../tools/litex/venv/bin/activate ] && . ../../tools/litex/venv/bin/activate
tp=$(cd ../../third_party && pwd)
export PYTHONPATH=$tp/migen:$tp/litex:$tp/litedram${PYTHONPATH:+:$PYTHONPATH}
python3 -m litedram.gen vc707.yml --output-dir build --no-compile-software --csr-csv build/csr.csv --csr-json build/csr.json "$@"
