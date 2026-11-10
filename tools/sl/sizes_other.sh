#!/bin/zsh
# Widget sizes on other simulators via gallery previews (German UI required by the gallery automation).
cd "$(dirname "$0")"
APP=~/Library/Developer/Xcode/DerivedData/AWL/Build/Products/Debug-iphonesimulator/AgentWidgetLab.app
DEVICES=("iPhone 16e" "iPhone 17 Pro Max"); [[ -n "$SL_DEVICE" ]] && DEVICES=("$SL_DEVICE")
for NAME in "${DEVICES[@]}"; do
  UDID=$(xcrun simctl list devices available | grep "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  echo "== $NAME $UDID"
  xcrun simctl boot "$UDID" 2>/dev/null
  xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array de-DE
  xcrun simctl spawn "$UDID" defaults write -g AppleLocale de_DE
  xcrun simctl shutdown "$UDID"; xcrun simctl boot "$UDID"; sleep 25
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$(defaults read "$APP/Info" CFBundleIdentifier)" >/dev/null; sleep 4
  AWL_SIM="$UDID" SL_SIM_NAME="$NAME" python3 - "$NAME" <<'PY'
import sys, json, slcore as s
name = sys.argv[1]
since = s.lab.now_ms()
sys.path.insert(0, "../rl")
out, ok = s.uitest("RenderLabTests/testGalleryDump", RL_SWIPES=20)
sizes = {}
for e in s.lab.events(since):
    if e["e"] == "sl_timeline":
        d = dict(x.split("=", 1) for x in e["d"].split() if "=" in x); sizes[d["family"]] = d["size"]
print(name, ok, sizes)
s.save("B1-sizes-" + name.replace(" ", "-"), {"device": name, "uitest_ok": ok, "sizes_pt": sizes})
PY
  xcrun simctl shutdown "$UDID"
done
