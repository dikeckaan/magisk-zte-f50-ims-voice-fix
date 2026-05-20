# ZTE F50 — Real Root Cause of 14-20s Call Drops

After exhaustive AP-side experimentation, the actual root cause was found in
the modem's IMS layer, not in the SCREEN_OFF handler this module patches.

## Diagnostic chain

A failed call's logcat tail reveals:

```
Telephony: onDisconnect: callId=TC@9_1, cause=ERROR_UNSPECIFIED
Telephony: disconnectCause =36
Telecom: TelephonyCause: 36/-1 ImsReasonInfo: {0 : CODE_UNSPECIFIED, 0, 999}
```

* `36` = `android.telephony.DisconnectCause.ERROR_UNSPECIFIED`.
* `999` is the ImsReasonInfo extra-code.

Disassembling `/system_ext/priv-app/ims/ims.apk` (com.spreadtrum.ims):

```
ImsService.smali:78:
    .field public static final IMS_HANDOVER_ACTION_CONFIRMED:I = 0x3e7
```

`0x3e7 = 999`. The extra-code says "IMS layer has confirmed a handover
action" — specifically a VoLTE → fallback handover. Around line 14150
the smali shows the failure path with the literal `"VOLTE pdn failed."`.

## What's actually happening

On the ZTE F50, configured by ZTE as a "data terminal" SKU:

1. An outbound call is placed via Telecom → TelephonyConnectionService.
2. The Spreadtrum IMS layer brings up a VoLTE PDN, establishes an
   ImsCallSession (`state:NEGOTIATING → ESTABLISHED`), call is up.
3. ~14-20 s later the VoLTE PDN drops (short lease — set by the modem
   firmware or by carrier-side ePDG behaviour on this SKU).
4. IMS tries a handover to fallback (CS), fails (no PDN, possibly no
   CS-voice capability either), and confirms HANDOVER_ACTION (999).
5. The session is terminated with `CODE_UNSPECIFIED`.

This explains every prior failed experiment:

* The PhoneStateMonitor SCREEN_OFF patch was real but inert — it never
  fires before the modem-side timer does.
* AT+CLCC keepalive never affected anything — the AT command interface
  doesn't refresh the IMS PDN lease.
* Stock-dialer re-enable, double-INVITE races, InCallService removal —
  none of these change the IMS PDN lease.
* `AT+SPCAPABILITY=45,1,1` (MOS enable) succeeded ("+SPCAPABILITY: 45,0,1")
  but didn't extend the call — the MOS flag controls call-initiation
  capability, not PDN lease.

## What works (verified live but unsustainable)

* `settings put global volte_vt_enabled 0` + `AT+CAVIMS=0` immediately
  detaches IMS. On Vodafone TR this also tore down the cellular data PDP,
  so the device's internet went away (and with it, ADB-over-tunnel access).
  A separate carrier might decouple — to be tried again carefully.

## What needs to be tried next (cannot guess without device)

1. **CarrierConfig override**, NOT a global toggle:
   ```
   carrier_volte_available_bool = false
   carrier_volte_provisioned_bool = false
   carrier_ims_gba_required_bool = false
   ```
   This disables VoLTE *for the carrier* while still letting data attach.
   Implement as a Magisk overlay on `/vendor/etc/CarrierConfig/...xml`.
2. **CSFB fallback path** — find the AT command that toggles VoLTE
   preference without ImsAttach=0. Likely `AT+SPVOLTECTL=0` or similar
   in the SP* family.
3. **Modem PDN lease extension** — look for an NV item in nr_fixnv1.bin
   that controls IMS PDN inactivity timeout. Spreadtrum reference docs
   call it `NV_IMS_INACT_TIMER` or similar.
4. **Compare** `+SPCAPABILITY: 32,0,0` and `+SPCAPABILITY: 1,0,0` values
   against a voice-capable Unisoc phone — these flags may be the real
   gate.

## Why this matters for ims-voice-fix v0.x

The module's hypothesis was wrong. The patched APK is correctly applied
(logcat confirms "Screen is off. (PATCHED - ignoring)" runs), but the
patched handler is downstream of the actual problem. Module is left
under-development pending a real CarrierConfig-or-NV solution.
