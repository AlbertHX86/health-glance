#!/bin/bash
# Builds HealthWidget.app (menu-bar app + widget extension) with the Command Line Tools only, ad-hoc signed.
#   ./build.sh            build into build/
#   ./build.sh install    also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")"
B=build
mkdir -p $B
# CLT 26.x ships a duplicate SwiftBridging module map; hide it from the compiler
: > $B/empty.modulemap
cat > $B/overlay.yaml <<YAML
{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"/Library/Developer/CommandLineTools/usr/include/swift","contents":[{"type":"file","name":"module.modulemap","external-contents":"$PWD/$B/empty.modulemap"}]}]}
YAML
O=(-vfsoverlay $B/overlay.yaml -target arm64-apple-macos14.0 -swift-version 5 -O)
APP=$B/HealthWidget.app; A=$APP/Contents; X=$A/PlugIns/HealthWidgetExtension.appex/Contents
rm -rf $APP; mkdir -p $A/MacOS $X/MacOS
swiftc "${O[@]}" -parse-as-library Sources/Shared/*.swift Sources/App/*.swift -o $A/MacOS/HealthWidget
swiftc "${O[@]}" -parse-as-library -application-extension Sources/Shared/*.swift Sources/Widget/*.swift -o $X/MacOS/HealthWidgetExtension
swiftc "${O[@]}" Sources/Shared/Health.swift Sources/App/Engine.swift Sources/CLI/main.swift -o $B/healthwidget-cli
cp Resources/App-Info.plist $A/Info.plist
cp Resources/Widget-Info.plist $X/Info.plist
codesign -f -s - --entitlements Resources/Widget.entitlements $A/PlugIns/HealthWidgetExtension.appex
codesign -f -s - $APP
codesign -v --deep $APP
echo "built $APP"
if [ "${1:-}" = install ]; then
  mkdir -p ~/Applications
  osascript -e 'quit app "HealthWidget"' 2>/dev/null || true
  rm -rf ~/Applications/HealthWidget.app && cp -R $APP ~/Applications/
  open ~/Applications/HealthWidget.app
  echo "installed ~/Applications/HealthWidget.app"
fi
