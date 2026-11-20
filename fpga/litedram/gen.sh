#!/bin/bash
# Regenerate the LiteDRAM core: fpga/litedram/build/gateware/litedram_core.v and the CSR headers.
set -e
cd "$(dirname "$0")"
. ../../tools/litex/venv/bin/activate
litedram_gen vc707.yml --output-dir build --no-compile-software --csr-csv build/csr.csv --csr-json build/csr.json "$@"
