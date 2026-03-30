# =============================================================
# watchdog_vps.ps1 — MT5 + Collector Watchdog
# =============================================================
# รันอัตโนมัติทุก 5 นาที ผ่าน Task Scheduler
# ตรวจ: MT5 + Python collector ยังรันอยู่ไหม
# ถ้าตาย → restart อัตโนมัติ + บันทึก log
# =============================================================

$LOG    = "C:\quant-s\watchdog.log"
$MT5EXE = "$env:APPDATA\MetaQuotes\Terminal\*\terminal64.exe"
$DIR    = "C:\quant-s"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $msg" | Tee-Object -FilePath $LOG -Append
}

# ── ตรวจ Bangkok time (ช่วง session เท่านั้น) ──────────────────
$bkk  = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
            [DateTime]::UtcNow, "SE Asia Standard Time")
$hhmm = $bkk.Hour * 100 + $bkk.Minute
$isSession = (($hhmm -ge 900) -and ($hhmm -le 1700))  # 09:00-17:00

if (-not $isSession) {
    Log "[watchdog] นอก session ($bkk) — ข้าม"
    exit 0
}

Log "[watchdog] ตรวจสอบ session $bkk (hhmm=$hhmm)"

# ── 1. ตรวจ MT5 ─────────────────────────────────────────────
$mt5proc = Get-Process "terminal64" -ErrorAction SilentlyContinue
if (-not $mt5proc) {
    Log "[watchdog] ⚠️  MT5 ไม่รัน — กำลัง restart..."
    $mt5path = Get-Item "$env:APPDATA\MetaQuotes\Terminal\*\terminal64.exe" `
               -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($mt5path) {
        Start-Process $mt5path.FullName
        Start-Sleep 30   # รอ MT5 login
        Log "[watchdog] ✅ MT5 restarted: $($mt5path.FullName)"
    } else {
        Log "[watchdog] ❌ หา terminal64.exe ไม่เจอ — ตรวจสอบ MT5 installation"
    }
} else {
    Log "[watchdog] ✅ MT5 OK (PID=$($mt5proc.Id))"
}

# ── 2. ตรวจ Python Collector ─────────────────────────────────
$pyproc = Get-Process "python" -ErrorAction SilentlyContinue | 
          Where-Object { $_.CommandLine -like "*collect_mt5*" }

if (-not $pyproc) {
    Log "[watchdog] ⚠️  Collector ไม่รัน — กำลัง restart..."
    Start-Process "cmd" -ArgumentList "/c cd /d $DIR && python collect_mt5_tick_dom.py >> $DIR\collector.log 2>&1" -WindowStyle Hidden
    Start-Sleep 5
    $pyproc2 = Get-Process "python" -ErrorAction SilentlyContinue
    if ($pyproc2) {
        Log "[watchdog] ✅ Collector restarted (PID=$($pyproc2.Id))"
    } else {
        Log "[watchdog] ❌ Collector restart ล้มเหลว — ดู collector.log"
    }
} else {
    Log "[watchdog] ✅ Collector OK (PID=$($pyproc.Id))"
}

# ── 3. ตรวจ log size (ป้องกัน disk full) ───────────────────
$collLog = "C:\quant-s\collector.log"
if (Test-Path $collLog) {
    $sizeMB = (Get-Item $collLog).Length / 1MB
    if ($sizeMB -gt 100) {
        Rename-Item $collLog "$collLog.old" -Force
        Log "[watchdog] ⚠️  collector.log เกิน 100MB — rotate แล้ว"
    }
}

Log "[watchdog] ตรวจเสร็จ"
