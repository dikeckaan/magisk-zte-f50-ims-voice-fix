#!/system/bin/sh
ui_print " "
ui_print "  IMS Voice Fix v0.2.0-dev"
ui_print "  ========================"
ui_print " "
ui_print "  Patched com.spreadtrum.ims overlay'i kuruluyor."
ui_print "  Patch içeriği:"
ui_print "    PhoneStateMonitor\$PhoneStateChangedReceiver"
ui_print "    SCREEN_OFF event'inde onScreenStateChanged(0) çağrısı"
ui_print "    3x nop ile devre dışı bırakıldı."
ui_print "  Beklenen sonuç: cellular/VoWiFi çağrıları 20 sn'de düşmeyecek."
ui_print " "

# Verify target device
MODEL=$(getprop ro.product.model 2>/dev/null)
ui_print "  Cihaz modeli: $MODEL"
case "$MODEL" in
    *F50*|*MF93*|*U20*)
        ui_print "  ✓ ZTE F50 ailesi tespit edildi."
        ;;
    *)
        ui_print "  ⚠ Bu modül yalnız ZTE F50 için doğrulandı."
        ui_print "  ⚠ Devam ediyorum ama yanlış cihaza takarsan IMS bozulabilir."
        ;;
esac

# Verify the stock IMS apk exists where we expect
STOCK_IMS=/system_ext/priv-app/ims/ims.apk
if [ ! -f "$STOCK_IMS" ]; then
    abort "  ❌ Stock IMS apk $STOCK_IMS bulunamadı — bu modül F50 için tasarlandı."
fi
ui_print "  Stock IMS bulundu: $(stat -c %s $STOCK_IMS 2>/dev/null) byte"

PATCHED="$MODPATH/system_ext/priv-app/ims/ims.apk"
ui_print "  Patched IMS yüklenecek: $(stat -c %s $PATCHED 2>/dev/null) byte"

# Magisk Magic-Mount can replace /system_ext/priv-app/ims/ims.apk with our
# patched version, but Android caches the *compiled* dex of the apk under
# /system_ext/priv-app/ims/oat/arm64/{ims.odex,ims.vdex}. As long as those
# cached binaries exist, ART will use the stale stock dex and our patch is
# inert. To force a clean recompile from the patched apk we install a
# REPLACE-marker on the oat directory: Magisk Magic-Mount sees `.replace`
# and treats the whole oat dir as ours — which is empty, so ART must fall
# back to recompiling ims.apk on first boot.
mkdir -p "$MODPATH/system_ext/priv-app/ims/oat"
: > "$MODPATH/system_ext/priv-app/ims/oat/.replace"
ui_print "  oat dir mask installed (force on-boot dex recompile)"

set_perm "$MODPATH/system_ext/priv-app/ims/ims.apk"  0  0  0644
set_perm "$MODPATH/system_ext/priv-app/ims/oat/.replace" 0 0 0644
set_perm_recursive "$MODPATH/system_ext/priv-app/ims" 0 0 0755 0644

ui_print " "
ui_print "  [OK] Kuruldu. Reboot et — service.sh boot'ta IMS'i compile-force eder."
ui_print "  Geri al: Magisk → Modules → ims-voice-fix → disable → reboot."
ui_print " "
