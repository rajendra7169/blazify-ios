#!/usr/bin/env bash
# The compiler pass that CAN run on Linux, where there is no Xcode.
#
# It cannot type-check the app. SwiftUI, UIKit and AVFoundation are Apple's and
# do not exist here, and even the files that import only Foundation reach for
# URLRequest and URLSession, which on Linux live in a module iOS has never heard
# of. So everything is PARSED instead.
#
# That is worth doing anyway: parsing catches a duplicate attribute, an
# unbalanced brace, a trailing closure in the wrong place — the mistakes that
# have cost whole ten-minute cloud builds — in about five seconds. What it
# cannot catch is anything about types or argument labels; only Xcode says that.
#
# The toolchain (once, ~2.8 GB, no root needed):
#   curl -LO https://download.swift.org/swift-6.1-release/ubuntu2404/swift-6.1-RELEASE/swift-6.1-RELEASE-ubuntu24.04.tar.gz
#   mkdir -p ~/.local/share && tar xzf swift-6.1-RELEASE-ubuntu24.04.tar.gz -C ~/.local/share
#   mv ~/.local/share/swift-6.1-RELEASE-ubuntu24.04 ~/.local/share/swift-6.1
set -u

SWIFTC="${SWIFTC:-$HOME/.local/share/swift-6.1/usr/bin/swiftc}"
[ -x "$SWIFTC" ] || SWIFTC="$(command -v swiftc || true)"
if [ -z "$SWIFTC" ] || [ ! -x "$SWIFTC" ]; then
    echo "No Swift toolchain found — see the install lines at the top of this script."
    exit 127
fi

cd "$(dirname "$0")/.."
status=0

echo "Parsing every source file…"
"$SWIFTC" -parse Sources/*.swift Widget/*.swift || status=1

# Calls against hand-written initialisers. The parser cannot type-check, so an
# argument a type does not accept reaches the cloud Mac and fails there; this is
# the one shape of that mistake that has cost builds.
echo
echo "Checking calls against hand-written initialisers…"
if python3 scripts/init-labels.py Sources Widget; then
    echo "  ok"
else
    echo "  ^ these arguments match no initialiser of that type."
    status=1
fi

# The handful of files that stand on their own — no app types, no networking —
# can be checked properly, and their logic can even be run. Add to this list
# only files that compile alone against plain Foundation.
SELF_CONTAINED="Sources/PlaylistLink.swift Sources/CardOrder.swift Sources/LibraryCardText.swift"

echo "Type-checking the files that stand on their own…"
for file in $SELF_CONTAINED; do
    if "$SWIFTC" -typecheck "$file"; then
        echo "  ok  $file"
    else
        echo "  ^^  $file"
        status=1
    fi
done

# The card ordering can be run, not just checked: the bug it exists to prevent
# was a button playing a song other than the one on its face.
echo
echo "Running the library-card test…"
if "$SWIFTC" -o /tmp/blazify-librarytext Sources/LibraryCardText.swift scripts/librarytext-test/main.swift 2>/dev/null; then
    /tmp/blazify-librarytext | tail -2 || status=1
else
    echo "  could not build the test"
    status=1
fi

echo
echo "Running the letterbox test…"
if "$SWIFTC" -o /tmp/blazify-letterbox scripts/letterbox-test/main.swift 2>/dev/null; then
    /tmp/blazify-letterbox | tail -2 || status=1
else
    echo "  could not build the test"
    status=1
fi

echo
echo "Running the card-order test…"
if "$SWIFTC" -o /tmp/blazify-cardorder Sources/CardOrder.swift scripts/cardorder-test/main.swift 2>/dev/null; then
    /tmp/blazify-cardorder | tail -3 || status=1
else
    echo "  could not build the test"
    status=1
fi

echo
if [ $status -eq 0 ]; then
    echo "Clean — no syntax errors. (Not a promise it builds: only Xcode type-checks.)"
else
    echo "Errors above. These would fail the build."
fi
exit $status
