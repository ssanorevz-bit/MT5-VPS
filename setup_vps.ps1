# =============================================================
# setup_vps.ps1 — Linode VPS Auto Setup (ไม่รวม MT5)
# =============================================================
# วิธีใช้ (PowerShell Administrator):
#   irm https://raw.githubusercontent.com/ssanorevz-bit/MT5-VPS/main/setup_vps.ps1 | iex
# =============================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VPS Setup — Quant Collector"              -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# [1] สร้าง folder
New-Item -ItemType Directory -Force -Path C:\quant     | Out-Null
New-Item -ItemType Directory -Force -Path C:\quant-s\data | Out-Null
Write-Host "[1/7] folders OK" -ForegroundColor Green

# [2] ติดตั้ง Python 3.11
Write-Host "[2/7] ดาวน์โหลด + ติดตั้ง Python 3.11 ..." -ForegroundColor Yellow
$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCheck) {
    Write-Host "[2/7] Python มีอยู่แล้ว: $($pythonCheck.Source)" -ForegroundColor Green
} else {
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile "$env:TEMP\py.exe" -UseBasicParsing
    Start-Process "$env:TEMP\py.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "[2/7] Python OK" -ForegroundColor Green
}

# [3] pip packages + download collector script
Write-Host "[3/7] ติดตั้ง packages + ดาวน์โหลด script ..." -ForegroundColor Yellow
python -m pip install MetaTrader5 pandas pyarrow -q
curl -o "C:\quant\collect_mt5_tick_dom.py" "https://raw.githubusercontent.com/ssanorevz-bit/MT5-VPS/main/collect_mt5_tick_dom.py"
Write-Host "[3/7] packages + script OK" -ForegroundColor Green

# [4] ดาวน์โหลด MT5 Pi Securities
Write-Host "[4/7] ดาวน์โหลด MT5 Pi Securities ..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "https://download.mql5.com/cdn/web/21687/mt5/pisecurities5setup.exe" -OutFile "C:\quant\pisecurities5setup.exe" -UseBasicParsing
Write-Host "[4/7] MT5 installer OK -> C:\quant\pisecurities5setup.exe" -ForegroundColor Green

# [5] ติดตั้ง rclone (สำหรับ sync ข้อมูลขึ้น Google Drive)
Write-Host "[5/7] ติดตั้ง rclone ..." -ForegroundColor Yellow
$rcloneCheck = Get-Command rclone -ErrorAction SilentlyContinue
if ($rcloneCheck) {
    Write-Host "[5/7] rclone มีอยู่แล้ว" -ForegroundColor Green
} else {
    Invoke-WebRequest -Uri "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile "$env:TEMP\rclone.zip" -UseBasicParsing
    Expand-Archive "$env:TEMP\rclone.zip" -DestinationPath "$env:TEMP\rclone" -Force
    $rcloneExe = Get-ChildItem "$env:TEMP\rclone" -Recurse -Filter "rclone.exe" | Select-Object -First 1
    Copy-Item $rcloneExe.FullName "C:\Windows\System32\rclone.exe"
    Write-Host "[5/7] rclone OK" -ForegroundColor Green
}

# [6] สร้าง upload script (รัน rclone sync หลังตลาดปิด)
Write-Host "[6/7] สร้าง upload_gdrive.ps1 ..." -ForegroundColor Yellow
$uploadScript = @'
# upload_gdrive.ps1 — sync ข้อมูลขึ้น Google Drive
# ต้อง rclone config ก่อน 1 ครั้ง: rclone config -> n -> gdrive -> Google Drive

$dataDir  = "C:\quant-s\data"
$logFile  = "C:\quant-s\upload.log"
$remote   = "gdrive:/VPS-Data"

"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting upload..." | Tee-Object -FilePath $logFile -Append
rclone sync $dataDir $remote --progress --log-file $logFile --log-level INFO
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Upload complete!" | Tee-Object -FilePath $logFile -Append
'@
$uploadScript | Out-File "C:\quant\upload_gdrive.ps1" -Encoding UTF8
Write-Host "[6/7] upload_gdrive.ps1 OK" -ForegroundColor Green

# [7] ตั้ง Task Scheduler
Write-Host "[7/7] ตั้ง Task Scheduler ..." -ForegroundColor Yellow

# MT5Collector — รันตอน boot
schtasks /delete /tn MT5Collector /f 2>$null
schtasks /create /tn MT5Collector /tr "python C:\quant\collect_mt5_tick_dom.py" /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Null
schtasks /run /tn MT5Collector | Out-Null
Write-Host "  MT5Collector task OK (background)" -ForegroundColor Green

# UploadGDrive — รัน 17:15 ทุกวัน (หลังตลาดปิด)
schtasks /delete /tn UploadGDrive /f 2>$null
schtasks /create /tn UploadGDrive /tr "powershell -ExecutionPolicy Bypass -File C:\quant\upload_gdrive.ps1" /sc daily /st 17:00 /ru SYSTEM /f | Out-Null
Write-Host "  UploadGDrive task OK (17:00 daily)" -ForegroundColor Green
Write-Host "[7/7] Task Scheduler OK" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup เสร็จ!" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. ติดตั้ง MT5 : C:\quant\pisecurities5setup.exe" -ForegroundColor White
Write-Host "  2. Config rclone (1 ครั้ง): rclone config" -ForegroundColor White
Write-Host "     -> n -> gdrive -> drive (Google Drive) -> ทำตาม URL" -ForegroundColor White
Write-Host "  3. ทดสอบ sync  : powershell C:\quant\upload_gdrive.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  เช็ค collector : Get-ScheduledTask MT5Collector | Select State" -ForegroundColor White
Write-Host "  ดู log         : Get-Content C:\quant-s\collector.log -Tail 20 -Wait" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
