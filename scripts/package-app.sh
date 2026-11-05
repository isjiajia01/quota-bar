#!/usr/bin/env bash
# Build QuotaBar.app: SwiftPM release binary + minimal bundle + ad-hoc signature.
# Output: build/QuotaBar.app (git-ignored). Nothing is installed, registered or started:
# no launchd job, no /Applications copy, no login item.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="$root/build/QuotaBar.app"
bundle_id="page.isjia.quotabar"

swift build -c release --package-path "$root"
bin="$(swift build -c release --package-path "$root" --show-bin-path)/QuotaBar"
[ -x "$bin" ] || { echo "package-app: missing release binary at $bin" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/QuotaBar"
printf 'APPL????' > "$app/Contents/PkgInfo"

# LSUIElement: agent app, no Dock icon. ATS: exception for the loopback tunnel only —
# no NSAllowsArbitraryLoads. ATS treatment of the literal 127.0.0.1 is verified by running
# the packaged app against the live tunnel (docs/PLATFORM_CONSTRAINTS.md › Packaging).
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>QuotaBar</string>
	<key>CFBundleIdentifier</key>
	<string>${bundle_id}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>QuotaBar</string>
	<key>CFBundleDisplayName</key>
	<string>QuotaBar</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
		<key>NSExceptionDomains</key>
		<dict>
			<key>127.0.0.1</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<false/>
			</dict>
		</dict>
	</dict>
</dict>
</plist>
PLIST

plutil -lint "$app/Contents/Info.plist"

# Ad-hoc signature: enough for local launch, not for distribution/notarization.
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"

echo "package-app: $app"
echo "package-app: bundle id $bundle_id · ad-hoc signed · run: open $app (or --fixture via Contents/MacOS/QuotaBar --fixture)"
