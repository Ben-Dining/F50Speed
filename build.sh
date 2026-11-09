#!/bin/bash
# 编译 F50Speed 并打包为 F50Speed.app
set -e
cd "$(dirname "$0")"

swiftc -O -swift-version 5 Sources/main.swift -o F50Speed

rm -rf F50Speed.app
mkdir -p F50Speed.app/Contents/MacOS
cp F50Speed F50Speed.app/Contents/MacOS/
cp App/Info.plist F50Speed.app/Contents/

echo "已生成 F50Speed.app，双击即可运行"
