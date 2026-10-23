#!/usr/bin/env bash
# 在 Windows（Git Bash）產生 Apple 憑證申請檔 CSR，不需要 Mac。
# 用法：bash tools/ios/make-csr.sh "你的名字或公司" your@email.com
# 產物：tools/ios/secrets/ios_dist.key（私鑰，勿外流）、tools/ios/secrets/ios_dist.csr（上傳到 Apple）
set -euo pipefail
NAME="${1:?請給名字}"; EMAIL="${2:?請給 Email}"
DIR="$(cd "$(dirname "$0")" && pwd)/secrets"
mkdir -p "$DIR"
openssl genrsa -out "$DIR/ios_dist.key" 2048
openssl req -new -key "$DIR/ios_dist.key" -out "$DIR/ios_dist.csr" -subj "/CN=$NAME/emailAddress=$EMAIL/C=TW"
echo "完成："
echo "  私鑰：$DIR/ios_dist.key   （保密）"
echo "  CSR ：$DIR/ios_dist.csr   → 到 https://developer.apple.com/account/resources/certificates/add"
echo "        選 Apple Distribution，上傳這個 .csr，下載 distribution.cer 放到 $DIR/"
echo "然後執行：bash tools/ios/make-p12.sh"
