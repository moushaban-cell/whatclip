#!/bin/sh
# Runs the tests with Swift Testing on a Mac that has only the Command Line Tools (no Xcode).
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test --build-system native -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F "$@"
