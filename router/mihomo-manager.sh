#!/bin/sh

PORT=8399
API_KEY="${MIHOMO_MANAGER_API_KEY:-}"
DEFAULT_PROFILE_URL="${MIHOMO_MANAGER_PROFILE_URL:-}"
MARK_DEFAULT=7892
DEFAULT_CN4_URL="https://testingcf.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt https://testingcf.jsdelivr.net/gh/fernvenue/chn-cidr-list@master/ipv4.txt"
DEFAULT_CN6_URL="https://testingcf.jsdelivr.net/gh/gaoyifan/china-operator-ip@ip-lists/china6.txt https://testingcf.jsdelivr.net/gh/fernvenue/chn-cidr-list@master/ipv6.txt"
DEFAULT_CN_REFRESH_HOURS=24
DEFAULT_PROFILE_SYNC_HOURS=1
MIHOMO_API="http://127.0.0.1:9999"
POLICY_TARGETS_CACHE=""

find_usb() {
  USB=""
  for d in /mnt/usb-*; do
    [ -d "$d/ShellCrash" ] && USB="$d" && break
  done
  [ -n "$USB" ] || {
    echo "USB ShellCrash directory not found" >&2
    exit 1
  }
  CRASHDIR="$USB/ShellCrash"
  BASE="$USB/services/mihomo-manager"
  WWW="$BASE/www"
  CGI="$WWW/cgi-bin"
  STATE="$BASE/state.conf"
  DEVICES="$BASE/device_bypass.list"
  DOMAINS="$BASE/force_domains.list"
  SUFFIXES="$BASE/force_suffixes.list"
  FORCE_NETS="$BASE/force_nets.list"
  FORCE4="$BASE/force_ipv4.list"
  FORCE6="$BASE/force_ipv6.list"
  DIRECT_DOMAINS="$BASE/direct_domains.list"
  DIRECT_SUFFIXES="$BASE/direct_suffixes.list"
  DIRECT_NETS="$BASE/direct_nets.list"
  DIRECT4="$BASE/direct_ipv4.list"
  DIRECT6="$BASE/direct_ipv6.list"
  DEVICE_POLICIES="$BASE/device_policies.list"
  DEVICE_RULES="$BASE/device_rules.list"
  DEVICE_PORT_RULES="$BASE/device_port_rules.list"
  GLOBAL_RULES="$BASE/global_rules.list"
  CUSTOM_RULES="$CRASHDIR/yamls/rules.yaml"
  CUSTOM_GROUPS="$CRASHDIR/yamls/proxy-groups.yaml"
  DEVICE_POLICY_LOG="/tmp/mihomo-manager-device-policy.log"
  WLAN_BYPASS="$BASE/wlan_bypass.list"
  LOG="$BASE/manager.log"
  URLS="$BASE/profile_urls.list"
  BACKUPS="$BASE/backups"
  SYNC_SCRIPT="/data/sync_substore_profile_to_shellcrash.sh"
  SYNC_CONF="/data/sync_substore_profile_to_shellcrash.conf"
  SYNC_LOG="/tmp/substore-profile-sync.log"
  SYNC_TEST_LOG="/tmp/substore-profile-config-test.log"
  DNSMASQ_CONF="/tmp/dnsmasq.d/mihomo-manager.conf"
  mkdir -p "$BASE" "$WWW" "$CGI" "$BACKUPS"
  [ -f "$STATE" ] || echo "CN_ACCEL=0" > "$STATE"
  [ -f "$WLAN_BYPASS" ] || printf 'wl1\nwl2\n' > "$WLAN_BYPASS"
  touch "$DEVICES" "$DOMAINS" "$SUFFIXES" "$FORCE_NETS" "$FORCE4" "$FORCE6" "$DIRECT_DOMAINS" "$DIRECT_SUFFIXES" "$DIRECT_NETS" "$DIRECT4" "$DIRECT6" "$DEVICE_POLICIES" "$DEVICE_RULES" "$DEVICE_PORT_RULES" "$GLOBAL_RULES" "$WLAN_BYPASS" "$LOG" "$URLS"
  if [ -z "$API_KEY" ]; then
    API_KEY="$(sed -n 's/^secret=//p' "$CRASHDIR/configs/ShellCrash.cfg" 2>/dev/null | tail -n 1)"
  fi
  if ! grep -q . "$URLS" 2>/dev/null && [ -n "$DEFAULT_PROFILE_URL" ]; then
    printf '%s\n' "$DEFAULT_PROFILE_URL" > "$URLS"
  fi
}

log_msg() {
  find_usb >/dev/null 2>&1 || true
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

load_state() {
  CN_ACCEL=0
  CN4_URL="$DEFAULT_CN4_URL"
  CN6_URL="$DEFAULT_CN6_URL"
  CN_REFRESH_HOURS="$DEFAULT_CN_REFRESH_HOURS"
  PROFILE_SYNC_HOURS="$DEFAULT_PROFILE_SYNC_HOURS"
  [ -f "$STATE" ] && . "$STATE" 2>/dev/null
  [ "$CN_ACCEL" = "1" ] || CN_ACCEL=0
  valid_url_list "$CN4_URL" || CN4_URL="$DEFAULT_CN4_URL"
  valid_url_list "$CN6_URL" || CN6_URL="$DEFAULT_CN6_URL"
  case "$CN_REFRESH_HOURS" in
    0|6|12|24|48|72|168) ;;
    *) CN_REFRESH_HOURS="$DEFAULT_CN_REFRESH_HOURS" ;;
  esac
  valid_profile_sync_hours "$PROFILE_SYNC_HOURS" || PROFILE_SYNC_HOURS="$DEFAULT_PROFILE_SYNC_HOURS"
}

save_state() {
  tmp="$STATE.tmp.$$"
  {
    echo "CN_ACCEL=$CN_ACCEL"
    printf "CN4_URL=%s\n" "$(shell_quote "$CN4_URL")"
    printf "CN6_URL=%s\n" "$(shell_quote "$CN6_URL")"
    echo "CN_REFRESH_HOURS=$CN_REFRESH_HOURS"
    echo "PROFILE_SYNC_HOURS=$PROFILE_SYNC_HOURS"
  } > "$tmp" && mv "$tmp" "$STATE"
}

shell_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

valid_url() {
  printf '%s\n' "$1" | grep -Eq "^https?://[^[:space:]\"']+$"
}

valid_url_list() {
  ok=1
  for item in $1; do
    valid_url "$item" || ok=0
  done
  [ "$ok" = 1 ]
}

valid_profile_sync_hours() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]{1,3}$' || return 1
  [ "$1" -le 168 ]
}

current_profile_url() {
  URL=""
  [ -f "$SYNC_CONF" ] && . "$SYNC_CONF" 2>/dev/null
  [ -n "$URL" ] || URL="$DEFAULT_PROFILE_URL"
  printf "%s" "$URL"
}

write_profile_url() {
  url="$1"
  tmp="$SYNC_CONF.tmp.$$"
  if {
    printf "URL=%s\n" "$(shell_quote "$url")"
  } > "$tmp" && mv "$tmp" "$SYNC_CONF"; then
    chmod 600 "$SYNC_CONF" 2>/dev/null || true
    return 0
  fi
  rm -f "$tmp"
  return 1
}

sync_interval_from_cron() {
  load_state
  echo $((PROFILE_SYNC_HOURS * 60))
}

set_sync_interval() {
  hours="$1"
  valid_profile_sync_hours "$hours" || return 1
  load_state
  PROFILE_SYNC_HOURS="$hours"
  save_state || return 1
  tmp="/tmp/mihomo-manager-cron.$$"
  crontab -l 2>/dev/null | grep -v '/data/sync_substore_profile_to_shellcrash.sh' | grep -v '/data/mihomo_manager.sh auto-sync' > "$tmp" || true
  if [ "$hours" != "0" ]; then
    echo "17 * * * * /data/mihomo_manager.sh auto-sync >/dev/null 2>&1" >> "$tmp"
  fi
  crontab "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"
}

auto_sync_profile() {
  find_usb
  load_state
  valid_profile_sync_hours "$PROFILE_SYNC_HOURS" || PROFILE_SYNC_HOURS="$DEFAULT_PROFILE_SYNC_HOURS"
  [ "$PROFILE_SYNC_HOURS" != "0" ] || exit 0
  now="$(date +%s)"
  last="$(cat "$BASE/last_profile_sync" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $((now - last)) -ge $((PROFILE_SYNC_HOURS * 3600)) ] || exit 0
  if /bin/sh "$SYNC_SCRIPT" >/tmp/mihomo-manager-auto-sync.log 2>&1; then
    date +%s > "$BASE/last_profile_sync"
    log_msg "auto sync ok"
  else
    log_msg "auto sync failed"
    exit 1
  fi
}

set_cfg_value() {
  key="$1"
  value="$2"
  cfg="$CRASHDIR/configs/ShellCrash.cfg"
  [ -f "$cfg" ] || return 1
  if grep -q "^$key=" "$cfg"; then
    sed -i "s#^$key=.*#$key=$value#" "$cfg"
  else
    echo "$key=$value" >> "$cfg"
  fi
}

get_cfg_value() {
  key="$1"
  cfg="$CRASHDIR/configs/ShellCrash.cfg"
  awk -F= -v k="$key" '$1==k {v=$2} END {print v}' "$cfg" 2>/dev/null
}

get_mark() {
  fwmark="$(get_cfg_value fwmark)"
  [ -n "$fwmark" ] || fwmark="$(get_cfg_value redir_port)"
  case "$fwmark" in
    ''|*[!0-9]*) fwmark="$MARK_DEFAULT" ;;
  esac
  MARK="$fwmark"
  MARK_HEX="$(printf '0x%x' "$MARK")"
  MARK_XHEX="$(printf '0x%x/0xffffffff' "$MARK")"
  BYPASS_MARK=$((MARK + 2))
  BYPASS_HEX="$(printf '0x%x' "$BYPASS_MARK")"
  BYPASS_XHEX="$(printf '0x%x/0xffffffff' "$BYPASS_MARK")"
}

valid_ipv4_or_cidr() {
  printf '%s\n' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
}

valid_ipv6_or_cidr() {
  printf '%s\n' "$1" | grep -Eiq '^[0-9a-f:]+(/[0-9]{1,3})?$' && printf '%s\n' "$1" | grep -q ':'
}

valid_ip_or_cidr() {
  valid_ipv4_or_cidr "$1" || valid_ipv6_or_cidr "$1"
}

valid_mac() {
  printf '%s\n' "$1" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
}

valid_domain() {
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9_-]*\.)+[A-Za-z0-9][A-Za-z0-9_-]*$'
}

valid_port_spec() {
  local spec start end
  spec="$1"
  printf '%s\n' "$spec" | grep -Eq '^[0-9]{1,5}(-[0-9]{1,5})?$' || return 1
  start="${spec%%-*}"
  end="$start"
  case "$spec" in
    *-*) end="${spec##*-}" ;;
  esac
  [ "$start" -ge 1 ] && [ "$start" -le 65535 ] || return 1
  [ "$end" -ge 1 ] && [ "$end" -le 65535 ] || return 1
  [ "$start" -le "$end" ]
}

norm_domain_suffix() {
  value="$(norm_value "$1")"
  case "$value" in
    \*.*) value="${value#*.}" ;;
    .*) value="${value#.}" ;;
  esac
  printf '%s\n' "$value"
}

trim_value() {
  printf '%s\n' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

norm_value() {
  trim_value "$1" | tr 'A-Z' 'a-z'
}

wlan_sections() {
  uci show wireless 2>/dev/null | awk -F= '$2=="wifi-iface" {print $1}'
}

wlan_label() {
  case "$1" in
    wl1) printf '%s\n' "WLAN 1" ;;
    wl0) printf '%s\n' "WLAN 2" ;;
    wl2) printf '%s\n' "WLAN 3" ;;
    *) printf 'WLAN %s\n' "$2" ;;
  esac
}

wlan_list() {
  seen=" "
  n=1
  for section in $(wlan_sections); do
    iface="$(uci -q get "$section.ifname" 2>/dev/null)"
    [ -n "$iface" ] || continue
    case " $seen " in *" $iface "*) continue ;; esac
    ssid="$(uci -q get "$section.ssid" 2>/dev/null)"
    network="$(uci -q get "$section.network" 2>/dev/null)"
    mode="$(uci -q get "$section.mode" 2>/dev/null)"
    disabled="$(uci -q get "$section.disabled" 2>/dev/null)"
    [ "$disabled" = "1" ] && continue
    [ "$network" = "lan" ] || continue
    [ "$mode" = "ap" ] || [ -z "$mode" ] || continue
    [ -n "$ssid" ] || continue
    case "$ssid" in MiMesh_*) continue ;; esac
    case "$iface" in wl*|wlan*) ;; *) continue ;; esac
    seen="$seen$iface "
    label="$(wlan_label "$iface" "$n")"
    printf '%s|%s|%s\n' "$iface" "$label" "$ssid"
    n=$((n + 1))
  done
}

valid_wlan_iface() {
  target="$1"
  wlan_list | awk -F'|' -v target="$target" '$1==target {found=1} END {exit found ? 0 : 1}'
}

wlan_rule_ifaces() {
  {
    printf 'wl1\nwl0\nwl2\n'
    wlan_list | awk -F'|' '{print $1}'
    [ -f "$WLAN_BYPASS" ] && cat "$WLAN_BYPASS"
  } | awk 'NF && !seen[$0]++'
}

wlan_bypass_ifaces() {
  [ -f "$WLAN_BYPASS" ] || return
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    valid_wlan_iface "$item" && printf '%s\n' "$item"
  done < "$WLAN_BYPASS"
}

set_wlan_mode() {
  input="$(norm_value "$1")"
  requested_iface="${input%%:*}"
  requested_mode="${input#*:}"
  [ "$requested_iface" != "$input" ] || return 1
  valid_wlan_iface "$requested_iface" || return 1
  case "$requested_mode" in
    bypass)
      add_unique_line "$WLAN_BYPASS" "$requested_iface"
    ;;
    mihomo)
      del_line "$WLAN_BYPASS" "$requested_iface"
    ;;
    *)
      return 1
    ;;
  esac
  apply_firewall
  log_msg "set wlan $requested_iface $requested_mode"
}

add_unique_line() {
  file="$1"
  value="$2"
  grep -Fxq "$value" "$file" 2>/dev/null || echo "$value" >> "$file"
}

del_line() {
  file="$1"
  value="$2"
  tmp="$file.tmp.$$"
  grep -Fxv "$value" "$file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}

ipset_count() {
  ipset list "$1" 2>/dev/null | awk -F: '/Number of entries/ {gsub(/ /,"",$2); print $2; found=1} END {if (!found) print 0}'
}

load_cn_sets() {
  [ -f "$CRASHDIR/cn_ip.txt" ] && {
    tmp="/tmp/mm_cn4.ipset.$$"
    ipset -! create mm_cn4 hash:net family inet hashsize 16384 maxelem 131072 >/dev/null 2>&1 || true
    ipset flush mm_cn4 >/dev/null 2>&1 || true
    : > "$tmp"
    awk '!/^$/&&!/^#/{print "add mm_cn4 "$1}' "$CRASHDIR/cn_ip.txt" >> "$tmp"
    ipset -! restore < "$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
  }
  [ -f "$CRASHDIR/cn_ipv6.txt" ] && {
    tmp="/tmp/mm_cn6.ipset.$$"
    ipset -! create mm_cn6 hash:net family inet6 hashsize 8192 maxelem 32768 >/dev/null 2>&1 || true
    ipset flush mm_cn6 >/dev/null 2>&1 || true
    : > "$tmp"
    awk '!/^$/&&!/^#/{print "add mm_cn6 "$1}' "$CRASHDIR/cn_ipv6.txt" >> "$tmp"
    ipset -! restore < "$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
  }
}

valid_cn_refresh_hours() {
  case "$1" in
    0|6|12|24|48|72|168) return 0 ;;
    *) return 1 ;;
  esac
}

