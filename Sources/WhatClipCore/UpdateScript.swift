import Foundation

/// Builds the shell script that installs a new WhatClip release. It runs in Terminal, where the person can read every step.
/// The script downloads the release zip and its checksum from this repository over HTTPS, checks the checksum, checks the bundle
/// identifier, replaces the app in Applications (keeping a backup until the copy succeeds), and opens WhatClip again.
/// Your history and settings are in Application Support, so they are not touched.
public enum UpdateScript {
    public static let bundleID = "app.whatclip.WhatClip"

    /// The script for one version. Returns nil unless the version is plain numbers and dots (so nothing can be injected into the script).
    public static func make(version: String) -> String? {
        guard !version.isEmpty, version.count <= 20,
              version.allSatisfy({ $0.isNumber || $0 == "." }), !version.hasPrefix("."), !version.hasSuffix(".") else { return nil }
        let base = "https://github.com/moushaban-cell/whatclip/releases/download/v\(version)/WhatClip-\(version)"
        return """
        #!/bin/sh
        # WhatClip \(version) installer. Read it before you run it; it only downloads from github.com/moushaban-cell/whatclip.
        set -u
        VERSION="\(version)"
        URL="\(base).zip"
        SUM_URL="\(base).zip.sha256"
        TMP=$(mktemp -d)
        BACKUP=""
        cleanup() {
            # If the new copy did not land, put the old app back.
            if [ -n "$BACKUP" ] && [ -d "$BACKUP" ] && [ ! -d "/Applications/WhatClip.app" ]; then
                mv "$BACKUP" "/Applications/WhatClip.app"
                echo "The update did not finish, so the previous WhatClip was restored."
            fi
            rm -rf "$TMP"
        }
        trap cleanup EXIT

        echo "Downloading WhatClip $VERSION..."
        curl -fL --proto '=https' --tlsv1.2 -o "$TMP/app.zip" "$URL" || { echo "Download failed. Nothing was changed."; read -r _; exit 1; }
        curl -fL --proto '=https' --tlsv1.2 -o "$TMP/app.zip.sha256" "$SUM_URL" || { echo "Checksum download failed. Nothing was changed."; read -r _; exit 1; }

        EXPECTED=$(awk '{print $1}' "$TMP/app.zip.sha256")
        ACTUAL=$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')
        if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
            echo "The checksum does not match. Nothing was installed."
            read -r _; exit 1
        fi
        echo "Checksum verified."

        ditto -x -k "$TMP/app.zip" "$TMP/unpacked"
        NEW="$TMP/unpacked/WhatClip.app"
        if [ ! -d "$NEW" ]; then echo "The download does not contain WhatClip. Nothing was installed."; read -r _; exit 1; fi
        ID=$(defaults read "$NEW/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
        if [ "$ID" != "\(bundleID)" ]; then echo "The download is not WhatClip. Nothing was installed."; read -r _; exit 1; fi

        echo "Closing WhatClip..."
        osascript -e 'tell application "WhatClip" to quit' >/dev/null 2>&1 || true
        sleep 2

        echo "Installing into Applications..."
        if [ -d "/Applications/WhatClip.app" ]; then
            BACKUP="$TMP/previous.app"
            mv "/Applications/WhatClip.app" "$BACKUP"
        fi
        ditto "$NEW" "/Applications/WhatClip.app"
        BACKUP_DONE="done"

        echo "WhatClip $VERSION is installed. Opening it again..."
        open "/Applications/WhatClip.app"
        echo "Your history and settings were not changed."
        echo "You can close this window."
        read -r _
        """
    }
}
