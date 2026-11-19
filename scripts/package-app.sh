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
# no NSAllowsArbitraryLoads. One exception: the Tailscale MagicDNS name of the gateway.
# No SSH tunnel: the app calls the gateway directly over Tailscale.
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
			<key>oracle-fra.tail318c35.ts.net</key>
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

# Stable signature when a development identity exists: the Keychain ACL then survives a
# rebuild (an ad-hoc signature changes per build and prompts again). Ad-hoc otherwise.
identity="${QUOTABAR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/')}"
if [ -n "$identity" ]; then
  codesign --force --sign "$identity" --timestamp=none "$app"
else
  codesign --force --sign - --timestamp=none "$app"
fi
codesign --verify --strict "$app"

echo "package-app: $app"
echo "package-app: bundle id $bundle_id · signed: ${identity:-ad-hoc} · run: open $app"