set_cn_source() {
  input="$1"
  cn4="$(printf '%s\n' "$input" | sed -n '1p')"
  cn6="$(printf '%s\n' "$input" | sed -n '2p')"
  hours="$(printf '%s\n' "$input" | sed -n '3p')"
  cn4="$(trim_value "$cn4")"
  cn6="$(trim_value "$cn6")"
  hours="$(norm_value "$hours")"
  [ -n "$cn4" ] || cn4="$DEFAULT_CN4_URL"
  [ -n "$cn6" ] || cn6="$DEFAULT_CN6_URL"
  [ -n "$hours" ] || hours="$DEFAULT_CN_REFRESH_HOURS"
  valid_url_list "$cn4" || return 1
  valid_url_list "$cn6" || return 1
  valid_cn_refresh_hours "$hours" || return 1
  load_state
  CN4_URL="$cn4"
  CN6_URL="$cn6"
  CN_REFRESH_HOURS="$hours"
  save_state
}

download_cn_list() {
  urls="$1"
  dest="$2"
  family="$3"
  min_count="$4"
  raw="/tmp/mm_cn_raw.$$"
  merged="/tmp/mm_cn_merged.$$"
  clean="/tmp/mm_cn_clean.$$"
  : > "$merged"
  success=0
  for url in $urls; do
    if curl -fsSL --connect-timeout 8 --max-time 80 -o "$raw" "$url"; then
      cat "$raw" >> "$merged"
      printf '\n' >> "$merged"
      success=1
    else
      log_msg "CN list source failed $family $url"
    fi
  done
  [ "$success" = 1 ] || {
    rm -f "$raw" "$merged" "$clean"
    return 1
  }
  case "$family" in
    4)
      awk 'NF && $0 !~ /^#/ && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/ {print $1}' "$merged" | sort -u > "$clean"
    ;;
    6)
      awk 'NF && $0 !~ /^#/ && $1 ~ /^[0-9A-Fa-f:]+(\/[0-9]{1,3})?$/ && $1 ~ /:/ {print tolower($1)}' "$merged" | sort -u > "$clean"
    ;;
    *)
      rm -f "$raw" "$merged" "$clean"
      return 1
    ;;
  esac
  count="$(awk 'END {print NR+0}' "$clean")"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  if [ "$count" -lt "$min_count" ]; then
    rm -f "$raw" "$merged" "$clean"
    return 1
  fi
  if [ -f "$dest" ] && cmp -s "$clean" "$dest"; then
    log_msg "CN list unchanged $family count=$count"
  else
    TS="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$BASE/cn-backups"
    [ -f "$dest" ] && cp -p "$dest" "$BASE/cn-backups/$(basename "$dest").before-$TS" 2>/dev/null || true
    cp -f "$clean" "$dest"
    log_msg "CN list updated $family count=$count"
  fi
  rm -f "$raw" "$merged" "$clean"
  return 0
}

refresh_cn_lists() {
  find_usb
  load_state
  ok=0
  download_cn_list "$CN4_URL" "$CRASHDIR/cn_ip.txt" 4 1000 && ok=1
  download_cn_list "$CN6_URL" "$CRASHDIR/cn_ipv6.txt" 6 500 && ok=1
  [ "$ok" = 1 ] || return 1
  date +%s > "$BASE/last_cn_refresh"
  load_cn_sets
}

apply_direct_preset() {
  name="$1"
  find_usb
  case "$name" in
    wechat)
      for item in \
        weixin.qq.com \
        wx.qq.com \
        qq.com \
        gtimg.com \
        gtimg.cn \
        qpic.cn \
        tencent.com \
        tencent-cloud.com \
        myqcloud.com \
        wechat.com
      do
        add_unique_line "$DIRECT_SUFFIXES" "$item"
      done
      add_unique_line "$DIRECT_DOMAINS" "wetype.weixin.qq.com"
    ;;
    cn-common)
      for item in \
        baidu.com \
        bdstatic.com \
        bilibili.com \
        bilivideo.com \
        douyin.com \
        snssdk.com \
        byteimg.com \
        alibaba.com \
        taobao.com \
        tmall.com \
        alipay.com \
        jd.com \
        163.com \
        126.net \
        mi.com \
        xiaomi.com \
        miwifi.com
      do
        add_unique_line "$DIRECT_SUFFIXES" "$item"
      done
    ;;
    *)
      return 1
    ;;
  esac
  resolve_direct_domains
  apply_firewall
  log_msg "apply direct preset $name"
}

normalize_target() {
  value="$(trim_value "$1" | tr 'A-Z' 'a-z')"
  case "$value" in
    http://*) value="${value#http://}" ;;
    https://*) value="${value#https://}" ;;
  esac
  value="${value%%/*}"
  case "$value" in
    \[*\]*) value="${value#\[}"; value="${value%%\]*}" ;;
    *:*)
      if ! valid_ipv6_or_cidr "$value"; then
        value="${value%%:*}"
      fi
    ;;
  esac
  echo "$value"
}

resolve_host_file() {
  host="$1"
  resolver="$2"
  out="$3"
  : > "$out"
  nslookup "$host" "$resolver" 2>/dev/null | awk '
    /^Name:/ {seen=1; next}
    seen && /^Address [0-9]+:/ {print $3}
  ' | sort -u > "$out"
}

file_has_line() {
  file="$1"
  value="$2"
  grep -Fxq "$value" "$file" 2>/dev/null
}

first_suffix_match() {
  file="$1"
  host="$2"
  while IFS= read -r item; do
    item="$(norm_domain_suffix "$item")"
    [ -z "$item" ] && continue
    [ "$host" = "$item" ] && {
      echo "$item"
      return
    }
    case "$host" in
      *."$item")
        echo "$item"
        return
      ;;
    esac
  done < "$file"
}

ipset_bool() {
  setname="$1"
  ip="$2"
  ipset test "$setname" "$ip" >/dev/null 2>&1 && echo true || echo false
}

json_ip_checks() {
  file="$1"
  printf '['
  first=1
  while IFS= read -r ip; do
    ip="$(trim_value "$ip")"
    [ -z "$ip" ] && continue
    [ "$first" = 1 ] || printf ','
    first=0
    case "$ip" in
      *:*)
        cn="$(ipset_bool mm_cn6 "$ip")"
        force="$(ipset_bool mm_force6 "$ip")"
        [ "$force" = true ] || force="$(ipset_bool mm_force_net6 "$ip")"
        direct="$(ipset_bool mm_direct6 "$ip")"
        [ "$direct" = true ] || direct="$(ipset_bool mm_direct_net6 "$ip")"
        force_suffix="$(ipset_bool mm_suffix6 "$ip")"
        direct_suffix="$(ipset_bool mm_direct_suffix6 "$ip")"
      ;;
      *)
        cn="$(ipset_bool mm_cn4 "$ip")"
        force="$(ipset_bool mm_force4 "$ip")"
        [ "$force" = true ] || force="$(ipset_bool mm_force_net4 "$ip")"
        direct="$(ipset_bool mm_direct4 "$ip")"
        [ "$direct" = true ] || direct="$(ipset_bool mm_direct_net4 "$ip")"
        force_suffix="$(ipset_bool mm_suffix4 "$ip")"
        direct_suffix="$(ipset_bool mm_direct_suffix4 "$ip")"
      ;;
    esac
    printf '{"ip":"%s","cn":%s,"force":%s,"force_suffix":%s,"direct":%s,"direct_suffix":%s}' \
      "$(printf '%s' "$ip" | json_escape)" "$cn" "$force" "$force_suffix" "$direct" "$direct_suffix"
  done < "$file"
  printf ']'
}

diagnose_json() {
  host="$(normalize_target "$1")"
  if ! valid_domain "$host"; then
    cgi_reply "400 Bad Request" '{"ok":false,"error":"bad domain"}'
    return
  fi
  find_usb
  load_state
  get_mark
  ensure_basic_sets
  sync_dnsmasq_suffixes
  local_ips="/tmp/mm_diag_local.$$"
  public_ips="/tmp/mm_diag_public.$$"
  all_ips="/tmp/mm_diag_all.$$"
  resolve_host_file "$host" "127.0.0.1" "$local_ips"
  resolve_host_file "$host" "223.5.5.5" "$public_ips"
  cat "$local_ips" "$public_ips" 2>/dev/null | sort -u > "$all_ips"
  force_domain=false
  direct_domain=false
  file_has_line "$DOMAINS" "$host" && force_domain=true
  file_has_line "$DIRECT_DOMAINS" "$host" && direct_domain=true
  force_suffix="$(first_suffix_match "$SUFFIXES" "$host")"
  direct_suffix="$(first_suffix_match "$DIRECT_SUFFIXES" "$host")"
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '{'
  printf '"ok":true,'
  printf '"host":"%s",' "$(printf '%s' "$host" | json_escape)"
  printf '"force_domain":%s,' "$force_domain"
  printf '"direct_domain":%s,' "$direct_domain"
  printf '"force_suffix":"%s",' "$(printf '%s' "$force_suffix" | json_escape)"
  printf '"direct_suffix":"%s",' "$(printf '%s' "$direct_suffix" | json_escape)"
  printf '"local_ips":'
  json_file_array "$local_ips"
  printf ',"public_ips":'
  json_file_array "$public_ips"
  printf ',"checks":'
  json_ip_checks "$all_ips"
  printf '}'
  rm -f "$local_ips" "$public_ips" "$all_ips"
}

ensure_basic_sets() {
  ipset -! create mm_device4 hash:net family inet hashsize 1024 maxelem 4096 >/dev/null 2>&1 || true
  ipset -! create mm_force4 hash:ip family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_force6 hash:ip family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_force_net4 hash:net family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_force_net6 hash:net family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_suffix4 hash:ip family inet hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset -! create mm_suffix6 hash:ip family inet6 hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset -! create mm_direct4 hash:ip family inet hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset -! create mm_direct6 hash:ip family inet6 hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset -! create mm_direct_net4 hash:net family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_direct_net6 hash:net family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_direct_suffix4 hash:ip family inet hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset -! create mm_direct_suffix6 hash:ip family inet6 hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  if [ "$CN_ACCEL" = "1" ]; then
    ipset list mm_cn4 >/dev/null 2>&1 || load_cn_sets
  fi
}

reload_dnsmasq() {
  if [ -x /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart >/tmp/mihomo-manager-dnsmasq.log 2>&1 || true
  else
    pidof dnsmasq >/dev/null 2>&1 && kill -HUP $(pidof dnsmasq) >/dev/null 2>&1 || true
  fi
}

sync_dnsmasq_suffixes() {
  mkdir -p /tmp/dnsmasq.d
  tmp="$DNSMASQ_CONF.tmp.$$"
  {
    echo "# generated by mihomo-manager"
    while IFS= read -r item; do
      item="$(norm_value "$item")"
      [ -z "$item" ] && continue
      valid_domain "$item" && echo "ipset=/$item/mm_force4,mm_force6"
    done < "$DOMAINS"
    while IFS= read -r item; do
      item="$(norm_domain_suffix "$item")"
      [ -z "$item" ] && continue
      valid_domain "$item" && echo "ipset=/$item/mm_suffix4,mm_suffix6"
    done < "$SUFFIXES"
    while IFS= read -r item; do
      item="$(norm_value "$item")"
      [ -z "$item" ] && continue
      valid_domain "$item" && echo "ipset=/$item/mm_direct4,mm_direct6"
    done < "$DIRECT_DOMAINS"
    while IFS= read -r item; do
      item="$(norm_domain_suffix "$item")"
      [ -z "$item" ] && continue
      valid_domain "$item" && echo "ipset=/$item/mm_direct_suffix4,mm_direct_suffix6"
    done < "$DIRECT_SUFFIXES"
  } > "$tmp"
  if [ -f "$DNSMASQ_CONF" ] && cmp -s "$tmp" "$DNSMASQ_CONF"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$DNSMASQ_CONF"
    ipset flush mm_suffix4 >/dev/null 2>&1 || true
    ipset flush mm_suffix6 >/dev/null 2>&1 || true
    ipset flush mm_direct_suffix4 >/dev/null 2>&1 || true
    ipset flush mm_direct_suffix6 >/dev/null 2>&1 || true
    reload_dnsmasq
    log_msg "reload dnsmasq domain rules"
  fi
}

append_resolved_ips() {
  host="$1"
  resolver="$2"
  out4="$3"
  out6="$4"
  nslookup "$host" "$resolver" 2>/dev/null | awk '
    /^Name:/ {seen=1}
    seen && /^Address [0-9]+:/ {print $3}
  ' | while IFS= read -r ip; do
    case "$ip" in
      *:*) echo "$ip" >> "$out6" ;;
      *.*) echo "$ip" >> "$out4" ;;
    esac
  done
}

load_device_set() {
  ipset -! create mm_device4 hash:net family inet hashsize 1024 maxelem 4096 >/dev/null 2>&1 || true
  ipset flush mm_device4 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    valid_ipv4_or_cidr "$item" && ipset -! add mm_device4 "$item" >/dev/null 2>&1 || true
  done < "$DEVICES"
}

resolve_domains() {
  tmp4="$FORCE4.tmp.$$"
  tmp6="$FORCE6.tmp.$$"
  : > "$tmp4"
  : > "$tmp6"
  while IFS= read -r domain; do
    domain="$(norm_value "$domain")"
    [ -z "$domain" ] && continue
    append_resolved_ips "$domain" 127.0.0.1 "$tmp4" "$tmp6"
    append_resolved_ips "$domain" 223.5.5.5 "$tmp4" "$tmp6"
  done < "$DOMAINS"
  sort -u "$tmp4" > "$FORCE4"
  sort -u "$tmp6" > "$FORCE6"
  rm -f "$tmp4" "$tmp6"
  date +%s > "$BASE/last_domain_refresh"
}

resolve_direct_domains() {
  tmp4="$DIRECT4.tmp.$$"
  tmp6="$DIRECT6.tmp.$$"
  : > "$tmp4"
  : > "$tmp6"
  while IFS= read -r domain; do
    domain="$(norm_value "$domain")"
    [ -z "$domain" ] && continue
    append_resolved_ips "$domain" 127.0.0.1 "$tmp4" "$tmp6"
    append_resolved_ips "$domain" 223.5.5.5 "$tmp4" "$tmp6"
  done < "$DIRECT_DOMAINS"
  sort -u "$tmp4" > "$DIRECT4"
  sort -u "$tmp6" > "$DIRECT6"
  rm -f "$tmp4" "$tmp6"
  date +%s > "$BASE/last_direct_refresh"
}

load_force_sets() {
  ipset -! create mm_force4 hash:ip family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset flush mm_force4 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    ipset -! add mm_force4 "$item" >/dev/null 2>&1 || true
  done < "$FORCE4"

  ipset -! create mm_force6 hash:ip family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset flush mm_force6 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    ipset -! add mm_force6 "$item" >/dev/null 2>&1 || true
  done < "$FORCE6"

  ipset -! create mm_force_net4 hash:net family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_force_net6 hash:net family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset flush mm_force_net4 >/dev/null 2>&1 || true
  ipset flush mm_force_net6 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    case "$item" in
      *:*) valid_ipv6_or_cidr "$item" && ipset -! add mm_force_net6 "$item" >/dev/null 2>&1 || true ;;
      *) valid_ipv4_or_cidr "$item" && ipset -! add mm_force_net4 "$item" >/dev/null 2>&1 || true ;;
    esac
  done < "$FORCE_NETS"
}

load_direct_sets() {
  ipset -! create mm_direct4 hash:ip family inet hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset flush mm_direct4 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    ipset -! add mm_direct4 "$item" >/dev/null 2>&1 || true
  done < "$DIRECT4"

  ipset -! create mm_direct6 hash:ip family inet6 hashsize 2048 maxelem 32768 >/dev/null 2>&1 || true
  ipset flush mm_direct6 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    ipset -! add mm_direct6 "$item" >/dev/null 2>&1 || true
  done < "$DIRECT6"

  ipset -! create mm_direct_net4 hash:net family inet hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset -! create mm_direct_net6 hash:net family inet6 hashsize 1024 maxelem 8192 >/dev/null 2>&1 || true
  ipset flush mm_direct_net4 >/dev/null 2>&1 || true
  ipset flush mm_direct_net6 >/dev/null 2>&1 || true
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    case "$item" in
      *:*) valid_ipv6_or_cidr "$item" && ipset -! add mm_direct_net6 "$item" >/dev/null 2>&1 || true ;;
      *) valid_ipv4_or_cidr "$item" && ipset -! add mm_direct_net4 "$item" >/dev/null 2>&1 || true ;;
    esac
  done < "$DIRECT_NETS"
}

