#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Turn a single driver source file into kernel/patches/legend-eth.patch, the
# patch that build-kernel.sh applies automatically.
#
#   kernel/make-legend-eth-patch.sh path/to/legend_eth.c [out.patch]
#
# The patch adds
#   drivers/net/ethernet/legend/legend_eth.c   (your file, verbatim)
#   drivers/net/ethernet/legend/Kconfig       (config LEGEND_ETH)
#   drivers/net/ethernet/legend/Makefile
# and the only two edits to existing kernel files:
#   drivers/net/ethernet/Kconfig   + source "drivers/net/ethernet/legend/Kconfig"
#   drivers/net/ethernet/Makefile  + obj-$(CONFIG_LEGEND_ETH) += legend/
# You can equally write the patch by hand; build-kernel.sh only needs it to
# apply with -p1 and to define CONFIG_LEGEND_ETH.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
drv=${1:?usage: $0 legend_eth.c [out.patch]}
out=${2:-$here/patches/legend-eth.patch}
KVER=6.18.64
tarball=$here/../dl/linux-$KVER.tar.xz
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# pristine copies of the two files we touch, straight from the tarball
mkdir -p "$tmp/a" "$tmp/b"
for t in a b; do
    tar -C "$tmp/$t" --strip-components=1 -xf "$tarball" \
        linux-$KVER/drivers/net/ethernet/Kconfig linux-$KVER/drivers/net/ethernet/Makefile
done
e=$tmp/b/drivers/net/ethernet
sed -i 's|^source "drivers/net/ethernet/faraday/Kconfig"$|source "drivers/net/ethernet/legend/Kconfig"\n&|' "$e/Kconfig"
sed -i 's|^obj-\$(CONFIG_NET_VENDOR_FARADAY) += faraday/$|obj-$(CONFIG_LEGEND_ETH) += legend/\n&|' "$e/Makefile"
mkdir "$e/legend"
cp "$drv" "$e/legend/legend_eth.c"
cat > "$e/legend/Kconfig" <<'EOF'
# SPDX-License-Identifier: GPL-2.0-only
config LEGEND_ETH
	tristate "legend64 native descriptor-ring Ethernet MAC (legend,eth)"
	depends on OF && HAS_IOMEM && HAS_DMA
	help
	  Ethernet MAC of the legend64 VC707 SoC.  It DMAs packets directly
	  to and from system RAM (cache coherent, no IOMMU).
EOF
cat > "$e/legend/Makefile" <<'EOF'
# SPDX-License-Identifier: GPL-2.0-only
obj-$(CONFIG_LEGEND_ETH) += legend_eth.o
EOF
mkdir -p "$(dirname "$out")"
(cd "$tmp" && diff -urN a b) > "$out" || [ $? -eq 1 ]
echo "wrote $out ($(grep -c '^+++ ' "$out") files)"
