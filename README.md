# ZiproBar

macOS menu bar app for controlling a Zipro treadmill over Bluetooth LE: live speed and state, a speed slider, Start/Stop.

## Build

Requires macOS 14+ and Xcode / Swift 6.

```sh
swift test                      # protocol tests
./scripts/make-app.sh           # build/ZiproBar.app (ad-hoc signed)
./scripts/make-app.sh --install # also copy to ~/Applications and launch
```

On first launch macOS asks for Bluetooth permission. BLE traffic is logged:

```sh
log stream --level debug --predicate 'subsystem == "com.kuba.ziprobar"'
```

## Protocol

The treadmill advertises as `RZ_TreadMil` (protocol originally from [qdomyos-zwift](https://github.com/cagnulein/qdomyos-zwift)'s `ziprotreadmill` driver, verified and extended on real hardware).

- Service `FFF0`, write `FFF2` (**write-with-response only** — macOS silently drops write-without-response), notify `FFF1`.
- Host → treadmill: `FB len payload… sum FC`; treadmill → host: `FD len payload… sum FE`.
  `len` counts itself, payload and checksum; `sum = (len + Σpayload) & 0xFF`.

| Command | Payload |
|---|---|
| Start | `A2 01 01` (5 s countdown, then 1.0 km/h) |
| Stop | `A2 04 01` |
| Set speed | `A1 02 01 <km/h×10> <incline>` (1.0–8.0 km/h) |

Status (`A1`): 18-byte frame while active — byte 3 state, 4 target speed ×10, 5 speed ×10, 6 incline, 10 elapsed s (countdown while starting), 15 heart rate. Short beacons when idle: `fd 05 a1 00 00 a6 fe` (idle), `fd 04 a1 08 ad fe` (sleeping).

States: `00` idle, `01` countdown, `02` running, `04` stopping, `05` stopped, `08` sleeping (ignores start; wake with the remote). Incline commands have no effect on the tested model.