ipt_chain_reset() {
  cmd="$1"
  table="$2"
  chain="$3"
  "$cmd" -t "$table" -N "$chain" >/dev/null 2>&1 || true
  "$cmd" -t "$table" -F "$chain" >/dev/null 2>&1 || true
}

ipt_remove_jump() {
  cmd="$1"
  table="$2"
  from="$3"
  to="$4"
  while "$cmd" -t "$table" -D "$from" -j "$to" >/dev/null 2>&1; do :; done
}

device_mac_values() {
  while IFS= read -r item; do
    item="$(norm_value "$item")"
    [ -z "$item" ] && continue
    if valid_mac "$item"; then
      printf '%s\n' "$item"
      continue
    fi
    case "$item" in
      */32) ip="${item%/32}" ;;
      */*) continue ;;
      *) ip="$item" ;;
    esac
    valid_ipv4_or_cidr "$ip" || continue
    mac="$(ip neigh show "$ip" dev br-lan 2>/dev/null | awk '
      { for (i=1; i<=NF; i++) if ($i=="lladdr") { print tolower($(i+1)); exit } }
    ')"
    if ! valid_mac "$mac"; then
      mac="$(awk -v ip="$ip" '$1==ip && $4!="00:00:00:00:00:00" {print tolower($4); exit}' /proc/net/arp 2>/dev/null)"
    fi
    valid_mac "$mac" && printf '%s\n' "$mac"
  done < "$DEVICES" | sort -u
}

add_common_device_returns() {
  cmd="$1"
  table="$2"
  chain="$3"
  if [ "$table" = "mangle" ]; then
    "$cmd" -t "$table" -A "$chain" -m set --match-set mm_device4 src -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
  fi
  "$cmd" -t "$table" -A "$chain" -m set --match-set mm_device4 src -j RETURN >/dev/null 2>&1 || true
  for item in $(device_mac_values); do
    [ "$table" = "mangle" ] && "$cmd" -t "$table" -A "$chain" -m mac --mac-source "$item" -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    "$cmd" -t "$table" -A "$chain" -m mac --mac-source "$item" -j RETURN >/dev/null 2>&1 || true
  done
}

add_common_ssid_returns() {
  cmd="$1"
  table="$2"
  chain="$3"
  for iface in $(wlan_bypass_ifaces); do
    if [ "$table" = "mangle" ]; then
      "$cmd" -t "$table" -A "$chain" -i "$iface" -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
      "$cmd" -t "$table" -A "$chain" -m physdev --physdev-in "$iface" -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    fi
    "$cmd" -t "$table" -A "$chain" -i "$iface" -j RETURN >/dev/null 2>&1 || true
    "$cmd" -t "$table" -A "$chain" -m physdev --physdev-in "$iface" -j RETURN >/dev/null 2>&1 || true
  done
}

del_table_rule_all() {
  cmd="$1"
  table="$2"
  chain="$3"
  shift 3
  command -v "$cmd" >/dev/null 2>&1 || return 0
  while "$cmd" -t "$table" -D "$chain" "$@" >/dev/null 2>&1; do :; done
}

del_filter_rule_all() {
  cmd="$1"
  chain="$2"
  shift 2
  command -v "$cmd" >/dev/null 2>&1 || return 0
  while "$cmd" -D "$chain" "$@" >/dev/null 2>&1; do :; done
}

cleanup_legacy_wlan_rules() {
  for iface in $(wlan_rule_ifaces); do
    del_table_rule_all iptables mangle shellcrash_mark -i "$iface" -j RETURN
    del_table_rule_all iptables mangle shellcrash_mark -m physdev --physdev-in "$iface" -j RETURN
    del_table_rule_all iptables nat shellcrash_dns -i "$iface" -j RETURN
    del_table_rule_all iptables nat shellcrash_dns -m physdev --physdev-in "$iface" -j RETURN
    del_table_rule_all ip6tables mangle shellcrashv6_mark -i "$iface" -j RETURN
    del_table_rule_all ip6tables mangle shellcrashv6_mark -m physdev --physdev-in "$iface" -j RETURN
    del_table_rule_all ip6tables nat shellcrashv6_dns -i "$iface" -j RETURN
    del_table_rule_all ip6tables nat shellcrashv6_dns -m physdev --physdev-in "$iface" -j RETURN
    del_filter_rule_all ip6tables FORWARD -i "$iface" ! -o utun -j ACCEPT
    del_filter_rule_all ip6tables FORWARD -m physdev --physdev-in "$iface" ! -o utun -j ACCEPT
  done
}

add_ipv6_wlan_forward_bypass() {
  command -v ip6tables >/dev/null 2>&1 || return 0
  for iface in $(wlan_bypass_ifaces); do
    ip6tables -C FORWARD -i "$iface" ! -o utun -j ACCEPT >/dev/null 2>&1 ||
      ip6tables -I FORWARD 1 -i "$iface" ! -o utun -j ACCEPT >/dev/null 2>&1 || true
    ip6tables -C FORWARD -m physdev --physdev-in "$iface" ! -o utun -j ACCEPT >/dev/null 2>&1 ||
      ip6tables -I FORWARD 1 -m physdev --physdev-in "$iface" ! -o utun -j ACCEPT >/dev/null 2>&1 || true
  done
}

apply_ipv4() {
  iptables -t mangle -S shellcrash_mark >/dev/null 2>&1 && {
    ipt_chain_reset iptables mangle mm_pre
    add_common_ssid_returns iptables mangle mm_pre
    add_common_device_returns iptables mangle mm_pre
    iptables -t mangle -A mm_pre -m set --match-set mm_force4 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_force_net4 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_suffix4 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m mark --mark "$MARK_HEX" -j RETURN >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct4 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct_net4 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct_suffix4 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct4 dst -j RETURN >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct_net4 dst -j RETURN >/dev/null 2>&1 || true
    iptables -t mangle -A mm_pre -m set --match-set mm_direct_suffix4 dst -j RETURN >/dev/null 2>&1 || true
    [ "$CN_ACCEL" = "1" ] && {
      iptables -t mangle -A mm_pre -m set --match-set mm_cn4 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
      iptables -t mangle -A mm_pre -m set --match-set mm_cn4 dst -j RETURN >/dev/null 2>&1 || true
    }
    iptables -t mangle -A mm_pre -j RETURN >/dev/null 2>&1 || true
    ipt_remove_jump iptables mangle shellcrash_mark mm_pre
    iptables -t mangle -I shellcrash_mark 1 -j mm_pre >/dev/null 2>&1 || true
  }

  iptables -t nat -S shellcrash_dns >/dev/null 2>&1 && {
    ipt_chain_reset iptables nat mm_dns_pre
    add_common_ssid_returns iptables nat mm_dns_pre
    add_common_device_returns iptables nat mm_dns_pre
    iptables -t nat -A mm_dns_pre -j RETURN >/dev/null 2>&1 || true
    ipt_remove_jump iptables nat shellcrash_dns mm_dns_pre
    iptables -t nat -I shellcrash_dns 1 -j mm_dns_pre >/dev/null 2>&1 || true
  }
}

apply_ipv6() {
  command -v ip6tables >/dev/null 2>&1 || return 0
  ip6tables -t mangle -S shellcrashv6_mark >/dev/null 2>&1 && {
    ipt_chain_reset ip6tables mangle mm_v6_pre
    add_common_ssid_returns ip6tables mangle mm_v6_pre
    for item in $(device_mac_values); do
      ip6tables -t mangle -A mm_v6_pre -m mac --mac-source "$item" -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
      ip6tables -t mangle -A mm_v6_pre -m mac --mac-source "$item" -j RETURN >/dev/null 2>&1 || true
    done
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_force6 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_force_net6 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_suffix6 dst -j MARK --set-xmark "$MARK_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m mark --mark "$MARK_HEX" -j RETURN >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct6 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct_net6 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct_suffix6 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct6 dst -j RETURN >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct_net6 dst -j RETURN >/dev/null 2>&1 || true
    ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_direct_suffix6 dst -j RETURN >/dev/null 2>&1 || true
    [ "$CN_ACCEL" = "1" ] && {
      ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_cn6 dst -j MARK --set-xmark "$BYPASS_XHEX" >/dev/null 2>&1 || true
      ip6tables -t mangle -A mm_v6_pre -m set --match-set mm_cn6 dst -j RETURN >/dev/null 2>&1 || true
    }
    ip6tables -t mangle -A mm_v6_pre -j RETURN >/dev/null 2>&1 || true
    ipt_remove_jump ip6tables mangle shellcrashv6_mark mm_v6_pre
    ip6tables -t mangle -I shellcrashv6_mark 1 -j mm_v6_pre >/dev/null 2>&1 || true
  }

  ip6tables -t nat -S shellcrashv6_dns >/dev/null 2>&1 && {
    ipt_chain_reset ip6tables nat mm_v6_dns_pre
    add_common_ssid_returns ip6tables nat mm_v6_dns_pre
    for item in $(device_mac_values); do
      ip6tables -t nat -A mm_v6_dns_pre -m mac --mac-source "$item" -j RETURN >/dev/null 2>&1 || true
    done
    ip6tables -t nat -A mm_v6_dns_pre -j RETURN >/dev/null 2>&1 || true
    ipt_remove_jump ip6tables nat shellcrashv6_dns mm_v6_dns_pre
    ip6tables -t nat -I shellcrashv6_dns 1 -j mm_v6_dns_pre >/dev/null 2>&1 || true
  }
}

apply_firewall() {
  find_usb
  load_state
  get_mark
  ensure_basic_sets
  cleanup_legacy_wlan_rules
  load_device_set
  load_force_sets
  load_direct_sets
  sync_dnsmasq_suffixes
  apply_ipv4
  apply_ipv6
  add_ipv6_wlan_forward_bypass
}

restart_shellcrash() {
  if [ -x /etc/init.d/shellcrash ]; then
    /etc/init.d/shellcrash stop >/tmp/mihomo-manager-shellcrash.log 2>&1 || true
    sleep 2
    /etc/init.d/shellcrash start >>/tmp/mihomo-manager-shellcrash.log 2>&1 || true
    sleep 5
  fi
  /bin/sh /data/router_usb_services.sh >/dev/null 2>&1 || true
}

enable_cn() {
  find_usb
  load_state
  CN_ACCEL=1
  save_state
  set_cfg_value dns_mod route
  set_cfg_value dns_protect ON
  load_cn_sets
  resolve_domains
  log_msg "enable CN acceleration and switch dns_mod=route"
  restart_shellcrash
  apply_firewall
}

disable_cn() {
  find_usb
  load_state
  CN_ACCEL=0
  save_state
  set_cfg_value dns_mod fake-ip
  log_msg "disable CN acceleration and switch dns_mod=fake-ip"
  restart_shellcrash
  apply_firewall
}

start_web() {
  find_usb
  [ -x /usr/sbin/uhttpd ] || return 0
  if netstat -lntup 2>/dev/null | grep -q ":$PORT[[:space:]].*uhttpd"; then
    return 0
  fi
  for f in /proc/[0-9]*/cmdline; do
    cmd="$(tr '\0' ' ' < "$f" 2>/dev/null || true)"
    case "$cmd" in
      *"mihomo-manager/www"*)
        pid="${f#/proc/}"
        pid="${pid%/cmdline}"
        kill "$pid" >/dev/null 2>&1 || true
      ;;
    esac
  done
  uhttpd -f -h "$WWW" -I index.html -x /cgi-bin -p 0.0.0.0:$PORT -t 30 -T 30 >/tmp/mihomo-manager-uhttpd.log 2>&1 &
}

guard() {
  find_usb
  load_state
  start_web
  now="$(date +%s)"
  last_cn="$(cat "$BASE/last_cn_refresh" 2>/dev/null || echo 0)"
  case "$last_cn" in ''|*[!0-9]*) last_cn=0 ;; esac
  if [ "$CN_ACCEL" = "1" ] && [ "$CN_REFRESH_HOURS" != "0" ] && [ $((now - last_cn)) -gt $((CN_REFRESH_HOURS * 3600)) ]; then
    refresh_cn_lists >/dev/null 2>&1 || log_msg "CN list refresh failed"
  fi
  last="$(cat "$BASE/last_domain_refresh" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ -s "$DOMAINS" ] && [ $((now - last)) -gt 600 ]; then
    resolve_domains
  fi
  last_direct="$(cat "$BASE/last_direct_refresh" 2>/dev/null || echo 0)"
  case "$last_direct" in ''|*[!0-9]*) last_direct=0 ;; esac
  if [ -s "$DIRECT_DOMAINS" ] && [ $((now - last_direct)) -gt 600 ]; then
    resolve_direct_domains
  fi
  if device_policy_owners | grep -q .; then
    current_sources="$(device_policy_sources | md5sum | awk '{print $1}')"
    saved_sources="$(cat "$BASE/device_policy_sources.md5" 2>/dev/null)"
    if [ "$current_sources" != "$saved_sources" ]; then
      apply_device_policies >/dev/null 2>&1 || log_msg "device policy source refresh failed"
    fi
  fi
  apply_firewall
}

json_escape() {
  tr -d '\001-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url_path_encode() {
  printf '%s' "$1" | hexdump -ve '1/1 "%02x"' | sed 's/../%&/g' | tr 'a-f' 'A-F'
}

json_file_array() {
  file="$1"
  printf '['
  first=1
  while IFS= read -r line; do
    line="$(printf '%s\n' "$line" | tr -d '\r')"
    [ -z "$line" ] && continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '"%s"' "$(printf '%s' "$line" | json_escape)"
  done < "$file"
  printf ']'
}

json_wlan_array() {
  printf '['
  first=1
  wlan_list | while IFS='|' read -r iface label ssid; do
    [ -n "$iface" ] || continue
    bypass=false
    file_has_line "$WLAN_BYPASS" "$iface" && bypass=true
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"iface":"%s","label":"%s","ssid":"%s","mode":"%s","bypass":%s}' \
      "$(printf '%s' "$iface" | json_escape)" \
      "$(printf '%s' "$label" | json_escape)" \
      "$(printf '%s' "$ssid" | json_escape)" \
      "$([ "$bypass" = true ] && echo bypass || echo mihomo)" \
      "$bypass"
  done
  printf ']'
}

json_tail_array() {
  file="$1"
  lines="$2"
  tmp="/tmp/mm_json_tail.$$"
  case "$lines" in ''|*[!0-9]*) lines=20 ;; esac
  if [ -f "$file" ]; then
    tail -n "$lines" "$file" 2>/dev/null > "$tmp" || : > "$tmp"
  else
    : > "$tmp"
  fi
  json_file_array "$tmp"
  rm -f "$tmp"
}

valid_filename() {
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9._-]+$'
}

config_sanity_ok() {
  file="$1"
  [ -s "$file" ] &&
    grep -q '^proxies:' "$file" &&
    grep -q '^proxy-groups:' "$file" &&
    grep -q '^rules:' "$file"
}

