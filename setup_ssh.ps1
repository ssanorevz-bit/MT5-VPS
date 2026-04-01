# =============================================================
# setup_ssh.ps1 — ติดตั้ง OpenSSH Server บน Windows VPS
# =============================================================
# วิธีใช้ (PowerShell Administrator):
#   irm https://raw.githubusercontent.com/ssanorevz-bit/astfex/main/setup_ssh.ps1 | iex
#
# Fix v2: ดาวน์โหลดตรงจาก GitHub Releases
#         (ไม่ต้องพึ่ง Windows Update service)
# =============================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ติดตั้ง OpenSSH Server บน VPS (v2)"       -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# [1] ตรวจว่ามี sshd service อยู่แล้วหรือยัง
Write-Host "[1/4] ตรวจสอบ OpenSSH ..." -ForegroundColor Yellow
$sshdExists = Get-Service sshd -ErrorAction SilentlyContinue

if ($sshdExists) {
    Write-Host "      OpenSSH Server มีอยู่แล้ว — ข้ามการติดตั้ง" -ForegroundColor Green
} else {
    Write-Host "      ไม่พบ sshd — ดาวน์โหลดจาก GitHub Releases ..." -ForegroundColor Yellow

    # ดาวน์โหลด OpenSSH จาก Microsoft GitHub (ไม่ต้องใช้ Windows Update)
    $url  = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
    $zip  = "$env:TEMP\OpenSSH-Win64.zip"
    $dest = "C:\Program Files\OpenSSH"

    Write-Host "      กำลังดาวน์โหลด OpenSSH Win64 ..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Write-Host "      แตกไฟล์ไปที่ $dest ..." -ForegroundColor Yellow

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath "C:\Program Files\" -Force
    Rename-Item "C:\Program Files\OpenSSH-Win64" $dest -Force

    # ติดตั้ง service
    & "$dest\install-sshd.ps1"
    Write-Host "      OpenSSH Server ติดตั้งเสร็จ" -ForegroundColor Green
}

# [2] เปิดและตั้งให้รันอัตโนมัติ
Write-Host "[2/4] เปิด SSH Service + Auto Start ..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic'
$status = (Get-Service sshd).Status
Write-Host "      SSH Service: $status" -ForegroundColor Green

# [3] เพิ่ม PATH
Write-Host "[3/4] เพิ่ม PATH ..." -ForegroundColor Yellow
$sshPath = "C:\Program Files\OpenSSH"
$curPath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
if ($curPath -notlike "*OpenSSH*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$curPath;$sshPath", "Machine")
}
Write-Host "      PATH OK" -ForegroundColor Green

# [4] เปิด Firewall Port 22
Write-Host "[4/4] เปิด Firewall Port 22 ..." -ForegroundColor Yellow
$rule = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Port 22' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Write-Host "      Firewall Port 22: Open" -ForegroundColor Green

# แสดง IP และคำสั่ง SCP
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } |
       Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SSH Server พร้อมใช้งาน!" -ForegroundColor Green
Write-Host ""
Write-Host "  IP VPS : $ip" -ForegroundColor White
Write-Host ""
Write-Host "  รันบน Mac Terminal เพื่อดึง DOM CSV:" -ForegroundColor Yellow
Write-Host "  scp -r Administrator@${ip}:`"C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/*/MQL5/Files/dom/`" ~/Developer/Quant-S/data/vps_dom_raw/" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
