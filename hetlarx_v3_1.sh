#!/usr/bin/env bash
# ============================================================
#  HETLAR-X v3.1 — Unified Recon + Advanced + Verification
#  - Non-invasive by default, Kali-friendly (no pip), colorized UX
#  - All stages always ON (S1..S11), no subdomain timeout
#  - AllTxtFiles as unified wordlists (dirs/params)
#  - Skip/Resume/Time Budgets + AI Brain (learn & improve)
#  Legal: Use only on assets you own or have written authorization.
# ============================================================

set -Eeuo pipefail

trap 'echo -e "\033[0;31m✖ Error at line $LINENO. Check run.log.\033[0m"' ERR

# ========= Colors & Icons =========
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; NC="\033[0m"
IC_OK="✅"; IC_WARN="⚠️"; IC_INFO="ℹ️"; IC_RUN="🚀"; IC_STEP="🔹"; IC_DONE="🏁"; IC_GEAR="🛠️"; IC_BOOK="📘"; IC_BRAIN="🧠"

# ========= Identity =========
SCRIPT_NAME="HETLAR-X"
SCRIPT_VERSION="v3.1.0"

# ========= Inputs =========
USER_NAME=""; TARGET=""; MODE="2"    # 1/2/3 -> affects speed only
AI_ENABLE="${AI_ENABLE:-y}"          # y/n (if you export AI_API_KEY, it can suggest fixes)
AI_API_KEY="${AI_API_KEY:-}"
AI_PROVIDER="${AI_PROVIDER:-openai}" # openai|openrouter
AI_MODEL="${AI_MODEL:-gpt-4o-mini}"
AI_BASE_OPENAI="https://api.openai.com/v1/chat/completions"
AI_BASE_OPENROUTER="https://openrouter.ai/api/v1/chat/completions"

# ========= Skip/Resume & Budgets =========
RESUME="${RESUME:-y}"        # y: skip done stages automatically
SKIP="${SKIP:-}"             # CSV e.g. "S7,S9"
ENABLE_BUDGETS="${ENABLE_BUDGETS:-n}"
S1_BUDGET="${S1_BUDGET:-}"   # e.g. 30m
S2_BUDGET="${S2_BUDGET:-}"
S3_BUDGET="${S3_BUDGET:-}"
S4_BUDGET="${S4_BUDGET:-}"
S5_BUDGET="${S5_BUDGET:-}"
S6_BUDGET="${S6_BUDGET:-}"
S7_BUDGET="${S7_BUDGET:-}"
S8_BUDGET="${S8_BUDGET:-}"
S9_BUDGET="${S9_BUDGET:-}"
S10_BUDGET="${S10_BUDGET:-}"
S11_BUDGET="${S11_BUDGET:-}"

done_mark() { [[ "$RESUME" == "y" && -f "$RUN_DIR/.done_$1" ]]; }
mark_done() { touch "$RUN_DIR/.done_$1"; }
should_skip() { echo ",${SKIP}," | grep -qi ",${1},"; }

# ========= Tuning =========
RATE=20; THREADS=100; NUCLEI_RL=40; NUCLEI_SEVERITY="critical,high,medium"

# ========= Paths =========
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR=""
S1=""; S2=""; S3=""; S4=""; S5=""; S6=""; S7=""; S8=""; S9=""; S10=""; S11=""

# ========= Helpers =========
banner() {
  echo -e "${CYAN}"
  echo "============================================================"
  echo "   ${IC_RUN} $SCRIPT_NAME — Recon + Advanced + Verified       "
  echo "   ${IC_INFO} Version: $SCRIPT_VERSION"
  echo "============================================================"
  echo -e "${NC}"
}
ask(){ local p="$1"; local v="$2"; local d="${3:-}"; local i=""; if [[ -n "$d" ]]; then read -rp "$p [$d]: " i; i="${i:-$d}"; else read -rp "$p: " i; fi; eval "$v=\"\$i\""; }
section(){ echo -e "${GREEN}${IC_STEP} [$USER_NAME | $SCRIPT_NAME] $1${NC}"; }
safe_name(){ echo "$1" | sed 's#https\?://##; s#[^a-zA-Z0-9._-]#_#g'; }
mkdirs(){
  RUN_DIR="runs/${TARGET}/${RUN_ID}"; mkdir -p "$RUN_DIR"
  S1="$RUN_DIR/1_subdomains"; S2="$RUN_DIR/2_alive"; S3="$RUN_DIR/3_urls"; S4="$RUN_DIR/4_param_reflections"
  S5="$RUN_DIR/5_classification"; S6="$RUN_DIR/6_nuclei"; S7="$RUN_DIR/7_deep_scans"; S8="$RUN_DIR/8_hidden"
  S9="$RUN_DIR/9_ports_ssl"; S10="$RUN_DIR/10_sessions_waf_jwt"; S11="$RUN_DIR/11_verification_final"
  mkdir -p "$S1" "$S2" "$S3" "$S4" "$S5" "$S6" "$S7" "$S8" "$S9" "$S10" "$S11"
}
start_logging(){ exec > >(tee -a "$RUN_DIR/run.log") 2>&1; }
adapt_mode(){
  case "$MODE" in
    1) RATE=8; THREADS=40;  NUCLEI_RL=15 ;;
    2) RATE=20; THREADS=100; NUCLEI_RL=40 ;;
    3) RATE=40; THREADS=200; NUCLEI_RL=80 ;;
  esac
  echo -e "${BLUE}${IC_INFO} Mode=$MODE | RATE=$RATE | THREADS=$THREADS | NUCLEI_RL=$NUCLEI_RL${NC}"
}

# ========= AI Brain (learn & persist) =========
HETLARX_HOME="${HETLARX_HOME:-$HOME/.hetlarx}"
BRAIN="$HETLARX_HOME/brain.jsonl"
HOOKS="$HETLARX_HOME/hooks.sh"
AUTO_APPLY="${AUTO_APPLY:-n}"   # y: auto-run safe proposals
AI_INSTALL="${AI_INSTALL:-n}"   # y: allow apt/go from AI
SAFE_MODE="${SAFE_MODE:-strict}"
mkdir -p "$HETLARX_HOME"; touch "$BRAIN" "$HOOKS"

