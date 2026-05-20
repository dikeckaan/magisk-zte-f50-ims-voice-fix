#!/system/bin/sh
# ims-voice-fix — boot-time recompile guard.
#
# customize.sh dropped a REPLACE-marker on the stock oat dir so Magisk
# Magic-Mount masks the stale compiled dex. Even with that mask in place,
# `cmd package compile` is the explicit way to make ART re-emit a fresh
# odex/vdex from the (now patched) ims.apk. Without an explicit recompile,
# ART may still find a *.dm or *.prof and skip optimisation entirely,
# leaving the patched apk in interpreted/JIT mode — slow at best and
# subject to whatever ART decides to cache next.
#
# We compile to the same `speed` level the OEM build used, blocking until
# the binary lands so the very first IMS process post-boot picks it up.
#
# Idempotent: re-running this on subsequent boots is harmless. The marker
# at /data/ims-voice-fix/recompiled records when we last did it; we skip
# the recompile if the apk md5 matches and a recent marker exists.

MARK_DIR=/data/ims-voice-fix
MARK_FILE="$MARK_DIR/recompiled"
STOCK=/system_ext/priv-app/ims/ims.apk
PATCHED=/data/adb/modules/ims-voice-fix/system_ext/priv-app/ims/ims.apk

mkdir -p "$MARK_DIR"
chmod 755 "$MARK_DIR"

# Wait for ART/PackageManager to be alive
i=0
while [ "$i" -lt 30 ]; do
    pm path com.spreadtrum.ims >/dev/null 2>&1 && break
    sleep 2
    i=$((i + 1))
done

# Verify Magisk's overlay is in effect — only then does compile make sense.
cur_md5=$(md5sum "$STOCK" 2>/dev/null | awk '{print $1}')
patched_md5=$(md5sum "$PATCHED" 2>/dev/null | awk '{print $1}')
if [ -z "$cur_md5" ] || [ -z "$patched_md5" ] || [ "$cur_md5" != "$patched_md5" ]; then
    echo "ims-voice-fix: overlay mismatch (stock=$cur_md5, patched=$patched_md5); skipping recompile" \
        > "$MARK_DIR/last_run.log"
    exit 0
fi

# Already compiled for this apk content?
if [ -f "$MARK_FILE" ]; then
    last_md5=$(cat "$MARK_FILE" 2>/dev/null)
    if [ "$last_md5" = "$patched_md5" ]; then
        echo "ims-voice-fix: already compiled for $patched_md5; nothing to do" \
            > "$MARK_DIR/last_run.log"
        exit 0
    fi
fi

# Force a fresh compile. `-m everything` selects the full optimisation
# profile; `-f` discards any existing cache; the call blocks until the
# new odex/vdex is in place.
cmd package compile -m everything -f com.spreadtrum.ims \
    > "$MARK_DIR/last_run.log" 2>&1

# Bounce the running IMS service so the next call picks up the freshly
# compiled patched dex. com.spreadtrum.ims auto-restarts as a persistent
# system_server-managed service.
am stopservice com.spreadtrum.ims/.ImsService 2>/dev/null
PID=$(pgrep -f com.spreadtrum.ims | head -1)
[ -n "$PID" ] && kill "$PID" 2>/dev/null

echo "$patched_md5" > "$MARK_FILE"
