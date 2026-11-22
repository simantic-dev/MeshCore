#!/bin/sh
# Usage: [EXTRA="-D..."] sim/build.sh <pio-env> <out-name>   (run from repo root)
# e.g. EXTRA="-DMESH_DEBUG=1 -DMESH_PACKET_LOGGING=1 -UUSE_CC310_HW_CRYPTO" sim/build.sh RAK_4631_repeater merged_sw
# Writes sim/<out-name>.hex = MBR + S140 6.1.1 (from the PlatformIO Adafruit package, UICR dropped) + the app.
# Not committed: Nordic blobs / build output.
set -e
ENV=${1:-RAK_4631_repeater}; OUT=${2:-merged}
PLATFORMIO_BUILD_FLAGS="$EXTRA" pio run -e $ENV
OC=$(ls ~/.platformio/packages/toolchain-gccarmnoneeabi/bin/arm-none-eabi-objcopy 2>/dev/null || command -v arm-none-eabi-objcopy)
$OC -O ihex .pio/build/$ENV/firmware.elf sim/app.hex
python3 -I - $OUT <<'P'
import glob, os, sys
src = glob.glob(os.path.expanduser("~/.platformio/packages/framework-arduinoadafruitnrf52/bootloader/feather_nrf52840_express/*s140_6.1.1.hex"))[0]
out, skip = [], False
for l in open(src):
    l = l.strip()
    if l[7:9] == "04": skip = l[9:13] == "1000"
    if skip and l[7:9] in ("00", "04"): continue
    if l[7:9] == "01": continue
    out.append(l)
out += open("sim/app.hex").read().split()
open(f"sim/{sys.argv[1]}.hex", "w").write("\n".join(out) + "\n")
P
rm sim/app.hex
