# ims-voice-fix — ZTE F50 cellular call drop on screen-off

> ⚠ **UNDER DEVELOPMENT — root cause not yet confirmed.** See [Counterevidence](#counterevidence-why-this-is-still-exploratory).

A Magisk module that overlays a patched `com.spreadtrum.ims` apk over
the stock one, with the goal of stopping cellular / VoWiFi calls from
dropping when the F50 screen turns off.

## What it does

```
/data/adb/modules/ims-voice-fix/
└── system_ext/priv-app/ims/ims.apk      (bind-mounted over stock)
```

The patched apk differs from stock in exactly one method —
`PhoneStateMonitor$PhoneStateChangedReceiver` — where the SCREEN_OFF
branch's `onScreenStateChanged(monitor, 0)` call is replaced with
three `nop` instructions:

```smali
# original
invoke-static {v0, v4}, .../PhoneStateMonitor;->-$$Nest$monScreenStateChanged(.../PhoneStateMonitor;I)V
# patched
nop
nop
nop
```

The classes.dex differs by 92 bytes; no other code change exists. The
APK is debug-signed; Magisk's overlay path means the system partition
is not modified and the change survives reboots until you disable the
module.

## Hypothesis

ZTE F50 is a MiFi / portable-router SKU with a short default screen
timeout. Observed behaviour on one device: cellular calls die at the
exact moment the screen would have locked. The patched handler stops
that.

## Counterevidence (why this is still exploratory)

A second F50 on the same carrier showed a 1+ minute cellular call
continuing across a screen-off event without dropping. So either:

* That device's stock `ims.apk` build is different (different smali,
  no SCREEN_OFF teardown), or
* The drop on the affected device is not actually caused by
  SCREEN_OFF — the timing match with the ~20 s screen timeout was a
  coincidence and we are looking at a different layer (network-side
  BYE, vendor RIL OEM hook, etc.).

## How to test (no module install needed)

```bash
# disable screen-off entirely
adb shell settings put system screen_off_timeout 2147483647

# make a call and time it
# >  if it survives > 20 s on its own  → SCREEN_OFF was the trigger,
#                                          this module is correct
# >  if it still dies at ~20 s         → SCREEN_OFF is not the cause,
#                                          this module is placebo,
#                                          investigation continues
```

## Install (when ready)

```bash
adb push ims-voice-fix-v0.1.0-dev.zip /sdcard/
adb shell su -c "magisk --install-module /sdcard/ims-voice-fix-v0.1.0-dev.zip"
adb reboot
```

## Rollback

```bash
adb shell "echo 1 > /data/adb/modules/ims-voice-fix/disable" && adb reboot
# or just `magisk → modules → ims-voice-fix → disable`
```

## Provenance

The `system_ext/priv-app/ims/ims.apk` shipped here is the previously
debug-signed `ims_signed.apk` produced by the device owner. The
forensics that confirmed the smali diff lives in
`/tmp/f50-forensics/report-voice-drop.md` (local-only).

## Not in scope

* Identity / IMEI / WiFi MAC recovery — separate analysis, lives in
  `/tmp/f50-forensics/report-identity.md`, deliberately not packaged
  here.
* Modem firmware / NV writes — none of the partitions touched.

## Status checklist

- [x] Smali patch identified and isolated
- [x] APK signed and packaged
- [x] Magisk overlay structure produced
- [ ] Cause confirmed via `screen_off_timeout` test
- [ ] Cross-device comparison (the second F50's `ims.apk` byte-diff
      against the one on the affected device)
