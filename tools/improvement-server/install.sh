#!/bin/zsh
# 改善メモの受け口(improvement_server.py)を、ログイン時に自動で
# 立ち上がるように launchd へ登録する。一度実行すればよい。
#
#   導入:   ./install.sh
#   取り外し: ./install.sh --uninstall
#
# ログは ~/Library/Logs/english-improvements.log に出る。
# improvement_server.py を書き換えたら、もう一度 install.sh を実行すること。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
LABEL="com.okadamasayuki.english-improvements"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/english-improvements.log"
# 本体の写し先。リポジトリはデスクトップの中にあって launchd からは
# 読めない(macOS の保護)ので、保護の外へ写したものを動かす。
RUN_DIR="$HOME/.english-improvements"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "取り外しました: $LABEL"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$RUN_DIR"
cp "$SCRIPT_DIR/improvement_server.py" "$RUN_DIR/improvement_server.py"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/python3</string>
		<string>$RUN_DIR/improvement_server.py</string>
		<string>$REPO_DIR</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "入れました: $LABEL (port 8918, repo=$REPO_DIR)"
echo "ログ: $LOG"
