# Rinnenprofi Website Starter
# This script starts the Python web server and Cloudflare tunnel
$ErrorActionPreference = "Stop"

try {
    # Set working directory
    Set-Location -Path $PSScriptRoot
    
    # Log startup information
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   STARTING RINNENPROFI WEBSITE" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date)" -ForegroundColor White
    Write-Host "Working Directory: $(Get-Location)" -ForegroundColor White
    Write-Host "Website: https://rinnenprofi-muc.de" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if Python is available
    $pythonCmd = $null
    foreach ($cmd in @("python", "py")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            $pythonCmd = $cmd
            $pythonVersion = & $cmd --version 2>&1
            Write-Host "✅ Python found: $pythonVersion" -ForegroundColor Green
            break
        }
    }
    
    if (-not $pythonCmd) {
        Write-Host "❌ CRITICAL: Python not found!" -ForegroundColor Red
        Write-Host "   Install Python before starting!" -ForegroundColor Red
        Write-Host "   Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    # Check if cloudflared is available
    if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
        $cloudflaredVersion = & cloudflared --version 2>&1 | Select-Object -First 1
        Write-Host "✅ Cloudflared found: $cloudflaredVersion" -ForegroundColor Green
    } else {
        Write-Host "❌ CRITICAL: Cloudflared not found in PATH!" -ForegroundColor Red
        Write-Host "   Install cloudflared before starting!" -ForegroundColor Red
        Write-Host "   Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    # Check if port 8080 is already in use and free it automatically
    $portInUse = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
    if ($portInUse) {
        Write-Host "⚠️  Port 8080 is in use. Freeing it automatically..." -ForegroundColor Yellow
        foreach ($conn in $portInUse) {
            $processId = $conn.OwningProcess
            $processName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
            Write-Host "   Stopping process: $processName (PID: $processId)" -ForegroundColor Yellow
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        Write-Host "   ✅ Port 8080 is now free!" -ForegroundColor Green
    }
    
    # Also stop any existing cloudflared tunnels
    $cloudflaredProcesses = Get-Process -Name cloudflared -ErrorAction SilentlyContinue
    if ($cloudflaredProcesses) {
        Write-Host "⚠️  Stopping existing Cloudflare tunnels..." -ForegroundColor Yellow
        Stop-Process -Name cloudflared -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Write-Host "   ✅ Existing tunnels stopped!" -ForegroundColor Green
    }
    
    # Clean up any existing PowerShell background jobs
    $existingJobs = Get-Job -ErrorAction SilentlyContinue
    if ($existingJobs) {
        Write-Host "⚠️  Cleaning up old background jobs..." -ForegroundColor Yellow
        Stop-Job * -ErrorAction SilentlyContinue
        Remove-Job * -ErrorAction SilentlyContinue
        Write-Host "   ✅ Background jobs cleaned!" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Starting services..." -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Get full path to Python executable, avoiding Windows Store stub
    $pythonFullPath = (Get-Command $pythonCmd -ErrorAction SilentlyContinue).Source
    
    # Check if it's the Windows Store stub (bad!)
    if ($pythonFullPath -like "*WindowsApps*") {
        Write-Host "   ⚠️  Warning: Found Windows Store stub, searching for real Python..." -ForegroundColor Yellow
        # Try to find the real Python using pip
        try {
            $pipPath = (Get-Command pip -ErrorAction Stop).Source
            $realPythonPath = Split-Path -Parent $pipPath
            $pythonFullPath = Join-Path (Split-Path -Parent $realPythonPath) "python.exe"
            if (-not (Test-Path $pythonFullPath)) {
                # Try Scripts folder location
                $pythonFullPath = Join-Path (Split-Path -Parent (Split-Path -Parent $pipPath)) "python.exe"
            }
        } catch {
            Write-Host "   ❌ Could not find real Python installation!" -ForegroundColor Red
            throw "Python installation not found. Please install Python from python.org"
        }
    }
    
    Write-Host "   Using Python: $pythonFullPath" -ForegroundColor White
    
    # Start Secure Python HTTP Server in background
    Write-Host "🌐 Starting SECURE Python web server on port 8080..." -ForegroundColor Cyan
    $serverJob = Start-Job -ScriptBlock {
        param($workDir, $pythonPath)
        try {
            Set-Location $workDir
            # Run Python unbuffered for real-time logging
            & $pythonPath -u secure_server.py 2>&1
        } catch {
            Write-Error "Server error: $_"
            throw
        }
    } -ArgumentList $PSScriptRoot, $pythonFullPath
    
    Start-Sleep -Seconds 3
    
    if ($serverJob.State -eq "Running") {
        Write-Host "   ✅ Web server started (Job ID: $($serverJob.Id))" -ForegroundColor Green
        # Verify it's actually listening
        Start-Sleep -Seconds 1
        $listening = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
        if (-not $listening) {
            Write-Host "   ⚠️  Warning: Port 8080 not listening yet..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ❌ Web server failed to start!" -ForegroundColor Red
        $errors = Receive-Job $serverJob 2>&1
        Write-Host "   Error: $errors" -ForegroundColor Red
        throw "Failed to start web server"
    }
    
    Write-Host ""
    Write-Host "🔗 Starting Cloudflare tunnel..." -ForegroundColor Cyan
    
    # Try named tunnel first, fallback to quick tunnel
    $useQuickTunnel = $false
    
    # Check if tunnel credentials exist
    $tunnelExists = cloudflared tunnel list 2>&1 | Select-String "rinnenprofi-tunnel"
    
    if ($tunnelExists) {
        Write-Host "   Trying named tunnel (rinnenprofi-tunnel)..." -ForegroundColor Cyan
        $tunnelJob = Start-Job -ScriptBlock {
            cloudflared tunnel --protocol http2 run d9b07728-f3d8-48d1-b685-4657b308e0cd 2>&1
        }
        Start-Sleep -Seconds 5
        
        if ($tunnelJob.State -ne "Running") {
            Write-Host "   ⚠️  Named tunnel failed, switching to quick tunnel..." -ForegroundColor Yellow
            Stop-Job $tunnelJob -ErrorAction SilentlyContinue
            Remove-Job $tunnelJob -ErrorAction SilentlyContinue
            $useQuickTunnel = $true
        }
    } else {
        Write-Host "   Named tunnel not configured, using quick tunnel..." -ForegroundColor Yellow
        $useQuickTunnel = $true
    }
    
    # Start quick tunnel if needed
    if ($useQuickTunnel) {
        $tunnelJob = Start-Job -ScriptBlock {
            cloudflared tunnel --url http://127.0.0.1:8080 --protocol http2 2>&1
        }
        Start-Sleep -Seconds 5
    }
    
    if ($tunnelJob.State -eq "Running") {
        Write-Host "   ✅ Cloudflare tunnel started (Job ID: $($tunnelJob.Id))" -ForegroundColor Green
        
        # If using quick tunnel, extract the URL
        if ($useQuickTunnel) {
            Start-Sleep -Seconds 3
            $tunnelOutput = Receive-Job $tunnelJob -Keep 2>&1 | Out-String
            $urlMatch = $tunnelOutput | Select-String -Pattern "https://[a-z0-9-]+\.trycloudflare\.com"
            if ($urlMatch) {
                $quickTunnelUrl = $urlMatch.Matches[0].Value
                Write-Host "   🌐 Quick Tunnel URL: $quickTunnelUrl" -ForegroundColor Yellow
                Write-Host "   ⚠️  Note: This URL changes on each restart!" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "   ❌ Cloudflare tunnel failed to start!" -ForegroundColor Red
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -ErrorAction SilentlyContinue
        throw "Failed to start Cloudflare tunnel"
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "   ✅ RINNENPROFI WEBSITE IS LIVE!" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""
    if (-not $useQuickTunnel) {
        Write-Host "🌐 Website: https://rinnenprofi-muc.de" -ForegroundColor Yellow
    } else {
        if ($quickTunnelUrl) {
            Write-Host "🌐 Website: $quickTunnelUrl" -ForegroundColor Yellow
        }
        Write-Host "⚠️  Using temporary tunnel URL (changes on restart)" -ForegroundColor Yellow
    }
    Write-Host "🔧 Local: http://localhost:8080" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📊 Service Status:" -ForegroundColor White
    Write-Host "   - Python Server (Job $($serverJob.Id)): RUNNING" -ForegroundColor Green
    Write-Host "   - Cloudflare Tunnel (Job $($tunnelJob.Id)): RUNNING" -ForegroundColor Green
    Write-Host ""
    Write-Host "⚠️  DO NOT CLOSE THIS WINDOW!" -ForegroundColor Red
    Write-Host "   Closing this window will stop the website." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press Ctrl+C to stop all services and exit..." -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Keep window open and monitor jobs with live logs
    $lastServerOutput = ""
    $lastTunnelOutput = ""
    
    while ($true) {
        Start-Sleep -Seconds 2
        
        # Check if jobs are still running
        if ($serverJob.State -ne "Running") {
            Write-Host ""
            Write-Host "❌ Web server stopped unexpectedly!" -ForegroundColor Red
            Write-Host "Server state: $($serverJob.State)" -ForegroundColor Yellow
            Write-Host "Last output:" -ForegroundColor Yellow
            Receive-Job $serverJob 2>&1 | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            break
        }
        
        if ($tunnelJob.State -ne "Running") {
            Write-Host ""
            Write-Host "❌ Cloudflare tunnel stopped unexpectedly!" -ForegroundColor Red
            Write-Host "Tunnel state: $($tunnelJob.State)" -ForegroundColor Yellow
            Write-Host "Last output:" -ForegroundColor Yellow
            Receive-Job $tunnelJob 2>&1 | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            break
        }
        
        # Get new output from server job (more aggressive display)
        $serverOutput = Receive-Job $serverJob -Keep 2>&1 | Out-String
        if ($serverOutput -and $serverOutput -ne $lastServerOutput) {
            $newLines = $serverOutput.Substring($lastServerOutput.Length)
            if ($newLines.Trim()) {
                # Display each line with timestamp
                $newLines.Trim() -split "`n" | ForEach-Object {
                    if ($_.Trim()) {
                        Write-Host "[WEB SERVER] " -ForegroundColor Cyan -NoNewline
                        Write-Host $_
                    }
                }
            }
            $lastServerOutput = $serverOutput
        }
        
        # Get new output from tunnel job (only show important lines)
        $tunnelOutput = Receive-Job $tunnelJob -Keep 2>&1 | Out-String
        if ($tunnelOutput -and $tunnelOutput -ne $lastTunnelOutput) {
            $newLines = $tunnelOutput.Substring($lastTunnelOutput.Length)
            # Filter to show only important tunnel messages
            $importantLines = $newLines -split "`n" | Where-Object { 
                $_ -match "Registered tunnel|Updated to new configuration|Request failed|ERR|WRN" 
            }
            foreach ($line in $importantLines) {
                if ($line.Trim()) {
                    Write-Host "[TUNNEL] " -ForegroundColor Yellow -NoNewline
                    Write-Host $line.Trim()
                }
            }
            $lastTunnelOutput = $tunnelOutput
        }
    }
    
    # If we get here, something failed
    Write-Host ""
    Write-Host "Stopping all services..." -ForegroundColor Yellow
    Stop-Job $serverJob -ErrorAction SilentlyContinue
    Stop-Job $tunnelJob -ErrorAction SilentlyContinue
    Remove-Job $serverJob -ErrorAction SilentlyContinue
    Remove-Job $tunnelJob -ErrorAction SilentlyContinue
    
    Write-Host "Services stopped. Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
catch {
    # This code executes if there's an error
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host "ERROR STARTING WEBSITE:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host ""
    
    # Cleanup jobs
    Get-Job | Where-Object { $_.Name -like "*" } | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Where-Object { $_.Name -like "*" } | Remove-Job -ErrorAction SilentlyContinue
    
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
finally {
    # Ensure jobs are cleaned up
    Get-Job | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -ErrorAction SilentlyContinue
}

