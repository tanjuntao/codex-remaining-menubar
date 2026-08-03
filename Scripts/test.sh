#!/bin/zsh

set -euo pipefail

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "${CLT_FRAMEWORKS}/Testing.framework" && -f "${CLT_INTEROP}/lib_TestingInterop.dylib" ]]; then
    exec swift test \
        -Xswiftc -F \
        -Xswiftc "${CLT_FRAMEWORKS}" \
        -Xlinker -F \
        -Xlinker "${CLT_FRAMEWORKS}" \
        -Xlinker -rpath \
        -Xlinker "${CLT_FRAMEWORKS}" \
        -Xlinker -rpath \
        -Xlinker "${CLT_INTEROP}"
fi

exec swift test