ai_record_stage(){ # stage tool count
  local stage="$1" tool="${2:-}" count="${3:-0}" ts
  ts=$(date -Is)
  jq -n --arg ts "$ts" --arg target "$TARGET" --arg stage "$stage" --arg tool "$tool" --argjson findings "${count:-0}" \
     '{ts:$ts,target:$target,stage:$stage,tool:$tool,findings:$findings}' >> "$BRAIN" || true
}
ai_brain_stats(){ jq -s 'map(select(.tool)) | group_by(.tool) | map({tool: (.[0].tool), total: (map(.findings // 0) | add)})' "$BRAIN" 2>/dev/null || true; }
ai_build_context(){
  local alive urls site_type techs nuclei_hits
  alive=$(wc -l < "$S2/alive.txt" 2>/dev/null || echo 0)
  urls=$(wc -l < "$S3/urls_scoped.txt" 2>/dev/null || echo 0)
  site_type=$(tail -n +2 "$S5/site_type.csv" 2>/dev/null | awk -F, '{print $2}' | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
  techs=$(jq -r '(.response.headers["server"] // .headers["server"] // empty),(.response.headers["x-powered-by"] // .headers["x-powered-by"] // empty)' "$S5/headers.json" 2>/dev/null | awk 'NF' | sort -u | tr '\n' ',' | sed 's/,$//')
  nuclei_hits=$(wc -l < "$S6/nuclei.jsonl" 2>/dev/null || echo 0)
  echo "target=$TARGET; alive=$alive; urls=$urls; site_type=${site_type:-unknown}; techs=${techs:-}; nuclei_hits=$nuclei_hits; mode=$MODE;"
}
ai_call_chat(){
  [[ -z "${AI_API_KEY:-}" ]] && return 0
  local content="$1"; local base="$AI_BASE_OPENAI"; [[ "$AI_PROVIDER" == "openrouter" ]] && base="$AI_BASE_OPENROUTER"
  local payload
  payload=$(jq -n --arg model "$AI_MODEL" --arg content "$content" '{
    model:$model,
    messages:[
      {role:"system",content:"You are a Bash recon optimizer. Output only shell commands or export lines. No prose."},
      {role:"user",content:$content}
    ],
    temperature:0.2
  }')
  curl -sS -X POST "$base" -H "Authorization: Bearer $AI_API_KEY" -H "Content-Type: application/json" -d "$payload" \
    | jq -r '.choices[0].message.content // empty'
}
ai_filter_and_apply(){
  local line; : > "$RUN_DIR/ai_actions.log"
  while IFS= read -r line; do
    [[ -z "${line// }" ]] && continue
    # Block dangerous
    if echo "$line" | grep -Eq '(rm -|mkfs|dd if=|:KATEX_INLINE_OPENKATEX_INLINE_CLOSE|shutdown|reboot|chown\s+/|chmod\s+777\s+/|>|>>\s*/(dev|etc))'; then
      echo "[AI] BLOCKED: $line" >> "$RUN_DIR/ai_actions.log"; continue
    fi
    # Exports allowed
    if echo "$line" | grep -Eq '^export (NUCLEI_.*|RATE|THREADS|FFUF_.*)='; then
      echo "[AI] APPLY VAR: $line" | tee -a "$RUN_DIR/ai_actions.log"
      eval "$line" || true; echo "$line" >> "$HOOKS"; continue
    fi
    # Allowlist commands
    local base; base=$(echo "$line" | awk '{print $1}')
    if echo "$base" | grep -Eq '^(apt|apt-get|go|nuclei|httpx|ffuf|gau|waybackurls|katana|subfinder|amass|dnsx|dirsearch|gobuster|nikto|whatweb|jq|sed|awk|curl)$'; then
      if echo "$base" | grep -Eq '^(apt|apt-get|go)$' && [[ "$AI_INSTALL" != "y" ]]; then
        echo "[AI] SKIP install (AI_INSTALL!=y): $line" | tee -a "$RUN_DIR/ai_actions.log"; continue
      fi
      echo "[AI] PROPOSE: $line" | tee -a "$RUN_DIR/ai_actions.log"
      if [[ "$AUTO_APPLY" == "y" ]]; then
        bash -lc "$line" | tee -a "$RUN_DIR/ai_actions.log" || true
      else
        read -rp "Run? (y/n) [$line]: " ans; ans="${ans:-n}"; [[ "$ans" == "y" ]] && bash -lc "$line" | tee -a "$RUN_DIR/ai_actions.log" || true
      fi
      echo "$line" >> "$HOOKS"
    else
      echo "[AI] SKIP (not allowed): $line" >> "$RUN_DIR/ai_actions.log"
    fi
  done
}
ai_learn_and_improve(){
  [[ -z "${AI_API_KEY:-}" ]] && { echo -e "${YELLOW}${IC_BRAIN} AI key not set: skipping self-improve.${NC}"; return 0; }
  local ctx; ctx=$(ai_build_context)
  local stats; stats=$(ai_brain_stats 2>/dev/null)
  local prompt="Context:
$ctx
Prev tool stats: $stats
Goal: increase verified findings (S11). Website type hint above.
Allowed tools only. Output shell commands or export lines, one per line. No prose."
  echo -e "${CYAN}${IC_BRAIN} AI analyzing results and proposing safe improvements...${NC}"
  local props; props=$(ai_call_chat "$prompt")
  [[ -n "$props" ]] && echo "$props" | ai_filter_and_apply
}

# ========= OOS & Wordlists =========
OOS_FILE=""
oos_build_file(){
  OOS_FILE="$RUN_DIR/oos.txt"; : > "$OOS_FILE"
  echo -e "${BLUE}${IC_INFO} أدخل الأنماط خارج السكوب (سطر لكل نمط). اضغط Enter مرتين للإنهاء:${NC}"
  while true; do read -r line || break; [[ -z "${line// }" ]] && break; echo "$line" >> "$OOS_FILE"; done
  echo -e "${GREEN}${IC_OK} OOS saved: $OOS_FILE${NC}"
}
filter_hosts_oos(){
  local in="$1"; local out="$2"
  if [[ -s "$OOS_FILE" ]]; then
    awk 'NF' "$in" | tr '[:upper:]' '[:lower:]' | sort -u \
    | grep -Ev -f "$OOS_FILE" \
    | grep -Ev '(^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|\.local$|\.internal$)' > "$out"
  else
    awk 'NF' "$in" | tr '[:upper:]' '[:lower:]' | sort -u \
    | grep -Ev '(^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|\.local$|\.internal$)' > "$out"
  fi
}
filter_urls_oos_str(){
  if [[ -s "$OOS_FILE" ]]; then
    grep -Ev -f "$OOS_FILE" | grep -Ev '/(logout|signout|delete|destroy|checkout|payment)(/|$)'
  else
    grep -Ev '/(logout|signout|delete|destroy|checkout|payment)(/|$)'
  fi
}

DIR_WORDLIST=""; PARAM_WORDLIST=""; ALL_WORDS=""
setup_wordlists(){
  section "Wordlists — AllTxtFiles ${IC_GEAR}"
  local base="./AllTxtFiles"
  if [[ -d "$base" ]]; then
    echo -e "${IC_INFO} Found directory: AllTxtFiles (merging .txt files)"
    ALL_WORDS="$RUN_DIR/wordlist_all.txt"; : > "$ALL_WORDS"
  # 1️⃣ دمج كل ملفات .txt في ملف واحد مع فرز وحذف الأسطر الفارغة
find "$base" -maxdepth 3 -type f -name "*.txt" -print0 | xargs -0 -I{} cat "{}" >> "$ALL_WORDS" || true
sed -i 's/\r$//' "$ALL_WORDS"
awk 'NF' "$ALL_WORDS" | sort -u > "$ALL_WORDS.tmp" && mv "$ALL_WORDS.tmp" "$ALL_WORDS"

# 2️⃣ ملف الكلمات الخاصة بالـ parameters
PARAM_WORDLIST=$(find "$base" -maxdepth 3 -type f -iname "*param*.txt" | head -n1 || true)

# 3️⃣ ملف الكلمات الخاصة بالدليل/الديركتوريز
DIR_WORDLIST=$(find "$base" -maxdepth 3 -type f \( -iname "*dir*.txt" -o -iname "*raft*directories*.txt" -o -iname "common.txt" \) | head -n1 || true)

# 4️⃣ لو مفيش أي ملف param*.txt، استخدم كل الكلمات
[[ -z "$PARAM_WORDLIST" ]] && PARAM_WORDLIST="$ALL_WORDS"

    [[ -z "$DIR_WORDLIST" ]] && DIR_WORDLIST="$ALL_WORDS"
  elif [[ -f "$base" ]]; then
    echo -e "${IC_INFO} Found file: AllTxtFiles (single wordlist)"
    ALL_WORDS="$base"; PARAM_WORDLIST="$base"; DIR_WORDLIST="$base"
  else
    echo -e "${YELLOW}${IC_WARN} AllTxtFiles not found. Using a lightweight default list.${NC}"
    ALL_WORDS="$RUN_DIR/common.txt"
    curl -sSL "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt" -o "$ALL_WORDS" || true
    PARAM_WORDLIST="$ALL_WORDS"; DIR_WORDLIST="$ALL_WORDS"
  fi
  echo -e "${GREEN}${IC_OK} DIR_WORDLIST: $DIR_WORDLIST"
  echo -e "${GREEN}${IC_OK} PARAM_WORDLIST: $PARAM_WORDLIST"
}

# ========= Preflight =========
preflight(){
  section "Preflight ${IC_GEAR} Network & Tools"
  command -v curl >/dev/null 2>&1 || { echo -e "${RED}curl missing. Install first.${NC}"; exit 1; }
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y || true
    sudo apt-get install -y jq git rsync nmap amass sqlmap gobuster wafw00f dirsearch golang make build-essential pkg-config nikto whatweb || true
  fi
  export GOPATH="${GOPATH:-$HOME/go}"; export PATH="$GOPATH/bin:$PATH"
  if command -v go >/dev/null 2>&1; then
    GO111MODULE=on go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest || true
    GO111MODULE=on go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest || true
    GO111MODULE=on go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest || true
    GO111MODULE=on go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest || true
    GO111MODULE=on go install -v github.com/projectdiscovery/katana/cmd/katana@latest || true
    GO111MODULE=on go install -v github.com/tomnomnom/assetfinder@latest || true
    GO111MODULE=on go install -v github.com/lc/gau/v2/cmd/gau@latest || true
    GO111MODULE=on go install -v github.com/tomnomnom/waybackurls@latest || true
    GO111MODULE=on go install -v github.com/tomnomnom/qsreplace@latest || true
    GO111MODULE=on go install -v github.com/ffuf/ffuf@latest || true
    GO111MODULE=on go install -v github.com/tomnomnom/gf@latest || true
    GO111MODULE=on go install -v github.com/hahwul/dalfox/v2@latest || true
    mkdir -p "$HOME/.gf"
    if [[ ! -f "$HOME/.gf/xss.json" ]]; then
      rm -rf "$HOME/.gf_src" || true
      git clone --depth=1 https://github.com/tomnomnom/gf "$HOME/.gf_src" 2>/dev/null || true
      cp -r "$HOME/.gf_src/examples/"*.json "$HOME/.gf/" 2>/dev/null || true
      rm -rf "$HOME/.gf_src" || true
    fi
    hash -r
  else
    echo -e "${YELLOW}${IC_WARN} Go not found. Will rely on apt tools and curl fallbacks.${NC}"
  fi
  # Quick list of required tools
  local req=(jq curl subfinder amass assetfinder dnsx httpx gau waybackurls katana qsreplace nuclei wafw00f gf dalfox sqlmap dirsearch gobuster nmap nikto whatweb ffuf)
  local missing=(); for t in "${req[@]}"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  if ((${#missing[@]})); then
    echo -e "${YELLOW}${IC_WARN} Missing: ${missing[*]}${NC}"
  else
    echo -e "${GREEN}${IC_OK} All tools present.${NC}"
  fi
}

# ========= Stage wrapper (skip/resume/budget) =========
run_stage(){
  local ID="$1"; local TITLE="$2"; local BUDGET="$3"; local FUNC="$4"
  if should_skip "$ID"; then echo -e "${YELLOW}[SKIP] $ID $TITLE${NC}"; return 0; fi
  if done_mark "$ID"; then echo -e "${BLUE}[RESUME] $ID $TITLE already done.${NC}"; return 0; fi
  section "$ID $TITLE"
  set +e
  if [[ "$ENABLE_BUDGETS" == "y" && -n "$BUDGET" ]]; then
    timeout --foreground "$BUDGET" bash -lc "$FUNC" || echo -e "${YELLOW}${IC_WARN} $ID hit time budget ($BUDGET) — continuing.${NC}"
  else
    bash -lc "$FUNC" || echo -e "${YELLOW}${IC_WARN} $ID encountered errors — continuing.${NC}"
  fi
  set -e
  mark_done "$ID"
}

# ========= Stage functions =========

stage_s1(){
  {
    subfinder -all -d "$TARGET" -silent | tee "$S1/subfinder.txt" || true
    amass enum -passive -d "$TARGET" -o "$S1/amass.txt" 2>/dev/null || true
    assetfinder --subs-only "$TARGET" | tee "$S1/assetfinder.txt" || true
    cat "$S1/"*.txt 2>/dev/null | awk 'NF' | sort -u > "$S1/all.txt"
    echo "$TARGET" >> "$S1/all.txt"
    filter_hosts_oos "$S1/all.txt" "$S1/hosts_filtered.txt"
    if command -v dnsx >/dev/null 2>&1; then
      printf "1.1.1.1\n8.8.8.8\n" > "$S1/resolvers.txt"
      dnsx -silent -r "$S1/resolvers.txt" -l "$S1/hosts_filtered.txt" -o "$S1/final_hosts.txt" || true
    else
      cp "$S1/hosts_filtered.txt" "$S1/final_hosts.txt"
    fi
    echo -e "${GREEN}${IC_OK} Hosts: $(wc -l < "$S1/final_hosts.txt")${NC}"
  } 2>&1 | tee -a "$S1/stage1.log"
}

stage_s2(){
  {
    if command -v httpx >/dev/null 2>&1; then
      httpx -silent -threads "$THREADS" -rate-limit "$RATE" -follow-redirects -max-redirects 2 \
        -probe -sc -title -tech-detect -ip -cdn -json -l "$S1/final_hosts.txt" | tee "$S2/alive.json"
      jq -r '.[].url // empty' "$S2/alive.json" | awk 'NF' | sort -u > "$S2/alive.txt" || true
    else
      : > "$S2/alive.txt"
      while read -r h; do
        for sch in https http; do curl -sSIk "$sch://$h" --max-time 6 >/dev/null 2>&1 && { echo "$sch://$h" >> "$S2/alive.txt"; break; }; done
      done < "$S1/final_hosts.txt"
      sort -u -o "$S2/alive.txt" "$S2/alive.txt"
    fi
    wafw00f -a "$TARGET" > "$S2/waf.txt" 2>/dev/null || true
    echo -e "${GREEN}${IC_OK} Alive URLs: $(wc -l < "$S2/alive.txt" 2>/dev/null || echo 0)${NC}"
  } 2>&1 | tee -a "$S2/stage2.log"
  ai_record_stage "S2" "httpx" "$(wc -l < "$S2/alive.txt" 2>/dev/null || echo 0)"
}

stage_s3(){
  {
    command -v gau >/dev/null 2>&1 && gau -subs "$TARGET" > "$S3/gau.txt" 2>/dev/null || true
    if command -v waybackurls >/dev/null 2>&1; then echo "$TARGET" | waybackurls > "$S3/wayback.txt" 2>/dev/null || true
    else curl -sS "https://web.archive.org/cdx/search/cdx?url=*.$TARGET/*&output=json&fl=original&collapse=urlkey&limit=5000" | jq -r '.[1:][].0' > "$S3/wayback.txt" || true; fi
    if command -v katana >/dev/null 2>&1 && [[ -s "$S2/alive.txt" ]]; then katana -silent -jc -list "$S2/alive.txt" > "$S3/katana.txt" 2>/dev/null || true; fi
    cat "$S3/"*.txt 2>/dev/null | awk 'NF' | sort -u > "$S3/urls_raw.txt" || true
    cp "$S3/urls_raw.txt" "$S3/urls_clean.txt" 2>/dev/null || true
    cat "$S3/urls_clean.txt" 2>/dev/null | filter_urls_oos_str > "$S3/urls_scoped.txt" || true
    echo -e "${GREEN}${IC_OK} URLs in scope: $(wc -l < "$S3/urls_scoped.txt" 2>/dev/null || echo 0)${NC}"
  } 2>&1 | tee -a "$S3/stage3.log"
}

stage_s4(){
  {
    MARKER="ref__$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)"; echo "[*] Marker: $MARKER"
    grep -E '\?' "$S3/urls_scoped.txt" 2>/dev/null | sort -u > "$S4/urls_with_params.txt" || true
    if [[ -s "$S4/urls_with_params.txt" && -x "$(command -v qsreplace)" && -x "$(command -v httpx)" ]]; then
      cat "$S4/urls_with_params.txt" | qsreplace "$MARKER" \
        | httpx -silent -threads "$THREADS" -rate-limit "$RATE" -mc 200,400,403,404 -mr "$MARKER" \
        > "$S4/reflections.txt" 2>/dev/null || true
      echo -e "${GREEN}${IC_OK} Reflections: $(wc -l < "$S4/reflections.txt" 2>/dev/null || echo 0)${NC}"
    else
      echo -e "${YELLOW}${IC_WARN} Reflection check skipped (need qsreplace+httpx and param URLs).${NC}"
    fi
  } 2>&1 | tee -a "$S4/stage4.log"
}

stage_s5(){
  {
    if [[ -s "$S2/alive.txt" ]]; then
      if command -v httpx >/dev/null 2>&1; then
        httpx -silent -threads "$THREADS" -rate-limit "$RATE" -follow-redirects -max-redirects 2 \
          -status-code -title -tech-detect -web-server -json -l "$S2/alive.txt" > "$S5/headers.json" 2>/dev/null || true
      else
        : > "$S5/headers.json"; while read -r u; do { echo "{\"url\":\"$u\",\"headers\":{"; curl -sSIk "$u" --max-time 6 | awk -F': ' '/: /{ gsub("\r",""); printf "\"%s\":\"%s\",",tolower($1),$2 } END{ print "\"_end\":\"_end\"}}" }'; } >> "$S5/headers.json"; done < "$S2/alive.txt"
      fi
    fi
    if command -v gf >/dev/null 2>&1 && [[ -s "$S3/urls_scoped.txt" ]]; then
      cat "$S3/urls_scoped.txt" | gf xss      > "$S5/gf_xss.txt" || true
      cat "$S3/urls_scoped.txt" | gf sqli     > "$S5/gf_sqli.txt" || true
      cat "$S3/urls_scoped.txt" | gf lfi      > "$S5/gf_lfi.txt"  || true
      cat "$S3/urls_scoped.txt" | gf ssrf     > "$S5/gf_ssrf.txt" || true
      cat "$S3/urls_scoped.txt" | gf redirect > "$S5/gf_redirect.txt" || true
    fi
    # whatweb (sample 30)
    head -n 30 "$S2/alive.txt" 2>/dev/null | while read -r u; do whatweb -a 1 -q "$u" || true; done | tee "$S5/whatweb.txt" >/dev/null || true
    # site type classify (sample 10)
    : > "$S5/site_type.csv"; echo "url,type" >> "$S5/site_type.csv"
    while read -r u; do
      body="$(curl -sS "$u" --max-time 8 | tr '\n' ' ' | tr -d '\r' | tr '[:upper:]' '[:lower:]' | head -c 200000)"
      t="generic"
      echo "$body" | grep -qE "cart|checkout|product|add to cart|shop" && t="ecommerce"
      echo "$body" | grep -qE "course|lesson|enroll|curriculum|udemy|lms" && t="courses"
      echo "$body" | grep -qE "wp-content|wordpress|blog|post" && t="blog/cms"
      echo "$body" | grep -qE "portal|dashboard|accounts|login" && t="portal"
      echo "$u,$t" >> "$S5/site_type.csv"
    done < <(head -n 10 "$S2/alive.txt" 2>/dev/null)
    # nikto (top 5)
    head -n 5 "$S2/alive.txt" 2>/dev/null | while read -r u; do nikto -h "$u" -maxtime 300 -Tuning x 2>&1 | tee "$S5/nikto_$(safe_name "$u").txt" >/dev/null || true; done
  } 2>&1 | tee -a "$S5/stage5.log"
}

stage_phase2x_minimal(){
  local OUT="$RUN_DIR/phase2x"; mkdir -p "$OUT"
  # Robots/Sitemaps
  : > "$OUT/sitemaps.txt"; : > "$OUT/robots.txt.list"
  if [[ -s "$S2/alive.txt" ]]; then
    while read -r u; do
      root="$(echo "$u" | awk -F/ '{print $1"//"$3}')"
      curl -sSI "$root/robots.txt" --max-time 6 | head -n1 | grep -qE "200|301|302" && echo "$root/robots.txt" >> "$OUT/robots.txt.list" && curl -sS "$root/robots.txt" --max-time 6 | awk 'BEGIN{IGNORECASE=1} /^Sitemap:/{print $2}' >> "$OUT/sitemaps.txt"
      curl -sSI "$root/sitemap.xml" --max-time 6 | head -n1 | grep -qE "200|301|302" && echo "$root/sitemap.xml" >> "$OUT/sitemaps.txt"
    done < "$S2/alive.txt"
    sort -u -o "$OUT/sitemaps.txt" "$OUT/sitemaps.txt" 2>/dev/null || true
  fi
  # CORS quick (first 20)
  : > "$OUT/cors_checks.csv"; echo "url,origin,status,acao,acac,vary,issue" >> "$OUT/cors_checks.csv"
  local limit=20; mapfile -t sample < <(head -n $limit "$S2/alive.txt" 2>/dev/null)
  evil_origin="https://evil.$TARGET"
  for u in "${sample[@]}"; do
    for origin in "$evil_origin" "null" "https://example.com"; do
      hdrs="$(curl -sSI "$u" -H "Origin: $origin" --max-time 8)"
      st="$(echo "$hdrs" | head -n1 | awk '{print $2}')"
      aco="$(echo "$hdrs" | awk 'BEGIN{IGNORECASE=1} /^Access-Control-Allow-Origin:/{print $0}' | sed 's/.*: //;s/\r//')"
      acc="$(echo "$hdrs" | awk 'BEGIN{IGNORECASE=1} /^Access-Control-Allow-Credentials:/{print $0}' | sed 's/.*: //;s/\r//')"
      vary="$(echo "$hdrs" | awk 'BEGIN{IGNORECASE=1} /^Vary:/{print $0}' | sed 's/.*: //;s/\r//')"
      issue=""; [[ "$aco" == "*" && "$acc" =~ [Tt]rue ]] && issue="ACAO * with credentials=true"
      [[ "$aco" == "$origin" && "$acc" =~ [Tt]rue && "$origin" == "$evil_origin" ]] && issue="Reflects arbitrary Origin with credentials"
      [[ -z "$issue" && "$aco" == "*" ]] && issue="Wildcard ACAO"
      echo "$u,$origin,${st:-},${aco:-},${acc:-},${vary:-},${issue}" >> "$OUT/cors_checks.csv"
    done
  done
  # CSP quick (from httpx headers)
  if [[ -s "$S5/headers.json" ]]; then
    : > "$OUT/csp_findings.csv"; echo "url,csp_issue" >> "$OUT/csp_findings.csv"
    jq -c '.' "$S5/headers.json" 2>/dev/null | while read -r j; do
      url="$(echo "$j" | jq -r '.url // empty')"
      csp="$(echo "$j" | jq -r '.response.headers["Content-Security-Policy"] // .headers["Content-Security-Policy"] // .headers["content-security-policy"] // empty')"
      [[ -z "$csp" ]] && continue
      issue=""
      echo "$csp" | grep -q "unsafe-inline" && issue="${issue}unsafe-inline;"
      echo "$csp" | grep -q "unsafe-eval"   && issue="${issue}unsafe-eval;"
      echo "$csp" | grep -q "default-src" && echo "$csp" | grep -q "default-src.*\*" && issue="${issue}wildcard-default-src;"
      [[ -n "$issue" ]] && echo "$url,${issue%';'}" >> "$OUT/csp_findings.csv"
    done
    [[ -s "$OUT/csp_findings.csv" ]] || rm -f "$OUT/csp_findings.csv"
  fi
}

stage_s6(){
  {
    if [[ -s "$S2/alive.txt" && -x "$(command -v nuclei)" ]]; then
      nuclei -ni -l "$S2/alive.txt" -severity "$NUCLEI_SEVERITY" \
        -tags exposure,misconfig,cve,cors,ssrf,redirect,lfi,rce,xss \
        -rl "$NUCLEI_RL" -jsonl > "$S6/nuclei.jsonl" 2>/dev/null || true
      nuclei -ni -l "$S2/alive.txt" -severity critical,high -tags cve \
        -rl "$NUCLEI_RL" -jsonl > "$S6/nuclei_cve.jsonl" 2>/dev/null || true
    else
      echo -e "${YELLOW}${IC_WARN} Nuclei skipped (no alive or nuclei missing).${NC}"
    fi
  } 2>&1 | tee -a "$S6/stage6.log"
  ai_record_stage "S6" "nuclei" "$(wc -l < "$S6/nuclei.jsonl" 2>/dev/null || echo 0)"
}

stage_s7(){
  {
    grep -E '\?' "$S3/urls_scoped.txt" 2>/dev/null | head -n 400 > "$S7/param_urls_sample.txt" || true
    if [[ -x "$(command -v dalfox)" && -s "$S7/param_urls_sample.txt" ]]; then
      cat "$S7/param_urls_sample.txt" | dalfox pipe --skip-bav --follow-redirects --timeout 6 --no-spinner --worker 20 > "$S7/dalfox.txt" 2>/dev/null || true
    fi
    if [[ -x "$(command -v sqlmap)" && -s "$S7/param_urls_sample.txt" ]]; then
      head -n 20 "$S7/param_urls_sample.txt" > "$S7/sqlmap_urls.txt" || true
      while read -r u; do
        sqlmap -u "$u" --batch --level=1 --risk=1 --random-agent --timeout=8 --retries=0 -o --flush-session --crawl=0 --smart --avoid-567 2>&1 | tee -a "$S7/sqlmap.txt" >/dev/null || true
      done < "$S7/sqlmap_urls.txt"
    fi
  } 2>&1 | tee -a "$S7/stage7.log"
}

stage_s8(){
  {
    while read -r base; do
      safe="$(safe_name "$base")"
      if command -v ffuf >/dev/null 2>&1; then
        ffuf -u "${base}/FUZZ" -w "$DIR_WORDLIST" -of csv -o "$S8/ffuf_paths_${safe}.csv" -t 40 -timeout 8 -mc 200,204,301,302,307,401,403 >/dev/null 2>&1 || true
      fi
      if command -v dirsearch >/dev/null 2>&1; then
        dirsearch -u "$base" -w "$DIR_WORDLIST" --random-agent -t 20 -r --format=plain | tee "$S8/${safe}.txt" >/dev/null || true
      elif command -v gobuster >/dev/null 2>&1; then
        gobuster dir -q -u "$base" -w "$DIR_WORDLIST" -t 30 | tee "$S8/${safe}.txt" >/dev/null || true
      fi
    done < "$S2/alive.txt"
    # Params fuzz (first 20 alive)
    if [[ -x "$(command -v ffuf)" ]]; then
      head -n 20 "$S2/alive.txt" | while read -r base; do
        ffuf -u "${base}?FUZZ=1337" -w "$PARAM_WORDLIST" -of csv -o "$S8/ffuf_params_$(safe_name "$base").csv" -t 40 -timeout 8 -mc 200,401,403 >/dev/null 2>&1 || true
      done
    fi
  } 2>&1 | tee -a "$S8/stage8.log"
  hits=$( (ls "$S8"/ffuf_paths_*.csv 2>/dev/null || true) | wc -l ); ai_record_stage "S8" "ffuf" "${hits:-0}"
}

stage_s9(){
  {
    [[ -s "$S2/alive.json" ]] && jq -r '.ip // empty' "$S2/alive.json" | sort -u > "$S9/ips.txt" || true
    [[ -s "$S9/ips.txt" ]] || awk -F/ '{print $3}' "$S2/alive.txt" | sort -u > "$S9/ips.txt" || true
    if [[ -s "$S9/ips.txt" && -x "$(command -v nmap)" ]]; then
      if [[ "$EUID" -ne 0 ]]; then
        nmap -Pn -n --top-ports 100 -sT -T3 -iL "$S9/ips.txt" > "$S9/nmap_top100.txt" 2>/dev/null || true
      else
        nmap -Pn -n --top-ports 100 -sS -T3 -iL "$S9/ips.txt" > "$S9/nmap_top100.txt" 2>/dev/null || true
      fi
      nmap -Pn -n -p 443 --script ssl-enum-ciphers -iL "$S9/ips.txt" > "$S9/ssl_enum.txt" 2>/dev/null || true
    else
      echo -e "${YELLOW}${IC_WARN} Nmap skipped (no IPs or nmap missing).${NC}"
    fi
  } 2>&1 | tee -a "$S9/stage9.log"
}

stage_s10(){
  local REPORT="$RUN_DIR/report.md"
  {
    echo "# $SCRIPT_NAME Classic Report - $TARGET"
    echo "- Prepared by: $USER_NAME"
    echo "- Run ID: $RUN_ID"
    echo "- Date: $(date -Is)"
    echo
    echo "## Overview"
    echo "- Hosts: $(wc -l < "$S1/final_hosts.txt" 2>/dev/null || echo 0)"
    echo "- Alive: $(wc -l < "$S2/alive.txt" 2>/dev/null || echo 0)"
    echo "- URLs in scope: $(wc -l < "$S3/urls_scoped.txt" 2>/dev/null || echo 0)"
    echo
    echo "## Hints"
    [[ -s "$S4/reflections.txt" ]] && echo "- Reflections: $(wc -l < "$S4/reflections.txt")" || echo "- Reflections: 0"
    [[ -s "$S6/nuclei.jsonl" ]] && echo "- Nuclei hits: $(wc -l < "$S6/nuclei.jsonl")" || echo "- Nuclei hits: 0"
  } > "$REPORT"
  echo -e "${GREEN}${IC_OK} Classic report: $REPORT${NC}"
}

stage_s11(){
  : > "$S11/verified_findings.csv"; echo "category,severity,url,evidence,source" >> "$S11/verified_findings.csv"

  # CORS (from phase2x)
  if [[ -f "$RUN_DIR/phase2x/cors_checks.csv" ]]; then
    awk -F, 'NR>1 && $7!="" {print "CORS," (index($7,"credentials")? "high":"medium") "," $1 "," $7 " (Origin=" $2 ")", "Phase2X"}' "$RUN_DIR/phase2x/cors_checks.csv" >> "$S11/verified_findings.csv" || true
  fi
  # SourceMaps
  if [[ -f "$RUN_DIR/phase2x/sourcemaps.csv" ]]; then
    awk -F, 'NR>1 {print "SourceMap,medium," $1 ",status=" $2, "Phase2X"}' "$RUN_DIR/phase2x/sourcemaps.csv" >> "$S11/verified_findings.csv"
  fi
  # Nuclei CVEs
  if [[ -s "$S6/nuclei_cve.jsonl" ]]; then
    jq -rc '{sev:(.info.severity//""), url:(.matched-at//.host//""), name:(.info.name//""), tpl:(.template//"")}' "$S6/nuclei_cve.jsonl" \
    | while read -r j; do
        sev="$(echo "$j" | jq -r '.sev')"; url="$(echo "$j" | jq -r '.url')"; name="$(echo "$j" | jq -r '.name')"; tpl="$(echo "$j" | jq -r '.tpl')"
        [[ -n "$url" ]] && echo "CVE,$(echo "$sev"),$url,$name ($tpl),Nuclei" >> "$S11/verified_findings.csv"
      done
  fi
  # Dalfox confirm
  [[ -s "$S7/dalfox.txt" ]] && grep -Ei "POC|CONFIRM|VULN" "$S7/dalfox.txt" | awk -vOFS=',' '{print "XSS","high",$0,"dalfox-confirm","Dalfox"}' >> "$S11/verified_findings.csv" || true
  # Open Redirect verify
  if [[ -s "$S5/gf_redirect.txt" ]]; then
    while read -r u; do
      [[ -z "$u" ]] && continue
      testu="$(echo "$u" | qsreplace "https://example.com")"
      loc="$(curl -sSI "$testu" --max-time 8 | awk 'BEGIN{IGNORECASE=1}/^Location:/{print $2}' | tr -d '\r')"
      code="$(curl -sI "$testu" --max-time 8 | head -n1 | awk '{print $2}')"
      if [[ -n "$loc" && "$loc" == https://example.com* && "$code" =~ ^3[0-9][0-9]$ ]]; then
        echo "OpenRedirect,medium,$u,redirects to example.com,Manual-verify" >> "$S11/verified_findings.csv"
      fi
    done < "$S5/gf_redirect.txt"
  fi
  # LFI verify
  if [[ -s "$S5/gf_lfi.txt" ]]; then
    while read -r u; do
      [[ -z "$u" ]] && continue
      u_pwd="$(echo "$u" | qsreplace "../../../../../../etc/passwd")"
      body="$(curl -sS "$u_pwd" --max-time 8 | head -c 20000)"
      if echo "$body" | grep -q "root:x:0:0"; then echo "LFI,high,$u,/etc/passwd read,Manual-verify" >> "$S11/verified_findings.csv"; continue; fi
      u_win="$(echo "$u" | qsreplace "..\..\..\..\..\Windows\win.ini")"
      body2="$(curl -sS "$u_win" --max-time 8 | head -c 20000)"
      echo "$body2" | grep -qi "```math
extensions```" && echo "LFI,high,$u,Windows win.ini read,Manual-verify" >> "$S11/verified_findings.csv"
    done < "$S5/gf_lfi.txt"
  fi
  # FFUF exposures
  if ls "$S8"/ffuf_paths_*.csv >/dev/null 2>&1; then
    for f in "$S8"/ffuf_paths_*.csv; do
      awk -F',' 'NR>1 && ($3 ~ /200|204|301|302|307|401|403/) {print "PathExposure","info",$1,"status="$3" size="$5,"ffuf"}' "$f" >> "$S11/verified_findings.csv" || true
    done
  fi
  # Nikto CVE hints
  if ls "$S5"/nikto_*.txt >/dev/null 2>&1; then
    for f in "$S5"/nikto_*.txt; do
      grep -E "CVE-|OSVDB" "$f" | sed 's/,/ /g' | while read -r line; do
        base="$(echo "$f" | sed 's#.*nikto_##; s#\.txt$##')"
        echo "Nikto,medium,$base,$(echo "$line" | tr -d '\r'),Nikto" >> "$S11/verified_findings.csv"
      done
    done
  fi
  # CSP issues (low)
  if [[ -s "$RUN_DIR/phase2x/csp_findings.csv" ]]; then
    awk -F, 'NR>1 {print "CSP","low",$1,$2,"Phase2X"}' "$RUN_DIR/phase2x/csp_findings.csv" >> "$S11/verified_findings.csv"
  fi

  # Dedupe
  awk -F',' 'BEGIN{OFS=","} !seen[$1$3$4]++{print}' "$S11/verified_findings.csv" > "$S11/verified_findings_dedupe.csv" && mv "$S11/verified_findings_dedupe.csv" "$S11/verified_findings.csv"

  # Final report
  local FINAL="$S11/final_report.md"
  {
    echo "# $SCRIPT_NAME Final Verified Report - $TARGET"
    echo "- Prepared by: $USER_NAME"
    echo "- Run ID: $RUN_ID"
    echo "- Date: $(date -Is)"
    echo
    echo "## Summary"
    total="$(($(wc -l < "$S11/verified_findings.csv" 2>/dev/null)-1))"; echo "- Verified findings: ${total:-0}"
    echo
    echo "## Top Findings (sample)"
    grep -E "CVE|LFI|XSS|OpenRedirect|CORS|SourceMap" "$S11/verified_findings.csv" 2>/dev/null | sed '1d' | head -n 30 | awk -F',' '{printf "- [%s] %s -> %s (%s)\n", toupper($1), $2, $3, $5}' || echo "- None"
    echo
    echo "## Full CSV"
    echo '```'
    cat "$S11/verified_findings.csv"
    echo '```'
    echo
    echo "## Notes"
    echo "- نتائج مُتحققة قدر الإمكان بشكل آلي وآمن؛ يُفضَّل المراجعة اليدوية قبل الإبلاغ."
  } > "$FINAL"
  echo -e "${GREEN}${IC_OK} Verified CSV: $S11/verified_findings.csv${NC}"
  echo -e "${GREEN}${IC_OK} Final report: $S11/final_report.md${NC}"
  ai_record_stage "S11" "verified" "${total:-0}"
}

# ========= Main =========
main(){
  banner
  echo -e "${IC_BOOK} ${BLUE}مرحبًا! يرجى إدخال بيانات التشغيل (نفس نمط الاسكربت الأول).${NC}"
  ask "اكتب اسمك للتوثيق" USER_NAME
  ask "اكتب الدومين الأساسي (مثال: example.com)" TARGET
  while [[ -z "$TARGET" ]]; do ask "الدومين لا يمكن أن يكون فارغًا. اكتب الدومين الأساسي" TARGET; done
  ask "اختَر وضع الفحص 1) بسيط  2) قوي  3) عميق" MODE "2"
  adapt_mode

  # AI options
  read -rp "تفعيل AI Mode (اقتراح تحسينات آمنة)؟ (y/n) [${AI_ENABLE}]: " ans; ans="${ans:-$AI_ENABLE}"; AI_ENABLE="$ans"
  if [[ "$AI_ENABLE" == "y" && -z "${AI_API_KEY:-}" ]]; then
    read -rsp "AI API Key (لن يُخزّن): " AI_API_KEY; echo
  fi

  mkdirs; start_logging
  echo -e "${GREEN}${IC_OK} Prepared by: $USER_NAME | Script: $SCRIPT_NAME $SCRIPT_VERSION${NC}"
  echo -e "${BLUE}${IC_INFO} Target: $TARGET | Run: $RUN_ID${NC}"

  # Optional: budgets and skip
  read -rp "تفعيل ميزانيات زمنية للمراحل؟ (y/n) [${ENABLE_BUDGETS}]: " b; b="${b:-$ENABLE_BUDGETS}"; ENABLE_BUDGETS="$b"
  if [[ "$ENABLE_BUDGETS" == "y" ]]; then
    read -rp "ميزانية S1 (مثال 30m، أو Enter للتخطي): " S1_BUDGET; S1_BUDGET="${S1_BUDGET:-}"
    read -rp "ميزانية S8 (مثال 20m، أو Enter للتخطي): " S8_BUDGET; S8_BUDGET="${S8_BUDGET:-}"
  fi
  read -rp "تريد تخطي مراحل؟ (CSV مثل S7,S9 أو Enter للمتابعة الكاملة): " SKIP; SKIP="${SKIP:-}"

  # Load persisted hooks (from previous runs)
  if [[ -s "$HOOKS" ]]; then
    echo -e "${CYAN}${IC_BRAIN} Loading AI hooks from $HOOKS${NC}"
    # Block install commands unless AI_INSTALL=y
    if [[ "$AI_INSTALL" != "y" ]]; then
      sed -i 's/^KATEX_INLINE_OPENapt\|apt-get\|go installKATEX_INLINE_CLOSE/# [AI-BLOCKED] &/' "$HOOKS"
    fi
    # shellcheck disable=SC1090
    source "$HOOKS" || true
  fi

  preflight
  setup_wordlists
  section "إدخال OOS"; oos_build_file

  # Run stages
  run_stage "S1"  "Subdomains (no time limit)"     "$S1_BUDGET"  "stage_s1"
  run_stage "S2"  "Alive probing"                   "$S2_BUDGET"  "stage_s2"
  run_stage "S3"  "URLs discovery"                  "$S3_BUDGET"  "stage_s3"
  run_stage "S4"  "Param Reflections (safe)"        "$S4_BUDGET"  "stage_s4"
  run_stage "S5"  "Classification (headers/tech/nikto/site-logic)" "$S5_BUDGET" "stage_s5"
  # Minimal Phase2X helpers (robots/cors/csp) before verification
  section "Phase2X helpers (minimal)"; stage_phase2x_minimal || true
  run_stage "S6"  "Nuclei (baseline + CVEs)"        "$S6_BUDGET"  "stage_s6"
  run_stage "S7"  "Deep scans (dalfox/sqlmap)"      "$S7_BUDGET"  "stage_s7"
  run_stage "S8"  "Hidden dirs/files + params (ffuf/dirsearch)" "$S8_BUDGET" "stage_s8"
  run_stage "S9"  "Ports/SSL (nmap)"                "$S9_BUDGET"  "stage_s9"
  run_stage "S10" "Classic Report"                  "$S10_BUDGET" "stage_s10"
  run_stage "S11" "Verification & Final Only"       "$S11_BUDGET" "stage_s11"

  # AI Learning & Improvements
  if [[ "$AI_ENABLE" == "y" ]]; then
    ai_learn_and_improve
  fi

  echo -e "${GREEN}${IC_DONE} [DONE] All stages completed. Artifacts in: $RUN_DIR${NC}"
  echo -e "${IC_BOOK} التقارير: $RUN_DIR/report.md  | $RUN_DIR/11_verification_final/final_report.md"
  echo -e "${IC_INFO} يمكنك الاستئناف لاحقًا بنفس الهدف—المراحل المُنجزة سيتم تخطيها تلقائيًا (RESUME=y)."
}

main "$@"
