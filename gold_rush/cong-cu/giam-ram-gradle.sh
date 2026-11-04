#!/usr/bin/env bash
# Giảm lượng RAM mà Gradle được phép dùng — bản cho macOS và Linux.
# Xem giải thích đầy đủ trong giam-ram-gradle.ps1 và KHAC-PHUC-DO-MAY.md.
#
#   bash cong-cu/giam-ram-gradle.sh        # mặc định 2G
#   bash cong-cu/giam-ram-gradle.sh 3G
set -euo pipefail

HEAP="${1:-2G}"
GOC="$(cd "$(dirname "$0")/.." && pwd)"
TEP="$GOC/android/gradle.properties"

if [ ! -f "$TEP" ]; then
  echo "Chưa có android/gradle.properties. Chạy 'flutter create .' trước."
  exit 1
fi

TAM="$(mktemp)"
grep -Ev '^(org\.gradle\.jvmargs|org\.gradle\.parallel|org\.gradle\.workers\.max|kotlin\.daemon\.jvmargs)=' "$TEP" > "$TAM" || true
cat >> "$TAM" <<EOF
org.gradle.jvmargs=-Xmx$HEAP -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8
org.gradle.parallel=false
org.gradle.workers.max=2
kotlin.daemon.jvmargs=-Xmx1G
EOF
mv "$TAM" "$TEP"
echo "Đã đặt Gradle dùng tối đa $HEAP RAM trong $TEP"

if [ -x "$GOC/android/gradlew" ]; then
  (cd "$GOC/android" && ./gradlew --stop >/dev/null 2>&1 || true)
fi
echo "Xong. Chạy lại: flutter run"