make_config_backup_file() {
  reason="$1"
  TS="$(date '+%Y%m%d-%H%M%S')"
  out="$BACKUPS/mihomo-backup-$TS.tar.gz"
  tmpdir="/tmp/mihomo-manager-backup.$$"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/manager" "$tmpdir/shellcrash" "$tmpdir/sub-store"
  [ -f "$CRASHDIR/yamls/config.yaml" ] && cp -p "$CRASHDIR/yamls/config.yaml" "$tmpdir/shellcrash/config.yaml"
  [ -f "$CRASHDIR/configs/ShellCrash.cfg" ] && cp -p "$CRASHDIR/configs/ShellCrash.cfg" "$tmpdir/shellcrash/ShellCrash.cfg"
  [ -f "$STATE" ] && cp -p "$STATE" "$tmpdir/manager/state.conf"
  [ -f "$DEVICES" ] && cp -p "$DEVICES" "$tmpdir/manager/device_bypass.list"
  [ -f "$DOMAINS" ] && cp -p "$DOMAINS" "$tmpdir/manager/force_domains.list"
  [ -f "$SUFFIXES" ] && cp -p "$SUFFIXES" "$tmpdir/manager/force_suffixes.list"
  [ -f "$FORCE_NETS" ] && cp -p "$FORCE_NETS" "$tmpdir/manager/force_nets.list"
  [ -f "$DIRECT_DOMAINS" ] && cp -p "$DIRECT_DOMAINS" "$tmpdir/manager/direct_domains.list"
  [ -f "$DIRECT_SUFFIXES" ] && cp -p "$DIRECT_SUFFIXES" "$tmpdir/manager/direct_suffixes.list"
  [ -f "$DIRECT_NETS" ] && cp -p "$DIRECT_NETS" "$tmpdir/manager/direct_nets.list"
  [ -f "$DEVICE_POLICIES" ] && cp -p "$DEVICE_POLICIES" "$tmpdir/manager/device_policies.list"
  [ -f "$DEVICE_RULES" ] && cp -p "$DEVICE_RULES" "$tmpdir/manager/device_rules.list"
  [ -f "$DEVICE_PORT_RULES" ] && cp -p "$DEVICE_PORT_RULES" "$tmpdir/manager/device_port_rules.list"
  [ -f "$GLOBAL_RULES" ] && cp -p "$GLOBAL_RULES" "$tmpdir/manager/global_rules.list"
  [ -f "$CRASHDIR/yamls/user.yaml" ] && cp -p "$CRASHDIR/yamls/user.yaml" "$tmpdir/shellcrash/user.yaml"
  [ -f "$CRASHDIR/yamls/rules.yaml" ] && cp -p "$CRASHDIR/yamls/rules.yaml" "$tmpdir/shellcrash/rules.yaml"
  [ -f "$CRASHDIR/yamls/proxy-groups.yaml" ] && cp -p "$CRASHDIR/yamls/proxy-groups.yaml" "$tmpdir/shellcrash/proxy-groups.yaml"
  [ -f "$URLS" ] && cp -p "$URLS" "$tmpdir/manager/profile_urls.list"
  [ -f "$SYNC_CONF" ] && cp -p "$SYNC_CONF" "$tmpdir/manager/substore_profile_sync.conf"
  [ -f "$USB/services/subs-check/output/sub-store.json" ] && cp -p "$USB/services/subs-check/output/sub-store.json" "$tmpdir/sub-store/sub-store.json"
  {
    echo "created=$(date '+%F %T')"
    echo "reason=$reason"
    echo "profile_url=$(current_profile_url)"
  } > "$tmpdir/README.txt"
  tar -czf "$out" -C "$tmpdir" . >/dev/null 2>&1 || {
    rm -rf "$tmpdir" "$out"
    return 1
  }
  rm -rf "$tmpdir"
  echo "$out"
}

backups_json() {
  find_usb
  printf '['
  first=1
  ls -t "$BACKUPS"/*.tar.gz 2>/dev/null | head -20 | while IFS= read -r file; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    size="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"name":"%s","size":%s}' "$(printf '%s' "$name" | json_escape)" "${size:-0}"
  done
  printf ']'
}

backup_config_json() {
  find_usb
  if out="$(make_config_backup_file "manual")"; then
    size="$(wc -c < "$out" 2>/dev/null | tr -d ' ')"
    log_msg "create backup $(basename "$out")"
    cgi_reply "200 OK" "{\"ok\":true,\"name\":\"$(basename "$out" | json_escape)\",\"size\":${size:-0}}"
  else
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"backup failed"}'
  fi
}

download_current_config() {
  find_usb
  file="$CRASHDIR/yamls/config.yaml"
  [ -f "$file" ] || {
    cgi_reply "404 Not Found" '{"ok":false,"error":"config not found"}'
    return
  }
  name="mihomo-config-$(date '+%Y%m%d-%H%M%S').yaml"
  printf 'Content-Type: application/x-yaml; charset=utf-8\r\n'
  printf 'Content-Disposition: attachment; filename="%s"\r\n' "$name"
  printf 'Cache-Control: no-store\r\n\r\n'
  cat "$file"
}

download_backup() {
  find_usb
  name="$(basename "$1")"
  valid_filename "$name" || {
    cgi_reply "400 Bad Request" '{"ok":false,"error":"bad backup name"}'
    return
  }
  file="$BACKUPS/$name"
  [ -f "$file" ] || {
    cgi_reply "404 Not Found" '{"ok":false,"error":"backup not found"}'
    return
  }
  printf 'Content-Type: application/gzip\r\n'
  printf 'Content-Disposition: attachment; filename="%s"\r\n' "$name"
  printf 'Cache-Control: no-store\r\n\r\n'
  cat "$file"
}

import_config_b64() {
  find_usb
  tmp="/tmp/mihomo-manager-import.yaml.$$"
  new_config="$CRASHDIR/yamls/config.yaml.import.$$"
  test_log="/tmp/mihomo-manager-import-test.$$.log"
  printf '%s' "$1" | base64 -d > "$tmp" 2>/tmp/mihomo-manager-import-decode.log || {
    rm -f "$tmp" "$test_log" "$new_config"
    cgi_reply "400 Bad Request" '{"ok":false,"error":"base64 decode failed"}'
    return
  }
  config_sanity_ok "$tmp" || {
    rm -f "$tmp" "$test_log" "$new_config"
    cgi_reply "400 Bad Request" '{"ok":false,"error":"basic sanity check failed"}'
    return
  }
  if [ -x /tmp/ShellCrash/CrashCore ]; then
    if ! /tmp/ShellCrash/CrashCore -t -d "$CRASHDIR" -f "$tmp" >"$test_log" 2>&1; then
      printf 'Status: 400 Bad Request\r\n'
      printf 'Content-Type: application/json; charset=utf-8\r\n'
      printf 'Access-Control-Allow-Origin: *\r\n'
      printf 'Cache-Control: no-store\r\n\r\n'
      printf '{"ok":false,"error":"mihomo config test failed","test_log":'
      json_tail_array "$test_log" 30
      printf '}'
      rm -f "$tmp" "$new_config"
      return
    fi
  fi
  before="$(make_config_backup_file "before-import")" || {
    rm -f "$tmp" "$test_log" "$new_config"
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"backup before import failed"}'
    return
  }
  if ! cp -f "$tmp" "$new_config"; then
    rm -f "$tmp" "$test_log" "$new_config"
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"write config failed"}'
    return
  fi
  if ! mv -f "$new_config" "$CRASHDIR/yamls/config.yaml"; then
    rm -f "$tmp" "$test_log" "$new_config"
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"replace config failed"}'
    return
  fi
  rm -f "$tmp" "$test_log"
  restart_shellcrash
  apply_firewall
  i=0
  while [ "$i" -lt 5 ] && ! pidof CrashCore >/dev/null 2>&1; do
    sleep 1
    i=$((i + 1))
  done
  if pidof CrashCore >/dev/null 2>&1; then
    log_msg "import config ok backup=$(basename "$before")"
    cgi_reply "200 OK" "{\"ok\":true,\"backup\":\"$(basename "$before" | json_escape)\"}"
  else
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"CrashCore not running after import"}'
  fi
}

device_bypass_bool() {
  ip="$1"
  mac="$2"
  result=false
  [ -n "$ip" ] && ipset test mm_device4 "$ip" >/dev/null 2>&1 && result=true
  [ -n "$mac" ] && file_has_line "$DEVICES" "$mac" && result=true
  echo "$result"
}

online_devices_json() {
  find_usb
  ensure_basic_sets
  load_device_set
  raw="/tmp/mihomo-manager-devices.raw.$$"
  merged="/tmp/mihomo-manager-devices.merged.$$"
  : > "$raw"
  now="$(date +%s)"
  awk -v now="$now" '
    $1 ~ /^[0-9]+$/ && $3 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $1 > now {
      host=$4; if (host=="*" || host=="") host="-";
      print $3 "|" tolower($2) "|" host "|dhcp|lease"
    }
  ' /tmp/dhcp.leases 2>/dev/null >> "$raw"
  awk 'NR>1 && $6=="br-lan" && $4!="00:00:00:00:00:00" && $3=="0x2" {print $1 "|" tolower($4) "|-|arp|reachable"}' /proc/net/arp 2>/dev/null >> "$raw"
  ip neigh show dev br-lan 2>/dev/null | awk '
    $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $0 !~ /FAILED/ {
      mac="-"; state=$NF;
      for (i=1;i<=NF;i++) if ($i=="lladdr") mac=$(i+1);
      if (mac != "-") print $1 "|" tolower(mac) "|-|neigh|" state
    }
  ' >> "$raw"
  awk -F'|' '
    {
      ip=$1
      if (!seen[ip]++) order[++n]=ip
      if ($2 != "" && $2 != "-") mac[ip]=$2
      if ($3 != "" && $3 != "-") host[ip]=$3
      if ($4 != "") source[ip]=(source[ip] ? source[ip] "," $4 : $4)
      if ($5 != "") state[ip]=$5
    }
    END {
      for (i=1;i<=n;i++) {
        ip=order[i]
        print ip "|" mac[ip] "|" host[ip] "|" source[ip] "|" state[ip]
      }
    }
  ' "$raw" > "$merged"
  printf '['
  first=1
  while IFS='|' read -r ip mac host source state; do
    [ -n "$ip" ] || continue
    bypass="$(device_bypass_bool "$ip" "$mac")"
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"ip":"%s","mac":"%s","host":"%s","source":"%s","state":"%s","bypass":%s}' \
      "$(printf '%s' "$ip" | json_escape)" \
      "$(printf '%s' "$mac" | json_escape)" \
      "$(printf '%s' "$host" | json_escape)" \
      "$(printf '%s' "$source" | json_escape)" \
      "$(printf '%s' "$state" | json_escape)" \
      "$bypass"
  done < "$merged"
  printf ']'
  rm -f "$raw" "$merged"
}

set_device_bypass_value() {
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  mac="$(norm_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  enabled="$(trim_value "$(printf '%s\n' "$input" | sed -n '3p')")"
  [ "$enabled" = "1" ] || [ "$enabled" = "0" ] || return 1
  if [ "$enabled" = "1" ]; then
    if valid_mac "$mac"; then
      add_unique_line "$DEVICES" "$mac"
      log_msg "device bypass on $ip $mac"
    elif valid_ipv4_or_cidr "$ip"; then
      add_unique_line "$DEVICES" "$ip"
      log_msg "device bypass on $ip"
    else
      return 1
    fi
  else
    changed=0
    valid_mac "$mac" && { del_line "$DEVICES" "$mac"; changed=1; }
    valid_ipv4_or_cidr "$ip" && { del_line "$DEVICES" "$ip"; changed=1; }
    [ "$changed" = 1 ] || return 1
    log_msg "device bypass off $ip $mac"
  fi
  apply_firewall
}

rule_test_json() {
  input="$1"
  target="$(printf '%s\n' "$input" | sed -n '1p')"
  source="$(printf '%s\n' "$input" | sed -n '2p')"
  target="$(normalize_target "$target")"
  source="$(norm_value "$source")"
  if [ -z "$target" ]; then
    cgi_reply "400 Bad Request" '{"ok":false,"error":"empty target"}'
    return
  fi
  find_usb
  load_state
  get_mark
  ensure_basic_sets
  load_device_set
  load_force_sets
  load_direct_sets
  sync_dnsmasq_suffixes
  local_ips="/tmp/mm_rule_local.$$"
  public_ips="/tmp/mm_rule_public.$$"
  all_ips="/tmp/mm_rule_all.$$"
  reasons="/tmp/mm_rule_reasons.$$"
  : > "$local_ips"; : > "$public_ips"; : > "$all_ips"; : > "$reasons"

  target_type=ip
  if valid_ip_or_cidr "$target"; then
    echo "$target" > "$all_ips"
  elif valid_domain "$target"; then
    target_type=domain
    resolve_host_file "$target" "127.0.0.1" "$local_ips"
    resolve_host_file "$target" "223.5.5.5" "$public_ips"
    cat "$local_ips" "$public_ips" 2>/dev/null | sort -u > "$all_ips"
  else
    cgi_reply "400 Bad Request" '{"ok":false,"error":"bad target"}'
    rm -f "$local_ips" "$public_ips" "$all_ips" "$reasons"
    return
  fi

  source_bypass=false
  if valid_mac "$source"; then
    file_has_line "$DEVICES" "$source" && source_bypass=true
  elif valid_ipv4_or_cidr "$source"; then
    ipset test mm_device4 "$source" >/dev/null 2>&1 && source_bypass=true
  fi
  [ "$source_bypass" = true ] && echo "源设备命中绕过列表，整机不进 Mihomo" >> "$reasons"

  force_domain=false
  direct_domain=false
  force_suffix=""
  direct_suffix=""
  force_hit=false
  direct_hit=false
  cn_hit=false
  if [ "$target_type" = domain ]; then
    file_has_line "$DOMAINS" "$target" && { force_domain=true; echo "目标在强制进入完整域名列表" >> "$reasons"; }
    file_has_line "$DIRECT_DOMAINS" "$target" && { direct_domain=true; echo "目标在强制直连完整域名列表" >> "$reasons"; }
    force_suffix="$(first_suffix_match "$SUFFIXES" "$target")"
    direct_suffix="$(first_suffix_match "$DIRECT_SUFFIXES" "$target")"
    [ -n "$force_suffix" ] && echo "目标在强制进入后缀列表 $force_suffix" >> "$reasons"
    [ -n "$direct_suffix" ] && echo "目标在强制直连后缀列表 $direct_suffix" >> "$reasons"
  fi

  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    case "$ip" in
      *:*)
        ipset test mm_force6 "$ip" >/dev/null 2>&1 && { force_hit=true; echo "目标 IP 命中强制进入 $ip" >> "$reasons"; }
        ipset test mm_force_net6 "$ip" >/dev/null 2>&1 && { force_hit=true; echo "目标 IP 命中强制进入 CIDR $ip" >> "$reasons"; }
        ipset test mm_direct6 "$ip" >/dev/null 2>&1 && { direct_hit=true; echo "目标 IP 命中强制直连 $ip" >> "$reasons"; }
        ipset test mm_direct_net6 "$ip" >/dev/null 2>&1 && { direct_hit=true; echo "目标 IP 命中强制直连 CIDR $ip" >> "$reasons"; }
        [ "$CN_ACCEL" = "1" ] && ipset test mm_cn6 "$ip" >/dev/null 2>&1 && { cn_hit=true; echo "目标 IP 命中 CN IP 前置直连 $ip" >> "$reasons"; }
      ;;
      *)
        ipset test mm_force4 "$ip" >/dev/null 2>&1 && { force_hit=true; echo "目标 IP 命中强制进入 $ip" >> "$reasons"; }
        ipset test mm_force_net4 "$ip" >/dev/null 2>&1 && { force_hit=true; echo "目标 IP 命中强制进入 CIDR $ip" >> "$reasons"; }
        ipset test mm_direct4 "$ip" >/dev/null 2>&1 && { direct_hit=true; echo "目标 IP 命中强制直连 $ip" >> "$reasons"; }
        ipset test mm_direct_net4 "$ip" >/dev/null 2>&1 && { direct_hit=true; echo "目标 IP 命中强制直连 CIDR $ip" >> "$reasons"; }
        [ "$CN_ACCEL" = "1" ] && ipset test mm_cn4 "$ip" >/dev/null 2>&1 && { cn_hit=true; echo "目标 IP 命中 CN IP 前置直连 $ip" >> "$reasons"; }
      ;;
    esac
  done < "$all_ips"

  if [ "$source_bypass" = true ]; then
    verdict="不进 Mihomo（源设备绕过）"
  elif [ "$force_hit" = true ]; then
    verdict="进 Mihomo（强制进入优先）"
  elif [ "$direct_hit" = true ]; then
    verdict="不进 Mihomo（强制直连）"
  elif [ "$cn_hit" = true ]; then
    verdict="不进 Mihomo（CN IP 前置直连）"
  else
    verdict="进 Mihomo（交给 Mihomo 内部规则继续分流）"
    echo "未命中前置规则" >> "$reasons"
  fi

  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '{"ok":true,'
  printf '"target":"%s","target_type":"%s","source":"%s","source_bypass":%s,' \
    "$(printf '%s' "$target" | json_escape)" "$target_type" "$(printf '%s' "$source" | json_escape)" "$source_bypass"
  printf '"force_domain":%s,"force_suffix":"%s","direct_domain":%s,"direct_suffix":"%s",' \
    "$force_domain" "$(printf '%s' "$force_suffix" | json_escape)" "$direct_domain" "$(printf '%s' "$direct_suffix" | json_escape)"
  printf '"verdict":"%s","reasons":' "$(printf '%s' "$verdict" | json_escape)"
  json_file_array "$reasons"
  printf ',"local_ips":'
  json_file_array "$local_ips"
  printf ',"public_ips":'
  json_file_array "$public_ips"
  printf ',"checks":'
  json_ip_checks "$all_ips"
  printf '}'
  rm -f "$local_ips" "$public_ips" "$all_ips" "$reasons"
}

mihomo_proxies_json() {
  body="$(curl -fsS --connect-timeout 3 --max-time 8 -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/proxies" 2>/tmp/mihomo-manager-proxies.log)" || {
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"mihomo api failed"}'
    return
  }
  [ -n "$body" ] || {
    cgi_reply "500 Internal Server Error" '{"ok":false,"error":"mihomo api empty response"}'
    return
  }
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '{"ok":true,"data":'
  printf '%s' "$body"
  printf '}'
}

set_proxy_group_json() {
  input="$1"
  group="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  target="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  [ -n "$group" ] && [ -n "$target" ] || {
    cgi_reply "400 Bad Request" '{"ok":false,"error":"empty group or target"}'
    return
  }
  group_path="$(url_path_encode "$group")"
  body="$(printf '{"name":"%s"}' "$(printf '%s' "$target" | json_escape)")"
  if curl -fsS --connect-timeout 3 --max-time 8 -X PUT \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --data "$body" "$MIHOMO_API/proxies/$group_path" >/tmp/mihomo-manager-set-proxy.log 2>&1; then
    log_msg "set proxy group $group -> $target"
    cgi_reply "200 OK" '{"ok":true}'
  else
    printf 'Status: 500 Internal Server Error\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf '{"ok":false,"error":"set proxy group failed","log":'
    json_tail_array /tmp/mihomo-manager-set-proxy.log 20
    printf '}'
  fi
}

device_rule_name() {
  printf 'mm-device-%s' "$(printf '%s' "$1" | tr '.' '-')"
}

device_group_name() {
  printf '设备策略-%s' "$1"
}

yaml_single_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

valid_policy_target() {
  local target proxies
  target="$1"
  [ "$target" = "INHERIT" ] && return 0
  [ -n "$target" ] || return 1
  printf '%s\n' "$target" | grep -q '[,[:cntrl:]]' && return 1
  case "$target" in DIRECT|REJECT|REJECT-DROP|PASS) return 0 ;; esac
  if [ -z "$POLICY_TARGETS_CACHE" ] || [ ! -s "$POLICY_TARGETS_CACHE" ]; then
    POLICY_TARGETS_CACHE="/tmp/mm-policy-targets.$$"
    proxies="$(curl -fsS --connect-timeout 3 --max-time 8 -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/proxies" 2>/dev/null)" || return 1
    printf '%s' "$proxies" | jsonfilter -e '@.proxies.*.name' 2>/dev/null > "$POLICY_TARGETS_CACHE"
    [ -s "$POLICY_TARGETS_CACHE" ] || return 1
  fi
  grep -Fxq "$target" "$POLICY_TARGETS_CACHE"
}

strip_managed_device_block() {
  local src dst begin end
  src="$1"
  dst="$2"
  begin="$3"
  end="$4"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$src" 2>/dev/null > "$dst"
}

device_policy_owners() {
  {
    awk -F '\t' 'NF >= 3 && $1 != "" && $3 != "INHERIT" {print $1}' "$DEVICE_POLICIES" 2>/dev/null
    awk -F '\t' 'NF >= 4 && $1 != "" {print $1}' "$DEVICE_RULES" 2>/dev/null
    awk -F '\t' 'NF >= 4 && $1 != "" {print $1}' "$DEVICE_PORT_RULES" 2>/dev/null
  } | awk '!seen[$0]++'
}

device_policy_sources() {
  local tmp owner mac
  tmp="/tmp/mm-device-sources.$$"
  : > "$tmp"
  device_policy_owners | while IFS= read -r owner; do
    [ -n "$owner" ] || continue
    printf '%s\t%s\n' "$owner" "$owner"
    mac="$(awk -F '\t' -v ip="$owner" '$1 == ip {print $4; exit}' "$DEVICE_POLICIES" 2>/dev/null)"
    valid_mac "$mac" || continue
    ip -6 neigh show dev br-lan 2>/dev/null | awk -v owner="$owner" -v mac="$mac" '
      tolower($0) ~ "lladdr " tolower(mac) && $1 ~ /:/ && $1 !~ /^fe80:/ && $0 !~ /FAILED/ {print $1 "\t" owner}
    '
  done | sort -u > "$tmp"
  cat "$tmp"
  rm -f "$tmp"
}

device_default_target() {
  awk -F '\t' -v ip="$1" '$1 == ip {print $3; exit}' "$DEVICE_POLICIES" 2>/dev/null
}

validate_device_policy_data() {
  local ip label target mac type match port_type port
  while IFS="$(printf '\t')" read -r ip label target mac; do
    [ -n "$ip" ] || continue
    valid_ipv4_or_cidr "$ip" || return 1
    printf '%s' "$ip" | grep -q '/' && return 1
    valid_policy_target "$target" || return 1
    [ -z "$mac" ] || valid_mac "$mac" || return 1
  done < "$DEVICE_POLICIES"
  while IFS="$(printf '\t')" read -r ip type match target; do
    [ -n "$ip" ] || continue
    valid_ipv4_or_cidr "$ip" || return 1
    printf '%s' "$ip" | grep -q '/' && return 1
    case "$type" in DOMAIN|DOMAIN-SUFFIX) ;; *) return 1 ;; esac
    valid_domain "$match" || return 1
    valid_policy_target "$target" || return 1
    [ "$target" != "INHERIT" ] || return 1
  done < "$DEVICE_RULES"
  while IFS="$(printf '\t')" read -r ip port_type port target; do
    [ -n "$ip" ] || continue
    valid_ipv4_or_cidr "$ip" || return 1
    printf '%s' "$ip" | grep -q '/' && return 1
    case "$port_type" in IN-PORT|DST-PORT) ;; *) return 1 ;; esac
    valid_port_spec "$port" || return 1
    valid_policy_target "$target" || return 1
    [ "$target" != "INHERIT" ] || return 1
  done < "$DEVICE_PORT_RULES"
}

validate_global_rule_data() {
  local type match target
  while IFS="$(printf '\t')" read -r type match target; do
    [ -n "$type" ] || continue
    case "$type" in DOMAIN|DOMAIN-SUFFIX) ;; *) return 1 ;; esac
    valid_domain "$match" || return 1
    valid_policy_target "$target" || return 1
    [ "$target" != "INHERIT" ] || return 1
  done < "$GLOBAL_RULES"
}

write_global_rules_yaml() {
  local out type match target rule
  out="$1"
  while IFS="$(printf '\t')" read -r type match target; do
    [ -n "$type" ] || continue
    rule="$type,$match,$target"
    printf "- '%s'\n" "$(yaml_single_quote "$rule")" >> "$out"
  done < "$GLOBAL_RULES"
}

write_device_subrules_yaml() {
  local out ips ip name type match target rule port_type port
  out="$1"
  ips="/tmp/mm-device-ips.$$"
  device_policy_owners > "$ips"
  [ -s "$ips" ] || { rm -f "$ips"; return 0; }
  echo 'sub-rules:' >> "$out"
  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    name="$(device_rule_name "$ip")"
    printf '  %s:\n' "$name" >> "$out"
    awk -F '\t' -v ip="$ip" '$1 == ip {print $2 "\t" $3 "\t" $4}' "$DEVICE_RULES" 2>/dev/null |
      while IFS="$(printf '\t')" read -r type match target; do
        [ -n "$type" ] || continue
        rule="$type,$match,$target"
        printf "    - '%s'\n" "$(yaml_single_quote "$rule")" >> "$out"
      done
    awk -F '\t' -v ip="$ip" '$1 == ip {print $2 "\t" $3 "\t" $4}' "$DEVICE_PORT_RULES" 2>/dev/null |
      while IFS="$(printf '\t')" read -r port_type port target; do
        [ -n "$port_type" ] || continue
        rule="$port_type,$port,$target"
        printf "    - '%s'\n" "$(yaml_single_quote "$rule")" >> "$out"
      done
    target="$(device_default_target "$ip")"
    if [ -n "$target" ] && [ "$target" != "INHERIT" ]; then
      rule="MATCH,$(device_group_name "$ip")"
      printf "    - '%s'\n" "$(yaml_single_quote "$rule")" >> "$out"
    fi
  done < "$ips"
  rm -f "$ips"
}

write_device_groups_yaml() {
  local out ip label target mac group candidate group_names
  group_names="/tmp/mm-device-group-names.$$"
  awk '
    /^proxy-groups:/ {inside=1; next}
    inside && /^[^ ]/ {exit}
    inside && /^  - name:/ {
      line=$0
      sub(/^  - name:[[:space:]]*/, "", line)
      gsub(/^['\''"]|['\''"]$/, "", line)
      print line
    }
  ' "$CRASHDIR/yamls/config.yaml" 2>/dev/null > "$group_names"
  out="$1"
  while IFS="$(printf '\t')" read -r ip label target mac; do
    [ -n "$ip" ] && [ "$target" != "INHERIT" ] || continue
    group="$(device_group_name "$ip")"
    printf "  - name: '%s'\n" "$(yaml_single_quote "$group")" >> "$out"
    printf '    type: select\n' >> "$out"
    printf '    proxies:\n' >> "$out"
    printf "      - '%s'\n" "$(yaml_single_quote "$target")" >> "$out"
    [ "$target" = "DIRECT" ] || printf '      - DIRECT\n' >> "$out"
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      [ "$candidate" = "$target" ] && continue
      [ "$candidate" = "$group" ] && continue
      case "$candidate" in 设备策略-*) continue ;; esac
      printf "      - '%s'\n" "$(yaml_single_quote "$candidate")" >> "$out"
    done < "$group_names"
    printf '    include-all-proxies: true\n' >> "$out"
    printf '    hidden: false\n' >> "$out"
  done < "$DEVICE_POLICIES"
  rm -f "$group_names"
}

