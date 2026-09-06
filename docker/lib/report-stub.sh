# shellcheck shell=bash
# Static placeholder page publisher — sourced by entrypoint.sh only (not
# generate.sh: it never touches these paths, see docs/MULTI_MODEL.md). Used for
# two instances of the same underlying situation ("nothing valid to serve at
# this path yet"): the multi-model root landing page, and a per-model report
# directory that hasn't produced a successful report yet (first generation
# still in progress, or every attempt so far has failed).
#
# Deliberately does not list model slugs anywhere (§32.4) — discovering
# which models exist and their URLs is left to the deployer/documentation,
# not exposed to arbitrary visitors of the root path.

# mc_publish_stub <dir> <title> <body_html>
# Writes a minimal, self-contained index.html into <dir> (created if
# missing). Reuses the project's favicon set if present (same files
# generate.sh copies into real reports, see REPORT_THEME_DIR there) so a
# stub page doesn't look unfinished/broken in a browser tab.
mc_publish_stub() {
    local dir="$1" title="$2" body_html="$3"
    local theme_dir="${REPORT_THEME_DIR:-/opt/report-theme}"

    mkdir -p "$dir"
    cat > "$dir/index.html" << HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<link rel="icon" href="favicon.ico">
<style>
  body { font-family: system-ui, sans-serif; max-width: 38rem; margin: 4rem auto;
         padding: 0 1.5rem; color: #222; line-height: 1.5; }
  h1 { font-size: 1.35rem; }
  code { background: #eee; padding: .1rem .3rem; border-radius: .2rem; }
</style>
</head>
<body>
<h1>$title</h1>
$body_html
</body>
</html>
HTML

    if [ -d "$theme_dir/favicon" ]; then
        cp -f "$theme_dir"/favicon/*.ico "$theme_dir"/favicon/*.png "$dir/" 2> /dev/null || true
    fi
}
