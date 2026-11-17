#!/usr/bin/env bash
# Repro — un fix a fait un GET serveur sur une URL fournie par l'utilisateur avec redirect: 'follow' : une
# redirection mène où la réponse veut, hôte interne compris (SSRF). Vu deux fois en revue, jamais par un script.
#   - gauntlet/fetch_redirect.py : [WARN] fichier:ligne sur fetch(url non constante) qui suit les redirections ;
#     rien sur redirect: 'manual' | 'error', une URL constante ou d'origine écrite, un commentaire, un test ;
#   - fix_gauntlet.sh green et gauntlet.sh green portent server_fetch_redirect, qui ne fait jamais échouer le gate.
source "$(dirname "$0")/fixture.sh"

DETECT="$TESTS_DIR/../fetch_redirect.py"
FIX_G="$TESTS_DIR/../../fix_gauntlet.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/srv/extract" "$R/srv/test" "$R/.claude/fixes/ssrf"
echo '{"name":"srv"}' > "$R/srv/package.json"
echo "export const x = 1;" > "$R/srv/extract/post.js"
base="$(commit "$R" "base")"
R="$(cd "$R" && pwd -P)"
printf '{"base_sha":"%s"}\n' "$base" > "$R/.claude/fixes/ssrf/fix.json"
printf '{"package":"srv","test_files":["srv/test/post.test.js"]}\n' > "$R/.claude/fixes/ssrf/repro.json"

# L'exemple du pattern : l'URL vient de la requête, garde par sous-chaîne, redirections suivies.
cat > "$R/srv/extract/post.js" <<'EOF'
const isPostUrl = (url) => url.includes('example.com');

export async function fetchPost(url) {
  if (!isPostUrl(url)) return null;
  const res = await fetch(url, {
    redirect: 'follow',
    headers: { 'user-agent': 'Mozilla/5.0' },
  });
  return res.text();
}

export async function fetchImage(imageUrl) {
  return fetch(imageUrl);
}
EOF
# La même chose qui refuse les redirections : rien à dire.
cat > "$R/srv/extract/safe.js" <<'EOF'
const API_URL = 'https://api.example.com/v1/items';
const base = 'https://api.example.com';
const OPTS = { redirect: 'error' };

export async function fetchPost(url) {
  // fetch(url, { redirect: 'follow' }) : l'ancienne version
  const res = await fetch(url, { redirect: 'manual', headers: {} });
  await fetch(url, OPTS);
  await fetch(API_URL);
  await fetch(base);
  await fetch(`https://api.example.com/v1/items/${encodeURIComponent(url)}`);
  return res.status;
}

class Client { async fetch(req) { return req; } }
EOF
echo "fetch(url, { redirect: 'follow' });" > "$R/srv/test/post.test.js"

echo "fetch_redirect.py"
OUT="$(python3 "$DETECT" "$R" srv/extract/post.js srv/extract/safe.js srv/test/post.test.js 2>&1)"; RC=$?
expect_rc 0 "jamais bloquant"
expect_out "[WARN] srv/extract/post.js:5 — fetch(url) suit les redirections (redirect: 'follow')" "redirect: 'follow' signalé, fichier:ligne"
expect_out "[WARN] srv/extract/post.js:13 — fetch(imageUrl) suit les redirections (pas d'options" "fetch sans options signalé"
expect_out "SSRF" "le WARN dit le risque"
expect_no_out "safe.js" "redirect: 'manual' | 'error', URL constante ou d'origine écrite, commentaire, méthode fetch : rien"
expect_no_out "post.test.js" "un test n'est pas du code serveur"

echo "fix_gauntlet.sh server_fetch_redirect"
OUT="$(cd "$R" && bash "$FIX_G" server_fetch_redirect ssrf 2>&1)"; RC=$?
expect_rc 0 "le check ne fait pas échouer le gate"
expect_out "[WARN] srv/extract/post.js:5" "le WARN sort dans le gate du fix"
expect_no_out "safe.js" "rien sur le fichier sûr"
rm "$R/srv/extract/post.js"; git -C "$R" checkout -q -- srv/extract/post.js
rm "$R/srv/extract/safe.js" "$R/srv/test/post.test.js"
OUT="$(cd "$R" && bash "$FIX_G" server_fetch_redirect ssrf 2>&1)"; RC=$?
expect_rc 0 "sans fichier JS modifié : non bloquant"
expect_out "[N/A]  server_fetch_redirect" "sans fichier JS modifié : [N/A], jamais vert"

echo "profils green"
OUT="$(bash -c 'eval "$(sed -n "/^profile_checks() {/,/^}/p" "$1")"; profile_checks green' _ "$FIX_G")"
expect_out "server_fetch_redirect" "green de /fix"
OUT="$(bash -c 'source "$1"; profile_checks green; profile_checks green_data' _ "$TESTS_DIR/../profiles.sh")"
expect_out "strict server_fetch_redirect" "green de /feature"
[ "$(grep -c server_fetch_redirect <<<"$OUT")" = 2 ] && _pass "green_data aussi" || _fail "green_data sans server_fetch_redirect"

echo "gauntlet.sh server_fetch_redirect (feature)"
if command -v fvm >/dev/null && [ -n "$FVM_FLUTTER_VERSION" ]; then
  P="$TMP_ROOT/feat"; mk_repo "$P"; write_cfg "$P"
  mk_pkg "$P/app/features/feat" feat
  mkdir -p "$P/app/features/feat/tool"
  printf 'export const go = (u) => fetch(u);\nexport const ok = (u) => fetch(u, { redirect: "manual" });\n' > "$P/app/features/feat/tool/proxy.js"
  commit "$P" base >/dev/null
  OUT="$(cd "$P" && bash "$GAUNTLET" server_fetch_redirect feat 2>&1)"; RC=$?
  expect_rc 0 "feature : le check ne fait pas échouer le gate"
  expect_out "[WARN] app/features/feat/tool/proxy.js:1" "feature : le WARN sort, fichier:ligne"
  expect_no_out "proxy.js:2" "feature : redirect: 'manual' n'est pas signalé"
else echo "  SKIP feature : fvm requis (fixture du gauntlet feature)"; fi

finish
