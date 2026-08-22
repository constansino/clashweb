#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/mihomo-manager.sh"
TARGET="${MIHOMO_MANAGER_TARGET:-/data/mihomo_manager.sh}"
STAMP="$(date '+%Y%m%d-%H%M%S')"

USB=""
for directory in /mnt/usb-*; do
  if [ -d "$directory/ShellCrash" ]; then
    USB="$directory"
    break
  fi
done

[ -n "$USB" ] || {
  echo 'ShellCrash USB directory was not found.' >&2
  exit 1
}

SECRET="$(sed -n 's/^secret=//p' "$USB/ShellCrash/configs/ShellCrash.cfg" 2>/dev/null | tail -n 1)"
[ -n "$SECRET" ] || {
  echo 'Mihomo controller secret is empty. Configure ShellCrash secret first.' >&2
  exit 1
}

BASE="$USB/services/mihomo-manager"
CGI="$BASE/www/cgi-bin/api.cgi"
BACKUP="$BASE/backups/install-$STAMP"
mkdir -p "$BACKUP" "$(dirname "$CGI")"

[ -f "$TARGET" ] && cp -p "$TARGET" "$BACKUP/mihomo_manager.sh"
[ -f "$CGI" ] && cp -p "$CGI" "$BACKUP/api.cgi"

cp "$SOURCE" "$TARGET"
chmod 700 "$TARGET"
cat > "$CGI" <<EOF
#!/bin/sh
exec "$TARGET" cgi
EOF
chmod 700 "$CGI"

"$TARGET" start-web

echo "Installed manager: $TARGET"
echo "Backup: $BACKUP"
echo "API: http://ROUTER_IP:8399/cgi-bin/api.cgi"
