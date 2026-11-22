# MeshCore on pyrite (nRF52840, RAK4631 + SX1262): learning pass

Not for upstream. MeshCore `RAK_4631_repeater` (main @ clone time), sim 0.10.x, model `NRF52840QIAA`. Board and SX1262 peer derive from the
Meshtastic run (simantic-dev/meshtastic-firmware `sim-demo`).

## Run (from repo root)
    EXTRA="-DMESH_DEBUG=1 -DMESH_PACKET_LOGGING=1 -UUSE_CC310_HW_CRYPTO" sim/build.sh RAK_4631_repeater merged_sw
    sim run --scenario sim/two.yaml   --usb-cdc-console a.usbd --usb-cdc-console $'b.usbd=advert\r' --ascii --timeout 16
    MESH_LINKS=0-1,1-2 sim run --scenario sim/three.yaml --usb-cdc-console r.usbd --usb-cdc-console c.usbd --usb-cdc-console $'a.usbd=advert\r' --ascii --timeout 22
Single node: `sim NRF52840QIAA run --board sim/rak.board --elf sim/merged_sw.hex --usb-cdc-console usbd --ascii --timeout 12`.
`--on-fault stop` is single-machine only. A scenario takes one `elf:`, hence the merged MBR+S140+app hex.

## Peer changes (sim/sx/sx1262.py, vs the Meshtastic copy)
- Shared air: every Slave registers in a list kept in `builtins` (all machines share one embedded interpreter). At TX start the frame is
  offered to every other node (`_air_start`), which applies the existing RX match (mode, SF, BW, CR, sync, IQ, freq) and time-on-air
  from SF/BW/CR (DS.SX1261-2 6.1.4). Unit gain, fixed RSSI -60 / SNR 10, no collisions or capture: MODELED SIMPLIFICATION.
  Both nodes transmitting at once hear nothing (half duplex), which happens when two identical boots advertise at the same virtual time.
- `MESH_LINKS="0-1,1-2"`: reachability by machine order; unset = all hear all.
- Registers 0x0819-0x081C return per-node PRNG bits (RadioLib randomByte). MeshCore seeds its identity from them, so without this
  every node generated the same keypair. MODELED SIMPLIFICATION (silicon: wideband noise).
- `MESH_AIR_LOG=1` prints TX/RX air events and payload hex to stderr.

## Results
- Rung 1 (single node, 12 s virtual): boots, identity generated and saved to LittleFS, `RX Boosted Gain Mode: Enabled` (SX1262 init ok),
  no fault, no S140 assert (repeater env has no Bluefruit init, so the Meshtastic 7.9 s assert path is not exercised; NVMC question left open).
- Rung 2 (2 nodes, 16 s virtual): b `advert` at 12.215 s -> 857 ms on air (SF8 BW62.5 CR4/5, 127 B) -> a RX 13.078 s, `valid advertisement
  received!`, a floods it on (len 128), b sees its own advert. 639 M guest insns per node, 18.7 s wall, ~39 MIPS/node at quantum 10 us.
- Rung 3 (3 nodes a-r-c, a and c not linked, 22 s virtual): a advert 12.226 s -> r RX 13.089 -> r repeats (len 128) 14.408 s -> c RX 15.271,
  valid advertisement from a via r; c repeats (len 129), r hears it. 1.02 G insns per node, 36.6 s wall. Endpoints are repeaters, not companions
  (a companion needs a host app on USB/BLE).
- Fails with stock flags: `USE_CC310_HW_CRYPTO=1` makes `Identity::verify` call `CRYS_ECEDW_Verify`; it returns 0x00F02320
  (SIGN_VERIFY_FAILED) for a signature that Python Ed25519 verifies as valid, interpreter and JIT alike: "forged signature", advert dropped,
  nothing relayed. pyrite#4054. The software-crypto build above avoids it.
- Two identical boots advertise at the same virtual instant (16 s after boot) and collide; the runs trigger the advert by CLI (`advert\r`) instead.
- Not examined: FICR DEVICEADDR (identity here comes from the radio RNG, not FICR), companion firmware, BLE/S140 under MeshCore.
