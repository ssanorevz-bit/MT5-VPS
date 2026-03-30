# =============================================================
# setup_vps.ps1 — VPS Auto Setup  v2
# =============================================================
# วิธีใช้ (PowerShell Administrator):
#   irm https://raw.githubusercontent.com/ssanorevz-bit/astfex/main/setup_vps.ps1 | iex
# Fix: ใช้ Invoke-WebRequest แทน curl alias (PowerShell compat)
# =============================================================

# Helper function แทน curl
function Download-File($url, $dest) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

$REPO = "https://raw.githubusercontent.com/ssanorevz-bit/astfex/main"
$DIR  = "C:\quant-s"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VPS Setup — Quant Collector"              -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# [0] Timezone + Sync
Write-Host "[0/5] ตั้ง Timezone Bangkok + Sync เวลา ..." -ForegroundColor Yellow
Set-TimeZone -Id "SE Asia Standard Time"
w32tm /resync /force | Out-Null
Write-Host "      Timezone: $((Get-TimeZone).DisplayName)" -ForegroundColor Green
Write-Host "      เวลา: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green

# [1] สร้าง folders
Write-Host "[1/5] สร้าง folders ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$DIR\data" | Out-Null
Write-Host "      $DIR\data OK" -ForegroundColor Green

# [2] ติดตั้ง Python 3.11
Write-Host "[2/5] ตรวจสอบ Python ..." -ForegroundColor Yellow
$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCheck) {
    Write-Host "      Python มีอยู่แล้ว: $($pythonCheck.Source)" -ForegroundColor Green
} else {
    Write-Host "      ดาวน์โหลด Python 3.11 ..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" `
        -OutFile "$env:TEMP\py.exe" -UseBasicParsing
    Start-Process "$env:TEMP\py.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "      Python 3.11 OK" -ForegroundColor Green
}

# [3] pip packages + download collector
Write-Host "[3/5] ติดตั้ง packages + ดาวน์โหลด scripts ..." -ForegroundColor Yellow
python -m pip install MetaTrader5 pandas pyarrow -q

# Download Python collector
Download-File "$REPO/collect_mt5_tick_dom.py" "$DIR\collect_mt5_tick_dom.py"
Write-Host "      collect_mt5_tick_dom.py OK" -ForegroundColor Green

# Download watchdog
Download-File "$REPO/watchdog_vps.ps1" "$DIR\watchdog_vps.ps1"
Write-Host "      watchdog_vps.ps1 OK" -ForegroundColor Green

# Download run_collector.bat
Download-File "$REPO/run_collector.bat" "$DIR\run_collector.bat"
Write-Host "      run_collector.bat OK" -ForegroundColor Green

# Download EA ทุกตัว (DOM x6 + Tick x2)
$EAs = @(
    "DOM_S50IF.mq5",
    "DOM_Delta.mq5",
    "DOM_High.mq5",
    "DOM_Options.mq5",
    "DOM_Stocks_A.mq5",
    "DOM_Stocks_B.mq5",
    "Tick_TFEX.mq5",
    "Tick_Stocks.mq5"
)
foreach ($ea in $EAs) {
    Download-File "$REPO/$ea" "$DIR\$ea"
    $size = (Get-Item "$DIR\$ea").Length
    Write-Host "      $ea OK ($size bytes)" -ForegroundColor Green
}
Write-Host "[3/5] packages + scripts OK" -ForegroundColor Green

# [4] ดาวน์โหลด MT5 Pi Securities
Write-Host "[4/5] ดาวน์โหลด MT5 Pi Securities ..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "https://download.mql5.com/cdn/web/21687/mt5/pisecurities5setup.exe" `
    -OutFile "$DIR\pisecurities5setup.exe" -UseBasicParsing
Write-Host "      MT5 installer -> $DIR\pisecurities5setup.exe" -ForegroundColor Green

# [5] Task Scheduler — collector + watchdog
Write-Host "[5/5] ตั้ง Task Scheduler ..." -ForegroundColor Yellow

# 5a. Collector: รันทุกครั้งที่ boot
schtasks /delete /tn MT5Collector /f 2>$null
$action = "cmd /c cd /d C:\quant-s && python collect_mt5_tick_dom.py >> C:\quant-s\collector.log 2>&1"
schtasks /create /tn MT5Collector /tr $action /sc onstart /ru Administrator /rl HIGHEST /f | Out-Null
Write-Host "      MT5Collector task OK (runs on boot)" -ForegroundColor Green

# 5b. Watchdog: รันทุก 5 นาที (ตรวจ MT5 + Collector ยังอยู่ไหม → restart ถ้าตาย)
schtasks /delete /tn MT5Watchdog /f 2>$null
$wdAction = "powershell -ExecutionPolicy Bypass -File C:\quant-s\watchdog_vps.ps1"
schtasks /create /tn MT5Watchdog /tr $wdAction /sc minute /mo 5 /ru Administrator /rl HIGHEST /f | Out-Null
Write-Host "      MT5Watchdog task OK (runs every 5 min)" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup เสร็จ!" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. ติดตั้ง MT5  : $DIR\pisecurities5setup.exe" -ForegroundColor White
Write-Host "  2. Login MT5 + OTP" -ForegroundColor White
Write-Host "  3. Copy EA ไปที่ : MT5 -> File -> Open Data Folder -> MQL5\Experts" -ForegroundColor White
Write-Host "     (EA files อยู่ที่ $DIR\*.mq5)" -ForegroundColor Gray
Write-Host "  4. Compile EA   : MetaEditor -> เปิดทีละตัว -> F7 (8 ตัว)" -ForegroundColor White
Write-Host "  5. ลาก EA ลงกราฟ: DOM x6 + Tick x2 (1 EA = 1 chart)" -ForegroundColor White
Write-Host "  6. Run collector: double-click $DIR\run_collector.bat" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ✅ Watchdog จะ restart MT5+Collector อัตโนมัติทุก 5 นาที" -ForegroundColor Green
Write-Host ""
Write-Host "  ดึงข้อมูลกลับ Mac (รันบน Mac Terminal):" -ForegroundColor Yellow
Write-Host "  scp -r Administrator@<VPS_IP>:C:/quant-s/data/ ~/Developer/Quant-S/data/vps/" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