strip_device_policy_from_config() {
  local src dst
  src="$1"
  dst="$2"
  awk '
    /^# BEGIN MIHOMO MANAGER DEVICE SUB-RULES$/ {skip_managed_sub=1; next}
    skip_managed_sub && /^# END MIHOMO MANAGER DEVICE SUB-RULES$/ {skip_managed_sub=0; next}
    skip_managed_sub {next}
    /^# BEGIN MIHOMO MANAGER DEVICE RULES$/ {skip_managed_rules=1; next}
    skip_managed_rules && /^# END MIHOMO MANAGER DEVICE RULES$/ {skip_managed_rules=0; next}
    skip_managed_rules {next}
    /^# BEGIN MIHOMO MANAGER DEVICE GROUPS$/ {skip_managed_groups=1; next}
    skip_managed_groups && /^# END MIHOMO MANAGER DEVICE GROUPS$/ {skip_managed_groups=0; next}
    skip_managed_groups {next}
    /^ *# BEGIN MIHOMO MANAGER GLOBAL RULE OVERRIDES$/ {skip_global_rules=1; next}
    skip_global_rules && /^ *# END MIHOMO MANAGER GLOBAL RULE OVERRIDES$/ {skip_global_rules=0; next}
    skip_global_rules {next}
    /^sub-rules:/ {in_sub=1; next}
    in_sub && /^[^ ]/ {in_sub=0}
    in_sub {next}

    /^proxy-groups:/ {in_groups=1; print; next}
    in_groups && /^  - name:[[:space:]]*['\''"]?设备策略-/ {skip_group=1; next}
    skip_group && /^  - name:/ {skip_group=0}
    skip_group {next}
    in_groups && /^[^ ]/ {in_groups=0}

    /SUB-RULE,\(SRC-IP-CIDR,[^)]*\),mm-device-/ {next}
    {print}
  ' "$src" > "$dst"
}

write_device_main_rules() {
  local out source owner cidr
  out="$1"
  device_policy_sources | while IFS="$(printf '\t')" read -r source owner; do
    [ -n "$source" ] && [ -n "$owner" ] || continue
    case "$source" in *:*) cidr="$source/128" ;; *) cidr="$source/32" ;; esac
    printf -- "- 'SUB-RULE,(SRC-IP-CIDR,%s),%s'\n" "$cidr" "$(device_rule_name "$owner")" >> "$out"
  done
}

write_managed_main_rules() {
  local out
  out="$1"
  if device_policy_owners | grep -q .; then
    printf '# BEGIN MIHOMO MANAGER DEVICE RULES\n' >> "$out"
    write_device_main_rules "$out"
    printf '# END MIHOMO MANAGER DEVICE RULES\n' >> "$out"
  fi
  if grep -q . "$GLOBAL_RULES" 2>/dev/null; then
    printf '# BEGIN MIHOMO MANAGER GLOBAL RULE OVERRIDES\n' >> "$out"
    write_global_rules_yaml "$out"
    printf '# END MIHOMO MANAGER GLOBAL RULE OVERRIDES\n' >> "$out"
  fi
}

build_device_policy_files() {
  local user_out rules_out groups_out user_base rules_no_device rules_base groups_base tmp_rules tmp_global_rules tmp_groups
  user_out="$1"
  rules_out="$2"
  groups_out="$3"
  user_base="/tmp/mm-device-user-base.$$"
  rules_no_device="/tmp/mm-device-rules-no-device.$$"
  rules_base="/tmp/mm-device-rules-base.$$"
  groups_base="/tmp/mm-device-groups-base.$$"
  strip_managed_device_block "$CRASHDIR/yamls/user.yaml" "$user_base" '# BEGIN MIHOMO MANAGER DEVICE SUB-RULES' '# END MIHOMO MANAGER DEVICE SUB-RULES'
  strip_managed_device_block "$CRASHDIR/yamls/rules.yaml" "$rules_no_device" '# BEGIN MIHOMO MANAGER DEVICE RULES' '# END MIHOMO MANAGER DEVICE RULES'
  strip_managed_device_block "$rules_no_device" "$rules_base" '# BEGIN MIHOMO MANAGER GLOBAL RULE OVERRIDES' '# END MIHOMO MANAGER GLOBAL RULE OVERRIDES'
  strip_managed_device_block "$CRASHDIR/yamls/proxy-groups.yaml" "$groups_base" '# BEGIN MIHOMO MANAGER DEVICE GROUPS' '# END MIHOMO MANAGER DEVICE GROUPS'
  cp -f "$user_base" "$user_out"
  cp -f "$rules_base" "$rules_out"
  cp -f "$groups_base" "$groups_out"
  if grep -q . "$GLOBAL_RULES" 2>/dev/null; then
    tmp_global_rules="/tmp/mm-global-rules-managed.$$"
    printf '# BEGIN MIHOMO MANAGER GLOBAL RULE OVERRIDES\n' > "$tmp_global_rules"
    write_global_rules_yaml "$tmp_global_rules"
    printf '# END MIHOMO MANAGER GLOBAL RULE OVERRIDES\n' >> "$tmp_global_rules"
    cat "$rules_out" >> "$tmp_global_rules"
    mv -f "$tmp_global_rules" "$rules_out"
  fi
  if device_policy_owners | grep -q .; then
    printf '\n# BEGIN MIHOMO MANAGER DEVICE SUB-RULES\n' >> "$user_out"
    write_device_subrules_yaml "$user_out"
    printf '# END MIHOMO MANAGER DEVICE SUB-RULES\n' >> "$user_out"
    tmp_rules="/tmp/mm-device-rules-managed.$$"
    printf '# BEGIN MIHOMO MANAGER DEVICE RULES\n' > "$tmp_rules"
    write_device_main_rules "$tmp_rules"
    printf '# END MIHOMO MANAGER DEVICE RULES\n' >> "$tmp_rules"
    cat "$rules_out" >> "$tmp_rules"
    mv -f "$tmp_rules" "$rules_out"
  fi
  if awk -F '\t' 'NF >= 3 && $3 != "INHERIT" {found=1} END {exit !found}' "$DEVICE_POLICIES" 2>/dev/null; then
    tmp_groups="/tmp/mm-device-groups-managed.$$"
    printf '# BEGIN MIHOMO MANAGER DEVICE GROUPS\n' > "$tmp_groups"
    write_device_groups_yaml "$tmp_groups"
    printf '# END MIHOMO MANAGER DEVICE GROUPS\n' >> "$tmp_groups"
    cat "$groups_out" >> "$tmp_groups"
    mv -f "$tmp_groups" "$groups_out"
  fi
  rm -f "$user_base" "$rules_no_device" "$rules_base" "$groups_base"
}

