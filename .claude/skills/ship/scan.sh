#!/bin/sh
# 送出前的掃描：私人字詞、Team ID、iPhone 裝置代號、本機路徑。
#
# 用法（在 repo 根目錄）：
#   sh .claude/skills/ship/scan.sh --staged        掃暫存內容（commit 前）
#   sh .claude/skills/ship/scan.sh --file <檔案>   掃一個檔案（PR 內文）
#   sh .claude/skills/ship/scan.sh --unpushed      掃還沒推上去的 commit 內容與訊息（push 前）
#
# 沒命中回傳 0；有命中印出位置並回傳 1；找不到私人字詞清單回傳 2（清單在私有素材 repo，不進公開 repo）。

set -u
root=$(git rev-parse --show-toplevel) || exit 2
words="$root/penguin-family-assets/blocked-words.txt"
if [ ! -f "$words" ]; then
  echo "找不到私人字詞清單：penguin-family-assets/blocked-words.txt（私有素材 repo 要在 repo 根目錄）" >&2
  exit 2
fi
# 清單裡的空行與 # 註解不是字詞（空樣式會命中每一行）；再加上本機簽署檔裡的 Team ID（和 git 的 pre-commit 檢查相同）
patterns=$(mktemp)
trap 'rm -f "$patterns"' EXIT
grep -vE '^[[:space:]]*(#|$)' "$words" > "$patterns"
signing="$root/ios/Config/Signing.local.xcconfig"
[ -f "$signing" ] && sed -n -E 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' "$signing" >> "$patterns"

# diff 只看新增的那一側（以 + 開頭、不是檔頭 +++）；檔案與 commit 訊息整份都看
added_only() { grep -E '^\+' | grep -vE '^\+\+\+ '; }
case "${1:-}" in
  --staged)   content=$(git diff --cached | added_only) ;;
  --file)     content=$(cat "${2:?缺少檔案路徑}") ;;
  --unpushed)
    range='@{upstream}..HEAD'
    git rev-parse --verify -q '@{upstream}' >/dev/null || range='origin/main..HEAD'
    content="$(git log --format=%B "$range")
$(git log -p --format= "$range" | added_only)" ;;
  *) echo "用法：scan.sh --staged | --file <檔案> | --unpushed" >&2; exit 2 ;;
esac

hit=0
check() {
  # $1：說明；其餘：grep 參數與樣式
  label=$1; shift
  found=$(printf '%s\n' "$content" | LC_ALL=C grep -n "$@" | head -5)
  if [ -n "$found" ]; then
    echo "命中：$label"
    printf '%s\n' "$found" | cut -c1-160
    hit=1
  fi
}

# 固定字串、逐位元組比對：這台 Mac 的語系設定下，-i 的中文正規表示式會比對失敗（2026-11-16 實測）
check "私人字詞或本機 Team ID" -i -F -f "$patterns"
# Team ID 寫成實際值（xcconfig 的範本留空，不算）
check "Team ID" -E 'DEVELOPMENT_TEAM *= *[A-Z0-9]{10}'
# iPhone 的 UDID：8 碼十六進位、一槓、16 碼十六進位
check "iPhone 裝置代號" -E '[0-9A-F]{8}-[0-9A-F]{16}'
# 含使用者名稱的本機絕對路徑
check "本機路徑" -E '/Users/[A-Za-z]'

if [ "$hit" -eq 0 ]; then
  echo "掃描通過：沒有私人字詞、Team ID、裝置代號、本機路徑"
fi
exit "$hit"
