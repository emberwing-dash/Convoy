#!/bin/sh
# Logic tests for supabase/functions/groq-proxy-v2 (validation, 429 classification, usage, errors).
# Runs in Node 22+ with type stripping; Supabase/Deno are stubbed. No network, no secrets.
#   sh supabase/tests/groq-proxy-v2/run.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
sed -e 's#^import "jsr:@supabase/functions-js/edge-runtime.d.ts";##' \
    -e 's#from "jsr:@supabase/supabase-js@2"#from "./stub.mts"#' \
    "$HERE/../../functions/groq-proxy-v2/index.ts" > "$TMP/v2.mts"
echo 'export { validate, classify429, usageOf, usageRefusal, providerFailure };' >> "$TMP/v2.mts"
cp "$HERE/test.mts" "$HERE/setup.mjs" "$HERE/stub.mts" "$TMP/"
cd "$TMP" && node --experimental-strip-types test.mts 2>&1 | grep -v ExperimentalWarning
rm -rf "$TMP"