build_device_policy_test_config() {
  local out sub main groups clean
  out="$1"
  sub="/tmp/mm-device-subrules.$$"
  main="/tmp/mm-device-mainrules.$$"
  groups="/tmp/mm-device-groups.$$"
  clean="/tmp/mm-device-config-clean.$$"
  : > "$sub"
  : > "$main"
  : > "$groups"
  write_device_subrules_yaml "$sub"
  write_managed_main_rules "$main"
  write_device_groups_yaml "$groups"
  strip_device_policy_from_config "$CRASHDIR/yamls/config.yaml" "$clean"
  awk -v sub_file="$sub" -v main_file="$main" -v groups_file="$groups" '
    /^proxy-groups:/ && !groups_done {
      print
      while ((getline line < groups_file) > 0) print line
      close(groups_file)
      groups_done=1
      next
    }
    /^rules:/ && !done {
      while ((getline line < sub_file) > 0) print line
      close(sub_file)
      print
      while ((getline line < main_file) > 0) print "  " line
      close(main_file)
      done=1
      next
    }
    {print}
  ' "$clean" > "$out"
  rm -f "$sub" "$main" "$groups" "$clean"
}

build_device_policy_runtime_config() {
  local out sub main groups clean
  out="$1"
  sub="/tmp/mm-device-runtime-subrules.$$"
  main="/tmp/mm-device-runtime-mainrules.$$"
  groups="/tmp/mm-device-runtime-groups.$$"
  clean="/tmp/mm-device-runtime-clean.$$"
  : > "$sub"
  : > "$main"
  : > "$groups"
  write_device_subrules_yaml "$sub"
  write_managed_main_rules "$main"
  write_device_groups_yaml "$groups"
  strip_device_policy_from_config /tmp/ShellCrash/config.yaml "$clean"
  awk -v sub_file="$sub" -v main_file="$main" -v groups_file="$groups" '
    /^proxy-groups:/ && !groups_done {
      print
      while ((getline line < groups_file) > 0) print line
      close(groups_file)
      groups_done=1
      next
    }
    /^rules:/ && !done {
      while ((getline line < sub_file) > 0) print line
      close(sub_file)
      print
      while ((getline line < main_file) > 0) print " " line
      close(main_file)
      done=1
      next
    }
    {print}
  ' "$clean" > "$out"
  rm -f "$sub" "$main" "$groups" "$clean"
}

reload_device_policy_runtime() {
  local candidate path body
  candidate="$1"
  path="$CRASHDIR/device-policy-runtime.yaml"
  cp -f "$candidate" "$path.new.$$" || return 1
  chmod 644 "$path.new.$$" 2>/dev/null || true
  mv -f "$path.new.$$" "$path" || return 1
  cp -f "$candidate" /tmp/ShellCrash/config.yaml || return 1
  body="$(printf '{"path":"%s","payload":""}' "$(printf '%s' "$path" | json_escape)")"
  curl -fsS --connect-timeout 3 --max-time 30 -X PUT \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
    --data "$body" "$MIHOMO_API/configs?force=true" > "$DEVICE_POLICY_LOG" 2>&1
}

apply_device_policies() {
  local user_new rules_new groups_new test_config runtime_config test_log backup_dir expected actual expected_global actual_global old_runtime old_pid
  find_usb
  validate_device_policy_data || { echo 'invalid device policy data' > "$DEVICE_POLICY_LOG"; return 1; }
  validate_global_rule_data || { echo 'invalid global rule override data' > "$DEVICE_POLICY_LOG"; return 1; }
  user_new="/tmp/mm-device-user-new.$$"
  rules_new="/tmp/mm-device-rules-new.$$"
  groups_new="/tmp/mm-device-groups-new.$$"
  test_config="/tmp/mm-device-config-test.$$"
  runtime_config="/tmp/mm-device-runtime-config.$$"
  test_log="/tmp/mm-device-config-test.log"
  build_device_policy_files "$user_new" "$rules_new" "$groups_new" || return 1
  build_device_policy_test_config "$test_config" || return 1
  build_device_policy_runtime_config "$runtime_config" || return 1
  if ! /tmp/ShellCrash/CrashCore -t -d "$CRASHDIR" -f "$test_config" > "$test_log" 2>&1; then
    cp -f "$test_log" "$DEVICE_POLICY_LOG"
    rm -f "$user_new" "$rules_new" "$groups_new" "$test_config" "$runtime_config"
    return 1
  fi
  if ! /tmp/ShellCrash/CrashCore -t -d "$CRASHDIR" -f "$runtime_config" >> "$test_log" 2>&1; then
    cp -f "$test_log" "$DEVICE_POLICY_LOG"
    rm -f "$user_new" "$rules_new" "$groups_new" "$test_config" "$runtime_config"
    return 1
  fi
  backup_dir="$BASE/device-policy-backups/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$backup_dir"
  [ -f "$CRASHDIR/yamls/user.yaml" ] && cp -p "$CRASHDIR/yamls/user.yaml" "$backup_dir/user.yaml"
  [ -f "$CRASHDIR/yamls/rules.yaml" ] && cp -p "$CRASHDIR/yamls/rules.yaml" "$backup_dir/rules.yaml"
  [ -f "$CRASHDIR/yamls/proxy-groups.yaml" ] && cp -p "$CRASHDIR/yamls/proxy-groups.yaml" "$backup_dir/proxy-groups.yaml"
  cp -p /tmp/ShellCrash/config.yaml "$backup_dir/runtime-config.yaml"
  old_pid="$(pidof CrashCore 2>/dev/null | awk '{print $1}')"
  cp -p "$DEVICE_POLICIES" "$backup_dir/device_policies.list"
  cp -p "$DEVICE_RULES" "$backup_dir/device_rules.list"
  cp -p "$DEVICE_PORT_RULES" "$backup_dir/device_port_rules.list"
  cp -p "$GLOBAL_RULES" "$backup_dir/global_rules.list"
  cp -f "$user_new" "$CRASHDIR/yamls/user.yaml.new.$$" && mv -f "$CRASHDIR/yamls/user.yaml.new.$$" "$CRASHDIR/yamls/user.yaml" || return 1
  cp -f "$rules_new" "$CRASHDIR/yamls/rules.yaml.new.$$" && mv -f "$CRASHDIR/yamls/rules.yaml.new.$$" "$CRASHDIR/yamls/rules.yaml" || return 1
  cp -f "$groups_new" "$CRASHDIR/yamls/proxy-groups.yaml.new.$$" && mv -f "$CRASHDIR/yamls/proxy-groups.yaml.new.$$" "$CRASHDIR/yamls/proxy-groups.yaml" || return 1
  rm -f "$user_new" "$rules_new" "$groups_new" "$test_config"
  device_policy_sources | md5sum | cut -d' ' -f1 > "$BASE/device_policy_sources.md5"
  if ! reload_device_policy_runtime "$runtime_config"; then
    cp -f "$backup_dir/runtime-config.yaml" /tmp/ShellCrash/config.yaml
    [ -f "$backup_dir/user.yaml" ] && cp -f "$backup_dir/user.yaml" "$CRASHDIR/yamls/user.yaml"
    if [ -f "$backup_dir/rules.yaml" ]; then cp -f "$backup_dir/rules.yaml" "$CRASHDIR/yamls/rules.yaml"; else rm -f "$CRASHDIR/yamls/rules.yaml"; fi
    if [ -f "$backup_dir/proxy-groups.yaml" ]; then cp -f "$backup_dir/proxy-groups.yaml" "$CRASHDIR/yamls/proxy-groups.yaml"; else rm -f "$CRASHDIR/yamls/proxy-groups.yaml"; fi
    rm -f "$runtime_config"
    return 1
  fi
  rm -f "$runtime_config"
  [ -n "$old_pid" ] && [ "$(pidof CrashCore 2>/dev/null | awk '{print $1}')" = "$old_pid" ] || {
    printf 'CrashCore PID changed during device policy reload\n' >> "$DEVICE_POLICY_LOG"
  }
  expected="$(device_policy_sources | wc -l | tr -d ' ')"
  actual="$(grep -c 'SUB-RULE,(SRC-IP-CIDR,.*),mm-device-' /tmp/ShellCrash/config.yaml 2>/dev/null || true)"
  expected_global="$(awk 'NF {count++} END {print count+0}' "$GLOBAL_RULES" 2>/dev/null)"
  actual_global="$(awk '
    /^ *# BEGIN MIHOMO MANAGER GLOBAL RULE OVERRIDES$/ {inside=1; next}
    /^ *# END MIHOMO MANAGER GLOBAL RULE OVERRIDES$/ {inside=0; next}
    inside && /^ *-/ {count++}
    END {print count+0}
  ' /tmp/ShellCrash/config.yaml 2>/dev/null)"
  if [ "$expected" != "$actual" ] || [ "$expected_global" != "$actual_global" ]; then
    printf 'policy runtime mismatch devices=%s/%s global_rules=%s/%s\n' "$actual" "$expected" "$actual_global" "$expected_global" > "$DEVICE_POLICY_LOG"
    [ -f "$backup_dir/user.yaml" ] && cp -f "$backup_dir/user.yaml" "$CRASHDIR/yamls/user.yaml"
    if [ -f "$backup_dir/rules.yaml" ]; then cp -f "$backup_dir/rules.yaml" "$CRASHDIR/yamls/rules.yaml"; else rm -f "$CRASHDIR/yamls/rules.yaml"; fi
    if [ -f "$backup_dir/proxy-groups.yaml" ]; then cp -f "$backup_dir/proxy-groups.yaml" "$CRASHDIR/yamls/proxy-groups.yaml"; else rm -f "$CRASHDIR/yamls/proxy-groups.yaml"; fi
    reload_device_policy_runtime "$backup_dir/runtime-config.yaml" >/dev/null 2>&1 || true
    return 1
  fi
  cp -f "$test_log" "$DEVICE_POLICY_LOG"
  log_msg "apply policies devices=$expected global_rules=$expected_global backup=$(basename "$backup_dir")"
  return 0
}

persist_device_groups_file() {
  local groups_base groups_new groups_managed
  groups_base="/tmp/mm-device-groups-base-persist.$$"
  groups_new="/tmp/mm-device-groups-persist.$$"
  groups_managed="/tmp/mm-device-groups-managed-persist.$$"
  if ! strip_managed_device_block "$CUSTOM_GROUPS" "$groups_base" '# BEGIN MIHOMO MANAGER DEVICE GROUPS' '# END MIHOMO MANAGER DEVICE GROUPS'; then
    rm -f "$groups_base" "$groups_new" "$groups_managed"
    return 1
  fi
  cp -f "$groups_base" "$groups_new" || {
    rm -f "$groups_base" "$groups_new" "$groups_managed"
    return 1
  }
  if awk -F '\t' 'NF >= 3 && $3 != "INHERIT" {found=1} END {exit !found}' "$DEVICE_POLICIES" 2>/dev/null; then
    printf '# BEGIN MIHOMO MANAGER DEVICE GROUPS\n' > "$groups_managed"
    write_device_groups_yaml "$groups_managed"
    printf '# END MIHOMO MANAGER DEVICE GROUPS\n' >> "$groups_managed"
    cat "$groups_new" >> "$groups_managed"
    mv -f "$groups_managed" "$groups_new"
  fi
  if ! cp -f "$groups_new" "$CUSTOM_GROUPS.new.$$" || ! mv -f "$CUSTOM_GROUPS.new.$$" "$CUSTOM_GROUPS"; then
    rm -f "$CUSTOM_GROUPS.new.$$" "$groups_base" "$groups_new" "$groups_managed"
    return 1
  fi
  rm -f "$groups_base" "$groups_new" "$groups_managed"
  return 0
}

set_device_selector_fast() {
  local group_path target body now i
  group_path="$1"
  target="$2"
  body="$(printf '{"name":"%s"}' "$(printf '%s' "$target" | json_escape)")"
  curl -fsS --connect-timeout 3 --max-time 25 -X PUT \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
    --data "$body" "$MIHOMO_API/proxies/$group_path" >"$DEVICE_POLICY_LOG" 2>&1 </dev/null &
  i=0
  while [ "$i" -lt 3 ]; do
    now="$(curl -fsS --connect-timeout 1 --max-time 1 -H "Authorization: Bearer $API_KEY" \
      "$MIHOMO_API/proxies/$group_path" 2>/dev/null | jsonfilter -e '@.now' 2>/dev/null)"
    [ "$now" = "$target" ] && return 0
    [ "$i" -ge 2 ] || sleep 1
    i=$((i + 1))
  done
  printf 'selector did not switch to %s within 2 seconds\n' "$target" > "$DEVICE_POLICY_LOG"
  return 1
}

set_device_policy_value() {
  local input ip label target mac old previous previous_mac group group_path
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  label="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  target="$(trim_value "$(printf '%s\n' "$input" | sed -n '3p')")"
  mac="$(norm_value "$(printf '%s\n' "$input" | sed -n '4p')")"
  valid_ipv4_or_cidr "$ip" && ! printf '%s' "$ip" | grep -q '/' || return 1
  valid_policy_target "$target" || return 1
  [ -z "$mac" ] || valid_mac "$mac" || return 1
  printf '%s' "$label" | grep -q "$(printf '\t')" && return 1
  old="/tmp/mm-device-policies-old.$$"
  cp -f "$DEVICE_POLICIES" "$old"
  previous="$(device_default_target "$ip")"
  previous_mac="$(awk -F '\t' -v ip="$ip" '$1 == ip {print $4; exit}' "$DEVICE_POLICIES" 2>/dev/null)"
  if [ -n "$previous" ] && [ "$target" != "INHERIT" ] && [ "$mac" = "$previous_mac" ]; then
    group="$(device_group_name "$ip")"
    group_path="$(url_path_encode "$group")"
    if set_device_selector_fast "$group_path" "$target"; then
      awk -F '\t' -v ip="$ip" '$1 != ip' "$DEVICE_POLICIES" > "$DEVICE_POLICIES.new.$$"
      printf '%s\t%s\t%s\t%s\n' "$ip" "${label:--}" "$target" "$mac" >> "$DEVICE_POLICIES.new.$$"
      mv -f "$DEVICE_POLICIES.new.$$" "$DEVICE_POLICIES"
      if ! persist_device_groups_file; then
        mv -f "$old" "$DEVICE_POLICIES"
        set_device_selector_fast "$group_path" "$previous" >/dev/null 2>&1 || true
        return 1
      fi
      close_device_connections "$ip"
      rm -f "$old"
      log_msg "switch device policy $ip -> $target"
      return 0
    fi
    rm -f "$old"
    return 1
  fi
  awk -F '\t' -v ip="$ip" '$1 != ip' "$DEVICE_POLICIES" > "$DEVICE_POLICIES.new.$$"
  printf '%s\t%s\t%s\t%s\n' "$ip" "${label:--}" "$target" "$mac" >> "$DEVICE_POLICIES.new.$$"
  mv -f "$DEVICE_POLICIES.new.$$" "$DEVICE_POLICIES"
  if apply_device_policies; then rm -f "$old"; return 0; fi
  mv -f "$old" "$DEVICE_POLICIES"
  return 1
}

