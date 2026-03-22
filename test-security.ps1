# Security Test Script
# Tests if the secure server is blocking sensitive paths correctly

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   SECURITY TEST SUITE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$testUrl = "http://localhost:8080"
$passed = 0
$failed = 0

function Test-Endpoint {
    param(
        [string]$Path,
        [string]$Description,
        [int]$ExpectedStatus
    )
    
    try {
        $response = Invoke-WebRequest -Uri "$testUrl$Path" -Method Get -ErrorAction SilentlyContinue -TimeoutSec 3
        $status = $response.StatusCode
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
    }
    
    if ($status -eq $ExpectedStatus) {
        Write-Host "✅ PASS: $Description" -ForegroundColor Green
        Write-Host "   Path: $Path - Status: $status" -ForegroundColor Gray
        return $true
    } else {
        Write-Host "❌ FAIL: $Description" -ForegroundColor Red
        Write-Host "   Path: $Path - Expected: $ExpectedStatus, Got: $status" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "Testing legitimate paths (should return 200)..." -ForegroundColor Cyan
Write-Host ""

if (Test-Endpoint "/" "Homepage accessible" 200) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/robots.txt" "robots.txt accessible" 200) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/impressum.html" "Impressum accessible" 200) { $script:passed++ } else { $script:failed++ }

Write-Host ""
Write-Host "Testing blocked paths (should return 404)..." -ForegroundColor Cyan
Write-Host ""

if (Test-Endpoint "/.git/config" "Git config blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/.git/HEAD" "Git HEAD blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/.git/logs/HEAD" "Git logs blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/.env" "Environment file blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/.aws/credentials" "AWS credentials blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/backup.sql" "SQL backup blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/wp-login.php" "WordPress login blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/phpmyadmin/" "PHPMyAdmin blocked" 404) { $script:passed++ } else { $script:failed++ }
if (Test-Endpoint "/config.php" "Config file blocked" 404) { $script:passed++ } else { $script:failed++ }

Write-Host ""
Write-Host "Testing invalid methods (should return 405)..." -ForegroundColor Cyan
Write-Host ""

try {
    $response = Invoke-WebRequest -Uri "$testUrl/" -Method Post -ErrorAction SilentlyContinue -TimeoutSec 3
    $status = $response.StatusCode
} catch {
    $status = $_.Exception.Response.StatusCode.value__
}

if ($status -eq 405) {
    Write-Host "✅ PASS: POST method blocked" -ForegroundColor Green
    Write-Host "   Status: $status" -ForegroundColor Gray
    $script:passed++
} else {
    Write-Host "❌ FAIL: POST method not blocked correctly" -ForegroundColor Red
    Write-Host "   Expected: 405, Got: $status" -ForegroundColor Yellow
    $script:failed++
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   TEST RESULTS" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "✅ Passed: $passed" -ForegroundColor Green
Write-Host "❌ Failed: $failed" -ForegroundColor Red
Write-Host ""

if ($failed -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! Security is working!" -ForegroundColor Green
    Write-Host "   Your server is properly blocking sensitive paths." -ForegroundColor Green
} else {
    Write-Host "⚠️  SOME TESTS FAILED!" -ForegroundColor Yellow
    Write-Host "   Make sure you're running secure_server.py!" -ForegroundColor Yellow
    Write-Host "   Restart with: .\start-rinnenprofi.ps1" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan




