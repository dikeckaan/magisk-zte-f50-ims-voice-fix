# Changelog

## v0.1.0-dev — 2026-05-20 (UNDER DEVELOPMENT)

- First exploratory release. **Root cause NOT yet confirmed**.

### What this is

A Magisk module that bind-mounts a patched `com.spreadtrum.ims`
(`/system_ext/priv-app/ims/ims.apk`) over the stock IMS apk. The patch
replaces this call in `PhoneStateMonitor$PhoneStateChangedReceiver`:

```smali
# original
invoke-static {v0, v4}, PhoneStateMonitor.onScreenStateChanged(monitor, 0)V

# patched
nop
nop
nop
```

### Hypothesis (still being validated)

ZTE F50 is a MiFi / portable-router SKU with a short default screen
timeout (~20 s). When the screen goes off during a cellular/VoWiFi
call, the `Intent.ACTION_SCREEN_OFF` reaches `PhoneStateMonitor`, which
calls `onScreenStateChanged(0)`, which ends up tearing down the active
call session. Patching out that one invocation should let calls survive
screen-off. The previous owner of this device shipped exactly this
patch and reported it working.

### Counterevidence (why this module is still "under development")

A different ZTE F50 on the same carrier (Vodafone TR) was observed to
**not** drop the call even after the screen went off — the call lasted
1+ minute and was manually ended. This contradicts the hypothesis
above, suggesting one of:

* The other device has a different `ims.apk` build that doesn't fire
  the same handler.
* Screen-off isn't actually the root cause on the affected device;
  the apparent correlation with the ~20 s screen timeout was
  coincidence and the real trigger is elsewhere (network-side BYE,
  vendor RIL OEM hook, an entirely different IMS code path).

### How to validate before depending on this module

Run **without** this module installed:

```
adb shell settings put system screen_off_timeout 2147483647
# make a call → measure how long it lasts
```

* Call > 20 s without dropping → screen-off WAS the cause, this module
  is the right fix.
* Call still drops at 20 s → screen-off is NOT the cause, this module
  is placebo and we need to keep investigating (vendor RIL, IMS
  network BYE, modem-side disconnect timer).

### What's bundled

`system_ext/priv-app/ims/ims.apk` — the patched + debug-signed APK
produced previously by the device owner. The Magisk overlay path is
chosen so the system partition is never modified, and disabling the
module restores the stock IMS apk on next boot.