close_device_connections() {
  local ip body sources source id
  ip="$1"
  sources="/tmp/mm-device-close-sources.$$"
  device_policy_sources | awk -F '\t' -v owner="$ip" '$2 == owner {print $1}' | awk '!seen[$0]++' > "$sources"
  [ -s "$sources" ] || printf '%s\n' "$ip" > "$sources"
  body="$(curl -fsS --connect-timeout 3 --max-time 8 -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/connections" 2>/dev/null)" || {
    rm -f "$sources"
    return 0
  }
  while IFS= read -r source; do
    [ -n "$source" ] || continue
    printf '%s' "$body" | jsonfilter -e "@.connections[@.metadata.sourceIP=\"$source\"].id" 2>/dev/null |
      while IFS= read -r id; do
      [ -n "$id" ] || continue
        curl -fsS --connect-timeout 1 --max-time 2 -X DELETE -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/connections/$id" >/dev/null 2>&1 || true
      done
  done < "$sources"
  rm -f "$sources"
}

set_device_rule_value() {
  local input ip type match target old
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  type="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  match="$(norm_domain_suffix "$(printf '%s\n' "$input" | sed -n '3p')")"
  target="$(trim_value "$(printf '%s\n' "$input" | sed -n '4p')")"
  valid_ipv4_or_cidr "$ip" && ! printf '%s' "$ip" | grep -q '/' || return 1
  case "$type" in DOMAIN|DOMAIN-SUFFIX) ;; *) return 1 ;; esac
  valid_domain "$match" || return 1
  valid_policy_target "$target" && [ "$target" != "INHERIT" ] || return 1
  old="/tmp/mm-device-rules-old.$$"
  cp -f "$DEVICE_RULES" "$old"
  awk -F '\t' -v ip="$ip" -v type="$type" -v match="$match" '!($1 == ip && $2 == type && $3 == match)' "$DEVICE_RULES" > "$DEVICE_RULES.new.$$"
  printf '%s\t%s\t%s\t%s\n' "$ip" "$type" "$match" "$target" >> "$DEVICE_RULES.new.$$"
  mv -f "$DEVICE_RULES.new.$$" "$DEVICE_RULES"
  if apply_device_policies; then rm -f "$old"; return 0; fi
  mv -f "$old" "$DEVICE_RULES"
  return 1
}

set_device_port_rule_value() {
  local input ip port_type port target old
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  port_type="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  port="$(norm_value "$(printf '%s\n' "$input" | sed -n '3p')")"
  target="$(trim_value "$(printf '%s\n' "$input" | sed -n '4p')")"
  valid_ipv4_or_cidr "$ip" && ! printf '%s' "$ip" | grep -q '/' || return 1
  case "$port_type" in IN-PORT|DST-PORT) ;; *) return 1 ;; esac
  valid_port_spec "$port" || return 1
  valid_policy_target "$target" && [ "$target" != "INHERIT" ] || return 1
  old="/tmp/mm-device-port-rules-old.$$"
  cp -f "$DEVICE_PORT_RULES" "$old"
  awk -F '\t' -v ip="$ip" -v port_type="$port_type" -v port="$port" '!($1 == ip && $2 == port_type && $3 == port)' "$DEVICE_PORT_RULES" > "$DEVICE_PORT_RULES.new.$$"
  printf '%s\t%s\t%s\t%s\n' "$ip" "$port_type" "$port" "$target" >> "$DEVICE_PORT_RULES.new.$$"
  mv -f "$DEVICE_PORT_RULES.new.$$" "$DEVICE_PORT_RULES"
  if apply_device_policies; then rm -f "$old"; return 0; fi
  mv -f "$old" "$DEVICE_PORT_RULES"
  return 1
}

delete_device_port_rule_value() {
  local input ip port_type port old
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  port_type="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  port="$(norm_value "$(printf '%s\n' "$input" | sed -n '3p')")"
  valid_ipv4_or_cidr "$ip" && ! printf '%s' "$ip" | grep -q '/' || return 1
  case "$port_type" in IN-PORT|DST-PORT) ;; *) return 1 ;; esac
  valid_port_spec "$port" || return 1
  old="/tmp/mm-device-port-rules-old.$$"
  cp -f "$DEVICE_PORT_RULES" "$old"
  awk -F '\t' -v ip="$ip" -v port_type="$port_type" -v port="$port" '!($1 == ip && $2 == port_type && $3 == port)' "$DEVICE_PORT_RULES" > "$DEVICE_PORT_RULES.new.$$"
  mv -f "$DEVICE_PORT_RULES.new.$$" "$DEVICE_PORT_RULES"
  if apply_device_policies; then rm -f "$old"; return 0; fi
  mv -f "$old" "$DEVICE_PORT_RULES"
  return 1
}

delete_device_rule_value() {
  local input ip type match old
  input="$1"
  ip="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  type="$(trim_value "$(printf '%s\n' "$input" | sed -n '2p')")"
  match="$(norm_domain_suffix "$(printf '%s\n' "$input" | sed -n '3p')")"
  old="/tmp/mm-device-rules-old.$$"
  cp -f "$DEVICE_RULES" "$old"
  awk -F '\t' -v ip="$ip" -v type="$type" -v match="$match" '!($1 == ip && $2 == type && $3 == match)' "$DEVICE_RULES" > "$DEVICE_RULES.new.$$"
  mv -f "$DEVICE_RULES.new.$$" "$DEVICE_RULES"
  if apply_device_policies; then rm -f "$old"; return 0; fi
  mv -f "$old" "$DEVICE_RULES"
  return 1
}

close_domain_connections() {
  local domain body ids id
  domain="$1"
  body="$(curl -fsS --connect-timeout 3 --max-time 8 -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/connections" 2>/dev/null)" || return 0
  ids="/tmp/mm-global-rule-connections.$$"
  {
    printf '%s' "$body" | jsonfilter -e "@.connections[@.metadata.host=\"$domain\"].id" 2>/dev/null
    printf '%s' "$body" | jsonfilter -e "@.connections[@.metadata.sniffHost=\"$domain\"].id" 2>/dev/null
  } | sort -u > "$ids"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    curl -fsS --connect-timeout 1 --max-time 2 -X DELETE -H "Authorization: Bearer $API_KEY" "$MIHOMO_API/connections/$id" >/dev/null 2>&1 || true
  done < "$ids"
  rm -f "$ids"
}

backup_global_rule_list() {
  local dir
  dir="$BASE/global-rule-list-backups"
  mkdir -p "$dir"
  cp -p "$GLOBAL_RULES" "$dir/global_rules.$(date '+%Y%m%d-%H%M%S').list"
}

set_global_rule_value() {
  local input type match target old
  input="$1"
  type="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  match="$(normalize_target "$(printf '%s\n' "$input" | sed -n '2p')")"
  target="$(trim_value "$(printf '%s\n' "$input" | sed -n '3p')")"
  case "$type" in
    DOMAIN) ;;
    DOMAIN-SUFFIX) match="$(norm_domain_suffix "$match")" ;;
    *) return 1 ;;
  esac
  valid_domain "$match" || return 1
  valid_policy_target "$target" && [ "$target" != "INHERIT" ] || return 1
  old="/tmp/mm-global-rules-old.$$"
  cp -f "$GLOBAL_RULES" "$old"
  backup_global_rule_list
  awk -F '\t' -v type="$type" -v match="$match" '!($1 == type && $2 == match)' "$GLOBAL_RULES" > "$GLOBAL_RULES.new.$$"
  printf '%s\t%s\t%s\n' "$type" "$match" "$target" >> "$GLOBAL_RULES.new.$$"
  mv -f "$GLOBAL_RULES.new.$$" "$GLOBAL_RULES"
  if apply_device_policies; then
    close_domain_connections "$match"
    rm -f "$old"
    log_msg "set global rule $type $match -> $target"
    return 0
  fi
  mv -f "$old" "$GLOBAL_RULES"
  return 1
}

delete_global_rule_value() {
  local input type match old
  input="$1"
  type="$(trim_value "$(printf '%s\n' "$input" | sed -n '1p')")"
  match="$(normalize_target "$(printf '%s\n' "$input" | sed -n '2p')")"
  case "$type" in
    DOMAIN) ;;
    DOMAIN-SUFFIX) match="$(norm_domain_suffix "$match")" ;;
    *) return 1 ;;
  esac
  valid_domain "$match" || return 1
  old="/tmp/mm-global-rules-old.$$"
  cp -f "$GLOBAL_RULES" "$old"
  backup_global_rule_list
  awk -F '\t' -v type="$type" -v match="$match" '!($1 == type && $2 == match)' "$GLOBAL_RULES" > "$GLOBAL_RULES.new.$$"
  mv -f "$GLOBAL_RULES.new.$$" "$GLOBAL_RULES"
  if apply_device_policies; then
    close_domain_connections "$match"
    rm -f "$old"
    log_msg "delete global rule $type $match"
    return 0
  fi
  mv -f "$old" "$GLOBAL_RULES"
  return 1
}

device_policies_json() {
  local first ip label target mac
  printf '['
  first=1
  while IFS="$(printf '\t')" read -r ip label target mac; do
    [ -n "$ip" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"ip":"%s","label":"%s","target":"%s","mac":"%s"}' "$(printf '%s' "$ip" | json_escape)" "$(printf '%s' "$label" | json_escape)" "$(printf '%s' "$target" | json_escape)" "$(printf '%s' "$mac" | json_escape)"
  done < "$DEVICE_POLICIES"
  printf ']'
}

device_rules_json() {
  local first ip type match target
  printf '['
  first=1
  while IFS="$(printf '\t')" read -r ip type match target; do
    [ -n "$ip" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"ip":"%s","type":"%s","match":"%s","target":"%s"}' "$(printf '%s' "$ip" | json_escape)" "$type" "$(printf '%s' "$match" | json_escape)" "$(printf '%s' "$target" | json_escape)"
  done < "$DEVICE_RULES"
  printf ']'
}

device_port_rules_json() {
  local first ip port_type port target
  printf '['
  first=1
  while IFS="$(printf '\t')" read -r ip port_type port target; do
    [ -n "$ip" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"ip":"%s","type":"%s","port":"%s","target":"%s"}' "$(printf '%s' "$ip" | json_escape)" "$port_type" "$port" "$(printf '%s' "$target" | json_escape)"
  done < "$DEVICE_PORT_RULES"
  printf ']'
}

global_rules_json() {
  local first type match target
  printf '['
  first=1
  while IFS="$(printf '\t')" read -r type match target; do
    [ -n "$type" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"type":"%s","match":"%s","target":"%s"}' "$type" "$(printf '%s' "$match" | json_escape)" "$(printf '%s' "$target" | json_escape)"
  done < "$GLOBAL_RULES"
  printf ']'
}

profile_check_json() {
  find_usb
  active_url="$(current_profile_url)"
  tmp="/tmp/mihomo-manager-profile-check.yaml.$$"
  check_log="/tmp/mihomo-manager-profile-check.log"
  test_log="/tmp/mihomo-manager-profile-test.log"
  rm -f "$tmp"
  if ! curl -fsS --connect-timeout 5 --max-time 60 -o "$tmp" "$active_url" >"$check_log" 2>&1; then
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf '{"ok":false,"error":"download failed","url":"%s","check_log":' "$(printf '%s' "$active_url" | json_escape)"
    json_tail_array "$check_log" 20
    printf '}'
    rm -f "$tmp"
    return
  fi
  if [ ! -s "$tmp" ] ||
     ! grep -q '^proxies:' "$tmp" ||
     ! grep -q '^proxy-groups:' "$tmp" ||
     ! grep -q '^rules:' "$tmp"; then
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf '{"ok":false,"error":"basic sanity check failed","url":"%s"}' "$(printf '%s' "$active_url" | json_escape)"
    rm -f "$tmp"
    return
  fi
  if [ -x /tmp/ShellCrash/CrashCore ]; then
    if ! /tmp/ShellCrash/CrashCore -t -d "$CRASHDIR" -f "$tmp" >"$test_log" 2>&1; then
      printf 'Content-Type: application/json; charset=utf-8\r\n'
      printf 'Cache-Control: no-store\r\n\r\n'
      printf '{"ok":false,"error":"mihomo config test failed","url":"%s","test_log":' "$(printf '%s' "$active_url" | json_escape)"
      json_tail_array "$test_log" 30
      printf '}'
      rm -f "$tmp"
      return
    fi
  fi
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '{"ok":true,"url":"%s","size":%s,"test_log":' "$(printf '%s' "$active_url" | json_escape)" "$(wc -c < "$tmp" | tr -d ' ')"
  json_tail_array "$test_log" 30
  printf '}'
  rm -f "$tmp"
}

status_json() {
  find_usb
  load_state
  dns_mod="$(get_cfg_value dns_mod)"
  redir_mod="$(get_cfg_value redir_mod)"
  crash_pid="$(pidof CrashCore 2>/dev/null | awk '{print $1}')"
  node_pid="$(pidof node-musl 2>/dev/null | awk '{print $1}')"
  active_url="$(current_profile_url)"
  cn_last="$(cat "$BASE/last_cn_refresh" 2>/dev/null || echo 0)"
  profile_last="$(cat "$BASE/last_profile_sync" 2>/dev/null || echo 0)"
  cron_line="$(crontab -l 2>/dev/null | grep -E '/data/sync_substore_profile_to_shellcrash.sh|/data/mihomo_manager.sh auto-sync' | grep -v '^#' | head -n 1)"
  sync_interval="$(sync_interval_from_cron)"
  printf '{'
  printf '"ok":true,'
  printf '"cn_accel":%s,' "$([ "$CN_ACCEL" = 1 ] && echo true || echo false)"
  printf '"dns_mod":"%s",' "$(printf '%s' "$dns_mod" | json_escape)"
  printf '"redir_mod":"%s",' "$(printf '%s' "$redir_mod" | json_escape)"
  printf '"cn4_url":"%s",' "$(printf '%s' "$CN4_URL" | json_escape)"
  printf '"cn6_url":"%s",' "$(printf '%s' "$CN6_URL" | json_escape)"
  printf '"cn_refresh_hours":%s,' "$CN_REFRESH_HOURS"
  printf '"cn_last_refresh":"%s",' "$(printf '%s' "$cn_last" | json_escape)"
  printf '"profile_url":"%s",' "$(printf '%s' "$active_url" | json_escape)"
  printf '"profile_sync_hours":%s,' "$PROFILE_SYNC_HOURS"
  printf '"profile_sync_enabled":%s,' "$([ "$PROFILE_SYNC_HOURS" = 0 ] && echo false || echo true)"
  printf '"profile_last_sync":"%s",' "$(printf '%s' "$profile_last" | json_escape)"
  printf '"sync_interval_min":%s,' "$sync_interval"
  printf '"cron_line":"%s",' "$(printf '%s' "$cron_line" | json_escape)"
  printf '"crash_pid":"%s",' "$crash_pid"
  printf '"substore_pid":"%s",' "$node_pid"
  printf '"sets":{"cn4":%s,"cn6":%s,"force4":%s,"force6":%s,"force_net4":%s,"force_net6":%s,"suffix4":%s,"suffix6":%s,"direct4":%s,"direct6":%s,"direct_net4":%s,"direct_net6":%s,"direct_suffix4":%s,"direct_suffix6":%s,"devices4":%s},' \
    "$(ipset_count mm_cn4)" "$(ipset_count mm_cn6)" "$(ipset_count mm_force4)" "$(ipset_count mm_force6)" "$(ipset_count mm_force_net4)" "$(ipset_count mm_force_net6)" "$(ipset_count mm_suffix4)" "$(ipset_count mm_suffix6)" "$(ipset_count mm_direct4)" "$(ipset_count mm_direct6)" "$(ipset_count mm_direct_net4)" "$(ipset_count mm_direct_net6)" "$(ipset_count mm_direct_suffix4)" "$(ipset_count mm_direct_suffix6)" "$(ipset_count mm_device4)"
  printf '"devices":'
  json_file_array "$DEVICES"
  printf ',"wlan_bypass":'
  json_file_array "$WLAN_BYPASS"
  printf ',"wlans":'
  json_wlan_array
  printf ',"online_devices":'
  online_devices_json
  printf ',"device_policies":'
  device_policies_json
  printf ',"device_rules":'
  device_rules_json
  printf ',"device_port_rules":'
  device_port_rules_json
  printf ',"global_rules":'
  global_rules_json
  printf ',"device_policy_log":'
  json_tail_array "$DEVICE_POLICY_LOG" 20
  printf ',"backups":'
  backups_json
  printf ',"domains":'
  json_file_array "$DOMAINS"
  printf ',"suffixes":'
  json_file_array "$SUFFIXES"
  printf ',"force_nets":'
  json_file_array "$FORCE_NETS"
  printf ',"direct_domains":'
  json_file_array "$DIRECT_DOMAINS"
  printf ',"direct_suffixes":'
  json_file_array "$DIRECT_SUFFIXES"
  printf ',"direct_nets":'
  json_file_array "$DIRECT_NETS"
  printf ',"profile_urls":'
  json_file_array "$URLS"
  printf ',"force_ipv4":'
  json_file_array "$FORCE4"
  printf ',"force_ipv6":'
  json_file_array "$FORCE6"
  printf ',"direct_ipv4":'
  json_file_array "$DIRECT4"
  printf ',"direct_ipv6":'
  json_file_array "$DIRECT6"
  printf ',"last_log":'
  tail -20 "$LOG" 2>/dev/null > "$BASE/log.tail" || : > "$BASE/log.tail"
  json_file_array "$BASE/log.tail"
  printf ',"sync_log":'
  json_tail_array "$SYNC_LOG" 20
  printf ',"sync_test_log":'
  json_tail_array "$SYNC_TEST_LOG" 30
  printf ',"sync_now_log":'
  json_tail_array /tmp/mihomo-manager-sync-now.log 20
  printf ',"auto_sync_log":'
  json_tail_array /tmp/mihomo-manager-auto-sync.log 20
  printf '}'
}

