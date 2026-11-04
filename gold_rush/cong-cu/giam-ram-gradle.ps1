# Giảm lượng RAM mà Gradle được phép dùng khi dựng bản Android.
#
# VÌ SAO CẦN: lệnh `flutter create` sinh ra android\gradle.properties với dòng
#   org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G ...
# tức là cho Gradle dùng tới 8 GB RAM, cộng thêm 4 GB metaspace. Trên máy
# 8 GB đang mở máy ảo Android, lần build đầu tiên đẩy Windows vào tình trạng
# tráo đổi bộ nhớ liên tục — chuột không nhúc nhích, trông như máy bị đơ.
#
# CÁCH DÙNG (PowerShell, đứng ở thư mục gốc dự án, SAU khi đã chạy
# `flutter create .`):
#     powershell -ExecutionPolicy Bypass -File cong-cu\giam-ram-gradle.ps1
#     powershell -ExecutionPolicy Bypass -File cong-cu\giam-ram-gradle.ps1 -Heap 3G
#
# Gợi ý chọn -Heap theo RAM của máy:
#     8 GB  -> 2G  (và nên dùng điện thoại thật thay máy ảo)
#     16 GB -> 3G hoặc 4G
#     32 GB -> không cần chạy script này
param(
    [string]$Heap = "2G"
)

$ErrorActionPreference = "Stop"
$goc = Split-Path -Parent $PSScriptRoot
$tep = Join-Path $goc "android\gradle.properties"

if (-not (Test-Path $tep)) {
    Write-Host "Chưa có android\gradle.properties." -ForegroundColor Yellow
    Write-Host "Chạy 'flutter create .' ở thư mục gốc dự án trước, rồi chạy lại script này."
    exit 1
}

# Giữ nguyên mọi dòng khác (android.useAndroidX, các cờ mà template mới thêm
# vào...), chỉ thay bốn dòng liên quan tới bộ nhớ và số luồng.
$bo = '^(org\.gradle\.jvmargs|org\.gradle\.parallel|org\.gradle\.workers\.max|kotlin\.daemon\.jvmargs)='
$giu = Get-Content $tep | Where-Object { $_ -notmatch $bo }

$moi = @($giu) + @(
    "org.gradle.jvmargs=-Xmx$Heap -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8",
    "org.gradle.parallel=false",
    "org.gradle.workers.max=2",
    "kotlin.daemon.jvmargs=-Xmx1G"
)

# Ghi UTF-8 KHÔNG có BOM. `Set-Content -Encoding UTF8` của PowerShell 5 chèn
# BOM vào đầu tệp, và Java đọc BOM thành một phần của khoá đầu tiên — dòng
# cấu hình đầu tiên sẽ bị bỏ qua mà không báo lỗi gì.
[System.IO.File]::WriteAllLines($tep, $moi, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Đã đặt Gradle dùng tối đa $Heap RAM trong $tep" -ForegroundColor Green

# Tắt các tiến trình Gradle đang chạy, nếu không cấu hình mới chỉ có hiệu lực
# sau khi khởi động lại máy.
$gradlew = Join-Path $goc "android\gradlew.bat"
if (Test-Path $gradlew) {
    Write-Host "Đang tắt các tiến trình Gradle cũ..."
    Push-Location (Join-Path $goc "android")
    try { & $gradlew --stop | Out-Null } catch { }
    Pop-Location
}
Write-Host "Xong. Chạy lại: flutter run"
