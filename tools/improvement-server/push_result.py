#!/usr/bin/env python3
"""対応結果のまとめを iPhone の改善タブ「対応済み」欄へ書き込む。

使い方: python3 push_result.py "要望の要約" "原因と対応内容のまとめ"
端末の Documents/improve_results.json を取得→追記→書き戻す(端末側の削除を尊重)。
"""
import json, subprocess, sys, uuid, time, os

DEVICE = "0FBCC7AE-2007-5EA8-9EDF-869A24A76401"
APPID = "com.okadamasayuki.MemorizeEnglishSentences"
ENV = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
TMP = "/tmp/improve_results_tmp.json"

def dctl(*args):
    return subprocess.run(["xcrun", "devicectl", *args], env=ENV, capture_output=True)

title, summary = sys.argv[1], sys.argv[2]
r = dctl("device", "copy", "from", "--device", DEVICE,
         "--source", "Documents/improve_results.json", "--destination", TMP,
         "--domain-type", "appDataContainer", "--domain-identifier", APPID)
try:
    results = json.load(open(TMP))
except Exception:
    results = []
# 端末(Swift)のJSONDecoderが読める形式: id=UUID文字列, 日付=ISO8601ではなくSwift既定(参照秒)
swift_epoch = time.time() - 978307200.0
results.append({
    "id": str(uuid.uuid4()).upper(),
    "title": title,
    "summary": summary,
    "completedAt": swift_epoch,
})
json.dump(results, open(TMP, "w"), ensure_ascii=False)
r = dctl("device", "copy", "to", "--device", DEVICE,
         "--source", TMP, "--destination", "Documents/improve_results.json",
         "--domain-type", "appDataContainer", "--domain-identifier", APPID)
print("pushed" if r.returncode == 0 else f"FAILED: {r.stderr.decode()[:200]}")