url_decode() {
  s="$(printf '%s\n' "$1" | sed 's/+/ /g; s/%/\\x/g')"
  printf '%b' "$s"
}

param_get() {
  name="$1"
  data="$2"
  printf '%s\n' "$data" | tr '&' '\n' | while IFS='=' read -r k v; do
    [ "$k" = "$name" ] && {
      url_decode "$v"
      exit 0
    }
  done
}

cgi_reply() {
  code="$1"
  body="$2"
  printf 'Status: %s\r\n' "$code"
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Access-Control-Allow-Origin: *\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '%s' "$body"
}

cgi() {
  find_usb
  body=""
  [ "$REQUEST_METHOD" = "POST" ] && body="$(cat)"
  data="$QUERY_STRING"
  [ -n "$body" ] && data="$data&$body"
  action="$(param_get action "$data")"
  key="$(param_get key "$data")"
  raw_value="$(param_get value "$data")"
  raw_value="$(trim_value "$raw_value")"
  value="$(norm_value "$raw_value")"
  if [ -z "$API_KEY" ]; then
    cgi_reply "503 Service Unavailable" '{"ok":false,"error":"mihomo controller secret is not configured"}'
    return
  fi
  if [ "$key" != "$API_KEY" ]; then
    cgi_reply "403 Forbidden" '{"ok":false,"error":"bad key"}'
    return
  fi
  case "$action" in
    ""|status)
      printf 'Content-Type: application/json; charset=utf-8\r\n'
      printf 'Access-Control-Allow-Origin: *\r\n'
      printf 'Cache-Control: no-store\r\n\r\n'
      status_json
    ;;
    enable_cn)
      enable_cn
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    disable_cn)
      disable_cn
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_device)
      if valid_ipv4_or_cidr "$value" || valid_mac "$value"; then
        add_unique_line "$DEVICES" "$value"
        apply_firewall
        log_msg "add device bypass $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad device"}'
      fi
    ;;
    del_device)
      del_line "$DEVICES" "$value"
      apply_firewall
      log_msg "delete device bypass $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    set_wlan_mode)
      if set_wlan_mode "$value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad wlan mode"}'
      fi
    ;;
    add_domain)
      value="$(normalize_target "$raw_value")"
      if valid_domain "$value"; then
        add_unique_line "$DOMAINS" "$value"
        resolve_domains
        apply_firewall
        log_msg "add force domain $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad domain"}'
      fi
    ;;
    del_domain)
      value="$(normalize_target "$raw_value")"
      del_line "$DOMAINS" "$value"
      resolve_domains
      apply_firewall
      log_msg "delete force domain $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_suffix)
      value="$(norm_domain_suffix "$(normalize_target "$raw_value")")"
      if valid_domain "$value"; then
        add_unique_line "$SUFFIXES" "$value"
        apply_firewall
        log_msg "add force suffix $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad suffix"}'
      fi
    ;;
    del_suffix)
      value="$(norm_domain_suffix "$(normalize_target "$raw_value")")"
      del_line "$SUFFIXES" "$value"
      apply_firewall
      log_msg "delete force suffix $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_force_net)
      if valid_ip_or_cidr "$value"; then
        add_unique_line "$FORCE_NETS" "$value"
        apply_firewall
        log_msg "add force ip/cidr $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad force ip/cidr"}'
      fi
    ;;
    del_force_net)
      del_line "$FORCE_NETS" "$value"
      apply_firewall
      log_msg "delete force ip/cidr $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_direct_domain)
      value="$(normalize_target "$raw_value")"
      if valid_domain "$value"; then
        add_unique_line "$DIRECT_DOMAINS" "$value"
        resolve_direct_domains
        apply_firewall
        log_msg "add direct domain $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad direct domain"}'
      fi
    ;;
    del_direct_domain)
      value="$(normalize_target "$raw_value")"
      del_line "$DIRECT_DOMAINS" "$value"
      resolve_direct_domains
      apply_firewall
      log_msg "delete direct domain $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_direct_suffix)
      value="$(norm_domain_suffix "$(normalize_target "$raw_value")")"
      if valid_domain "$value"; then
        add_unique_line "$DIRECT_SUFFIXES" "$value"
        apply_firewall
        log_msg "add direct suffix $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad direct suffix"}'
      fi
    ;;
    apply_preset)
      if apply_direct_preset "$value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad preset"}'
      fi
    ;;
    diagnose)
      diagnose_json "$value"
    ;;
    check_profile)
      profile_check_json
    ;;
    backup_config)
      backup_config_json
    ;;
    download_current_config)
      download_current_config
    ;;
    download_backup)
      download_backup "$raw_value"
    ;;
    import_config_b64)
      import_config_b64 "$raw_value"
    ;;
    set_device_bypass)
      if set_device_bypass_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad device bypass value"}'
      fi
    ;;
    set_device_policy)
      if set_device_policy_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"device policy update failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    set_device_rule)
      if set_device_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"device rule update failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    del_device_rule)
      if delete_device_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"device rule delete failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    set_device_port_rule)
      if set_device_port_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"device port rule update failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    del_device_port_rule)
      if delete_device_port_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"device port rule delete failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    set_global_rule)
      if set_global_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"global rule update failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    del_global_rule)
      if delete_global_rule_value "$raw_value"; then
        cgi_reply "200 OK" '{"ok":true}'
      else
        printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"global rule delete failed","log":'
        json_tail_array "$DEVICE_POLICY_LOG" 20
        printf '}'
      fi
    ;;
    rule_test)
      rule_test_json "$raw_value"
    ;;
    mihomo_proxies)
      mihomo_proxies_json
    ;;
    set_proxy_group)
      set_proxy_group_json "$raw_value"
    ;;
    del_direct_suffix)
      value="$(norm_domain_suffix "$(normalize_target "$raw_value")")"
      del_line "$DIRECT_SUFFIXES" "$value"
      apply_firewall
      log_msg "delete direct suffix $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_direct_net)
      if valid_ip_or_cidr "$value"; then
        add_unique_line "$DIRECT_NETS" "$value"
        apply_firewall
        log_msg "add direct ip/cidr $value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad direct ip/cidr"}'
      fi
    ;;
    del_direct_net)
      del_line "$DIRECT_NETS" "$value"
      apply_firewall
      log_msg "delete direct ip/cidr $value"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    refresh)
      resolve_domains
      resolve_direct_domains
      apply_firewall
      log_msg "refresh domains"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    add_url)
      if valid_url "$raw_value"; then
        add_unique_line "$URLS" "$raw_value"
        log_msg "add profile url $raw_value"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad url"}'
      fi
    ;;
    del_url)
      active="$(current_profile_url)"
      if [ "$raw_value" = "$active" ]; then
        cgi_reply "400 Bad Request" '{"ok":false,"error":"active url"}'
      else
        del_line "$URLS" "$raw_value"
        log_msg "delete profile url $raw_value"
        cgi_reply "200 OK" '{"ok":true}'
      fi
    ;;
    set_url)
      if valid_url "$raw_value"; then
        if write_profile_url "$raw_value"; then
          add_unique_line "$URLS" "$raw_value"
          log_msg "set profile url $raw_value"
          cgi_reply "200 OK" '{"ok":true}'
        else
          cgi_reply "500 Internal Server Error" '{"ok":false,"error":"write profile url failed"}'
        fi
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad url"}'
      fi
    ;;
    set_cn_source)
      if set_cn_source "$raw_value"; then
        log_msg "set CN source"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad CN source"}'
      fi
    ;;
    refresh_cn)
      if refresh_cn_lists; then
        apply_firewall
        log_msg "refresh CN lists"
        cgi_reply "200 OK" '{"ok":true}'
      else
        log_msg "refresh CN lists failed"
        cgi_reply "500 Internal Server Error" '{"ok":false,"error":"CN refresh failed"}'
      fi
    ;;
    set_interval)
      if set_sync_interval "$value"; then
        log_msg "set profile sync interval ${value}h"
        cgi_reply "200 OK" '{"ok":true}'
      else
        cgi_reply "400 Bad Request" '{"ok":false,"error":"bad interval"}'
      fi
    ;;
    sync_now)
      if /bin/sh "$SYNC_SCRIPT" >/tmp/mihomo-manager-sync-now.log 2>&1; then
        date +%s > "$BASE/last_profile_sync"
        log_msg "sync now ok"
        cgi_reply "200 OK" '{"ok":true}'
      else
        log_msg "sync now failed"
        printf 'Status: 500 Internal Server Error\r\n'
        printf 'Content-Type: application/json; charset=utf-8\r\n'
        printf 'Cache-Control: no-store\r\n\r\n'
        printf '{"ok":false,"error":"sync failed","sync_now_log":'
        json_tail_array /tmp/mihomo-manager-sync-now.log 20
        printf ',"sync_log":'
        json_tail_array "$SYNC_LOG" 20
        printf ',"test_log":'
        json_tail_array "$SYNC_TEST_LOG" 30
        printf '}'
      fi
    ;;
    restart_proxy)
      restart_shellcrash
      log_msg "restart proxy"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    apply)
      apply_firewall
      log_msg "apply firewall"
      cgi_reply "200 OK" '{"ok":true}'
    ;;
    *)
      cgi_reply "400 Bad Request" '{"ok":false,"error":"bad action"}'
    ;;
  esac
}

main() {
  cmd="$1"
  case "$cmd" in
    cgi) cgi ;;
    auto-sync) auto_sync_profile ;;
    guard) guard ;;
    start-web) start_web ;;
    apply) apply_firewall ;;
    status) status_json; echo ;;
    enable-cn) enable_cn ;;
    disable-cn) disable_cn ;;
    add-device) find_usb; value="$(norm_value "$2")"; valid_ipv4_or_cidr "$value" || valid_mac "$value" || exit 2; add_unique_line "$DEVICES" "$value"; apply_firewall ;;
    del-device) find_usb; value="$(norm_value "$2")"; del_line "$DEVICES" "$value"; apply_firewall ;;
    set-wlan-mode) find_usb; set_wlan_mode "$2" ;;
    set-device-policy) find_usb; set_device_policy_value "$2" ;;
    set-device-rule) find_usb; set_device_rule_value "$2" ;;
    del-device-rule) find_usb; delete_device_rule_value "$2" ;;
    set-device-port-rule) find_usb; set_device_port_rule_value "$2" ;;
    del-device-port-rule) find_usb; delete_device_port_rule_value "$2" ;;
    set-global-rule) find_usb; set_global_rule_value "$2" ;;
    del-global-rule) find_usb; delete_global_rule_value "$2" ;;
    add-domain) find_usb; value="$(normalize_target "$2")"; valid_domain "$value" || exit 2; add_unique_line "$DOMAINS" "$value"; resolve_domains; apply_firewall ;;
    del-domain) find_usb; value="$(normalize_target "$2")"; del_line "$DOMAINS" "$value"; resolve_domains; apply_firewall ;;
    add-suffix) find_usb; value="$(norm_domain_suffix "$(normalize_target "$2")")"; valid_domain "$value" || exit 2; add_unique_line "$SUFFIXES" "$value"; apply_firewall ;;
    del-suffix) find_usb; value="$(norm_domain_suffix "$(normalize_target "$2")")"; del_line "$SUFFIXES" "$value"; apply_firewall ;;
    add-force-net) find_usb; value="$(norm_value "$2")"; valid_ip_or_cidr "$value" || exit 2; add_unique_line "$FORCE_NETS" "$value"; apply_firewall ;;
    del-force-net) find_usb; value="$(norm_value "$2")"; del_line "$FORCE_NETS" "$value"; apply_firewall ;;
    add-direct-domain) find_usb; value="$(normalize_target "$2")"; valid_domain "$value" || exit 2; add_unique_line "$DIRECT_DOMAINS" "$value"; resolve_direct_domains; apply_firewall ;;
    del-direct-domain) find_usb; value="$(normalize_target "$2")"; del_line "$DIRECT_DOMAINS" "$value"; resolve_direct_domains; apply_firewall ;;
    add-direct-suffix) find_usb; value="$(norm_domain_suffix "$(normalize_target "$2")")"; valid_domain "$value" || exit 2; add_unique_line "$DIRECT_SUFFIXES" "$value"; apply_firewall ;;
    del-direct-suffix) find_usb; value="$(norm_domain_suffix "$(normalize_target "$2")")"; del_line "$DIRECT_SUFFIXES" "$value"; apply_firewall ;;
    add-direct-net) find_usb; value="$(norm_value "$2")"; valid_ip_or_cidr "$value" || exit 2; add_unique_line "$DIRECT_NETS" "$value"; apply_firewall ;;
    del-direct-net) find_usb; value="$(norm_value "$2")"; del_line "$DIRECT_NETS" "$value"; apply_firewall ;;
    apply-preset) apply_direct_preset "$(norm_value "$2")" ;;
    diagnose) diagnose_json "$2" ;;
    refresh) find_usb; resolve_domains; resolve_direct_domains; apply_firewall ;;
    set-url) find_usb; value="$(trim_value "$2")"; valid_url "$value" || exit 2; write_profile_url "$value" || exit 1; add_unique_line "$URLS" "$value" ;;
    set-interval) find_usb; set_sync_interval "$2" ;;
    set-cn-source) find_usb; set_cn_source "$2" ;;
    refresh-cn) refresh_cn_lists; apply_firewall ;;
    check-profile) profile_check_json ;;
    sync-now) find_usb; /bin/sh "$SYNC_SCRIPT" && date +%s > "$BASE/last_profile_sync" ;;
    restart-proxy) restart_shellcrash ;;
    *) echo "usage: $0 {guard|start-web|apply|status|enable-cn|disable-cn|add-device|del-device|add-domain|del-domain|refresh}" >&2; exit 2 ;;
  esac
}

if [ "${MIHOMO_MANAGER_LIBRARY:-0}" != "1" ]; then
  main "$@"
  rc=$?
  [ -z "$POLICY_TARGETS_CACHE" ] || rm -f "$POLICY_TARGETS_CACHE"
  exit "$rc"
fi
