#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d dist/QuotaBar.app ]]; then
  ./scripts/build-app.sh
fi
if pgrep -x QuotaBar >/dev/null; then
  print "请先从 QuotaBar 菜单退出正在运行的版本，再安装。"
  exit 1
fi
mkdir -p "$HOME/Applications"
/usr/bin/ditto dist/QuotaBar.app "$HOME/Applications/QuotaBar.app"
open "$HOME/Applications/QuotaBar.app" --args "$@"
print "已安装并启动：$HOME/Applications/QuotaBar.app"
