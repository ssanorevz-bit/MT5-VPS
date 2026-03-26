#!/usr/bin/env bash
# sync_from_windows.sh
# ─────────────────────────────────────────────────────────────────
# ดึง CSV จาก Windows VPS/PC → Mac และจัดโฟลเดอร์ตามวันที่
# VPS structure:  MQL5/Files/dom/*.csv และ MQL5/Files/tick/*.csv
# Mac structure:  ~/data/YYYY-MM-DD/dom/*.csv และ tick/*.csv
# ─────────────────────────────────────────────────────────────────

WIN_HOST="windows-local"         # SSH alias ใน ~/.ssh/config
# MQL5 Files path บน Windows (adjust ถ้า terminal ID ต่างกัน)
WIN_MQL5="C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WIN_DOM="${WIN_MQL5}/dom"
WIN_TICK="${WIN_MQL5}/tick"

MAC_DATA="$HOME/data"            # root data folder บน Mac
DATE_TAG=$(date '+%Y-%m-%d')     # วันที่วันนี้ เช่น 2026-03-26
DEST="${MAC_DATA}/${DATE_TAG}"   # ~/data/2026-03-26/
LOG="$HOME/Developer/Quant-S/sync.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

# ── สร้าง destination folders ──────────────────────────────────────
mkdir -p "${DEST}/dom" "${DEST}/tick"

echo "" >> "$LOG"
echo "[${TS}] === เริ่ม sync ${DATE_TAG} ===" >> "$LOG"

# ── Sync DOM (6 files) ─────────────────────────────────────────────
echo "[${TS}] Syncing DOM..." >> "$LOG"
scp "${WIN_HOST}:${WIN_DOM}/*.csv" "${DEST}/dom/" >> "$LOG" 2>&1
DOM_STATUS=$?

# ── Sync Tick (2 files) ────────────────────────────────────────────
echo "[${TS}] Syncing Tick..." >> "$LOG"
scp "${WIN_HOST}:${WIN_TICK}/*.csv" "${DEST}/tick/" >> "$LOG" 2>&1
TICK_STATUS=$?

# ── สรุปผล ────────────────────────────────────────────────────────
TS2=$(date '+%Y-%m-%d %H:%M:%S')
DOM_COUNT=$(find  "${DEST}/dom"  -name "*.csv" 2>/dev/null | wc -l | tr -d ' ')
TICK_COUNT=$(find "${DEST}/tick" -name "*.csv" 2>/dev/null | wc -l | tr -d ' ')

if [ $DOM_STATUS -eq 0 ] && [ $TICK_STATUS -eq 0 ]; then
    echo "[${TS2}] ✅ sync สำเร็จ | dom=${DOM_COUNT} tick=${TICK_COUNT}" >> "$LOG"
    FINAL_STATUS=0
else
    echo "[${TS2}] ⚠️  dom_status=${DOM_STATUS} tick_status=${TICK_STATUS}" >> "$LOG"
    FINAL_STATUS=1
fi

# ── แสดงขนาดไฟล์แต่ละตัว ──────────────────────────────────────────
echo "[${TS2}] --- ขนาดไฟล์ ---" >> "$LOG"
find "${DEST}" -name "*.csv" -exec du -sh {} \; 2>/dev/null | sort >> "$LOG"
echo "[${TS2}] === จบ ===" >> "$LOG"

exit $FINAL_STATUS
