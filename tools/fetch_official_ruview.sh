#!/usr/bin/env bash
# سحب مشروع RuView الرسمي كاملًا إلى vendor/ruview-full (مستثنى من Git).
#
# الاستخدام: ./tools/fetch_official_ruview.sh [--full-history]
set -euo pipefail

UPSTREAM="https://github.com/ruvnet/RuView.git"
PINNED_COMMIT="5728b90949e60e3f908d996997d453147c1794e0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/vendor/ruview-full"

if [[ "${1:-}" == "--full-history" ]]; then
  DEPTH_ARGS=()
  echo "→ سحب كامل مع التاريخ..."
else
  DEPTH_ARGS=(--depth 1)
  echo "→ سحب سريع (بدون تاريخ)..."
fi

if [[ -d "${TARGET}/.git" ]]; then
  echo "→ المجلّد موجود، تحديثه بدل إعادة السحب"
  git -C "${TARGET}" fetch --all --tags
else
  mkdir -p "${ROOT}/vendor"
  git clone "${DEPTH_ARGS[@]}" "${UPSTREAM}" "${TARGET}"
fi

# تثبيت النسخة المرجعية إن كانت موجودة في التاريخ
if git -C "${TARGET}" cat-file -e "${PINNED_COMMIT}^{commit}" 2>/dev/null; then
  echo "→ تثبيت الالتزام ${PINNED_COMMIT:0:12}"
  git -C "${TARGET}" checkout --quiet "${PINNED_COMMIT}"
else
  echo "! الالتزام المثبّت غير متاح في هذا السحب (نادرًا ما يحدث مع --depth 1)."
  echo "  شغّل: ./tools/fetch_official_ruview.sh --full-history"
fi

echo
echo "✔ المشروع الرسمي متاح في: ${TARGET#$ROOT/}"
echo
echo "نقاط بداية مفيدة:"
echo "  • README.md"
echo "  • docs/user-guide.md                    (التشغيل والمنافذ)"
echo "  • docs/adr/ADR-019-sensing-only-ui-mode.md  (صيغة sensing_update)"
echo "  • docs/adr/ADR-272-websocket-authentication-tickets.md"
echo "  • v2/crates/wifi-densepose-sensing-server/  (خادم الاستشعار)"
echo "  • ui/mobile/                            (تطبيق الموبايل المرجعي)"
