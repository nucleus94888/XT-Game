#!/usr/bin/env bash
# 把 Apple 下載的 distribution.cer + 本機私鑰合成 .p12，並印出要貼進 GitHub Secrets 的 base64。
# 用法：bash tools/ios/make-p12.sh [p12密碼]
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/secrets"
PASS="${1:-hanzo-ios}"
CER="$DIR/distribution.cer"
[ -f "$CER" ] || { echo "找不到 $CER，請先從 Apple 下載憑證放到該處"; exit 1; }
openssl x509 -in "$CER" -inform DER -out "$DIR/distribution.pem"
openssl pkcs12 -export -inkey "$DIR/ios_dist.key" -in "$DIR/distribution.pem" -out "$DIR/ios_dist.p12" -passout "pass:$PASS" -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/ios_dist.key" -in "$DIR/distribution.pem" -out "$DIR/ios_dist.p12" -passout "pass:$PASS"
base64 -w0 "$DIR/ios_dist.p12" > "$DIR/APPLE_CERT_P12_BASE64.txt"
echo "完成：$DIR/ios_dist.p12"
echo "GitHub Secrets 要填："
echo "  APPLE_CERT_PASSWORD      = $PASS"
echo "  APPLE_CERT_P12_BASE64    = （內容在 $DIR/APPLE_CERT_P12_BASE64.txt）"
echo "另外還要："
echo "  APPLE_PROFILE_BASE64     = base64 -w0 你的.mobileprovision"
echo "  APPLE_TEAM_ID / APPLE_API_KEY_ID / APPLE_API_ISSUER_ID / APPLE_API_KEY_P8_BASE64（App Store Connect → 使用者與存取 → 整合 → 金鑰）"
