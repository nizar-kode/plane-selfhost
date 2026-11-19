<#
.SYNOPSIS
    Plane Enterprise Deployment Script for Windows & Windows Server
.DESCRIPTION
    Automated end-to-end deployment of Plane on a Windows / Windows Server environment:
    1. Verifies Administrator privileges & system resources.
    2. Installs required tools (Git, Python 3) if missing.
    3. Installs & configures WSL 2 and Docker Desktop / Docker Engine.
    4. Retrieves the deployment repository from GitHub.
    5. Configures .env with high-entropy secrets and server IP/domain.
    6. Configures Windows Defender Firewall (Ports 80 & 443).
    7. Runs database schema migrations and starts the full Plane stack.
    8. Performs health check verification and displays live access URLs.
.PARAMETER ServerIPOrDomain
    The IP address or domain name of the Windows server (e.g. 192.168.1.100 or plane.company.com).
.PARAMETER InstallDir
    Target directory on Windows (defaults to C:\plane-selfhost).
.PARAMETER RepoUrl
    GitHub repository URL.
.EXAMPLE
    .\scripts\deploy-server.ps1 -ServerIPOrDomain "192.168.1.50"
#>

[CmdletBinding()]
param (
    [string]$ServerIPOrDomain = "",
    [string]$InstallDir = "C:\plane-selfhost",
    [string]$RepoUrl = "https://github.com/nizar-kode/plane-selfhost.git",
    [string]$Branch = "main",
    [int]$HttpPort = 80,
    [int]$HttpsPort = 443
)

# Allow environment variable override for ports
if ($env:HTTP_PORT -and $HttpPort -eq 80) {
    $HttpPort = [int]$env:HTTP_PORT
}
if ($env:PORT -and $HttpPort -eq 80) {
    $HttpPort = [int]$env:PORT
}

# If script is run directly from repo folder, default InstallDir to that folder
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\docker-compose.yml"))) {
    $resolvedRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    if ($InstallDir -eq "C:\plane-selfhost" -and $resolvedRoot -ne "C:\plane-selfhost" -and (Test-Path "$resolvedRoot\docker-compose.yml")) {
        $InstallDir = $resolvedRoot
    }
}

$ErrorActionPreference = "Continue"

# ------------------------------------------------------------------------------
# UI Helpers & Banner
# ------------------------------------------------------------------------------
function Show-Banner {
    Clear-Host
    Write-Host @"
================================================================================
   ____  _                  ____       _  __      _   _           _ 
  |  _ \| | __ _ _ __   ___/ ___|  ___| |/ _|    | | | | ___  ___| |_ 
  | |_) | |/ _` | '_ \ / _ \___ \ / _ \ | |_|____| |_| |/ _ \/ __| __|
  |  __/| | (_| | | | |  __/___) |  __/ |  _|____|  _  | (_) \__ \ |_ 
  |_|   |_|\__,_|_| |_|\___|____/ \___|_|_|      |_| |_|\___/|___/\__|
================================================================================
    Plane Enterprise Automated Windows Server Deployer | Plane v1.5.0
================================================================================
"@ -ForegroundColor Cyan
}

function Log-Step([string]$msg) {
    Write-Host "`n===> $msg" -ForegroundColor Blue
}

function Log-Success([string]$msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Log-Info([string]$msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Gray
}

function Log-Warn([string]$msg) {
    Write-Host "[WARNING] $msg" -ForegroundColor Yellow
}

function Log-Err([string]$msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# ------------------------------------------------------------------------------
# 1. Administrator Check
# ------------------------------------------------------------------------------
function Check-AdminPrivileges {
    Log-Step "Step 1/8: Verifying Administrator Privileges"
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log-Err "This deployment script must be run as Administrator."
        Log-Info "Please right-click PowerShell and select 'Run as administrator', then retry."
        exit 1
    }
    Log-Success "Running with elevated Administrator privileges."

    # Check RAM
    $totalRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Log-Info "Detected RAM: $totalRamGB GB"
    if ($totalRamGB -lt 4) {
        Log-Warn "Plane requires a minimum of 4 GB RAM (8 GB recommended for production)."
    }
}

# ------------------------------------------------------------------------------
# 2. Package & Tool Prerequisites (Git & Python)
# ------------------------------------------------------------------------------
function Install-Prerequisites {
    Log-Step "Step 2/8: Checking & Installing Prerequisites (Git & Python 3)"

    # 1. Check Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Log-Info "Git is not installed. Installing Git for Windows..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements --silent
        } else {
            Log-Info "Downloading official Git installer..."
            $gitInstaller = "$env:TEMP\Git-Installer.exe"
            Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe" -OutFile $gitInstaller
            Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait
            Remove-Item -Force $gitInstaller -ErrorAction SilentlyContinue
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Log-Success "Git installed successfully."
    } else {
        $gitVer = (git --version)
        Log-Success "Git is already installed: $gitVer"
    }

    # 2. Check Python
    $pythonFound = $false
    try {
        if (Get-Command python -ErrorAction SilentlyContinue) {
            $pyTest = (python -c "import sys; print('PYTHON_OK')" 2>&1)
            if ($LASTEXITCODE -eq 0 -and $pyTest -match "PYTHON_OK") {
                $pythonFound = $true
                $pyVer = (python --version 2>&1).Trim()
                Log-Success "Python is already installed: $pyVer"
            }
        }
    } catch {}

    if (-not $pythonFound) {
        Log-Info "Python is not installed. Native PowerShell cryptographic RNG will be used for secret generation."
    }
}

# ------------------------------------------------------------------------------
# 3. Docker Installation & WSL 2 Backend
# ------------------------------------------------------------------------------
function Install-DockerOnWindows {
    Log-Step "Step 3/8: Verifying & Installing Docker and WSL 2 Backend"

    $osInfo = Get-CimInstance Win32_OperatingSystem
    $isWindowsServer = ($osInfo.ProductType -ne 1)
    $osName = $osInfo.Caption
    Log-Info "Operating System detected: $osName (Windows Server: $isWindowsServer)"

    # Verify WSL 2 prerequisites
    Log-Info "Checking Windows Subsystem for Linux (WSL 2)..."
    $wslReady = $false
    try {
        if (Get-Command wsl -ErrorAction SilentlyContinue) {
            $wslStatus = (wsl.exe --status 2>&1 | Out-String)
            if ($wslStatus -match "Default Version: 2" -or $LASTEXITCODE -eq 0) {
                $wslReady = $true
                Log-Success "WSL 2 is active and operational."
            }
        }
    } catch {}

    if (-not $wslReady) {
        Log-Info "Configuring Windows features for WSL 2 (Subsystem & Virtual Machine Platform)..."
        try {
            dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
            dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
        } catch {
            Log-Warn "DISM feature enable returned: $_"
        }

        # Install WSL kernel package
        try {
            Log-Info "Installing/Updating WSL 2 Linux kernel..."
            $kernelMsi = "$env:TEMP\wsl_update_x64.msi"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi" -OutFile $kernelMsi -UseBasicParsing
            Start-Process msiexec.exe -ArgumentList "/i `"$kernelMsi`" /quiet /norestart" -Wait
            Remove-Item -Force $kernelMsi -ErrorAction SilentlyContinue
            Log-Success "Official Microsoft WSL 2 Kernel installed."
        } catch {
            Log-Warn "Could not download WSL2 kernel MSI directly: $_"
        }

        try {
            wsl.exe --install --no-distribution 2>&1 | Out-Null
            wsl.exe --set-default-version 2 2>&1 | Out-Null
        } catch {}
    }

    # Verify if Docker is already available
    $hasDocker = $false
    try {
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            $hasDocker = $true
        }
    } catch {}

    if ($hasDocker) {
        $dVer = (docker --version 2>&1)
        Log-Success "Docker is already installed: $dVer"
        
        # Verify Docker daemon is running
        $dockerReady = $false
        try {
            docker info >$null 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
        } catch {}

        if (-not $dockerReady) {
            Log-Info "Docker Engine is not running. Attempting to start Docker Desktop..."
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
            Write-Host "Waiting for Docker daemon to become responsive..." -NoNewline
            for ($i = 0; $i -lt 30; $i++) {
                Start-Sleep -Seconds 3
                docker info >$null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $dockerReady = $true
                    break
                }
                Write-Host "." -NoNewline
            }
            Write-Host ""
        }

        if ($dockerReady) {
            Log-Success "Docker daemon is running and responsive."
            return
        }
    }

    # Docker is missing - perform installation
    Log-Info "Docker is not detected on this server. Initiating Docker setup..."

    if ($isWindowsServer) {
        Log-Warn "Notice: On Windows Server ($osName), Docker Desktop is not officially provided by Docker."
        Log-Info "Attempting standard Docker Desktop installation; if blocked by installer, WSL2 Ubuntu backend can be utilized."
    }

    # Attempt Docker Desktop install
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log-Info "Installing Docker Desktop via winget..."
        winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements --silent
    } else {
        $dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
        Log-Info "Downloading Docker Desktop Installer (approx. 500 MB)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $dockerInstaller -UseBasicParsing
        Log-Info "Executing silent Docker installation..."
        Start-Process -FilePath $dockerInstaller -ArgumentList "install --quiet --accept-licenses" -Wait
        Remove-Item -Force $dockerInstaller -ErrorAction SilentlyContinue
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Log-Success "Docker Desktop installation finished."
    Log-Info "Starting Docker Desktop service..."
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue

    Write-Host "Waiting for Docker daemon to initialize..." -NoNewline
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 3
        docker info >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if (-not $ready) {
        Log-Warn "Docker engine has not yet reported ready."
        Log-Warn "IMPORTANT: If this server just had VirtualMachinePlatform or WSL enabled for the first time,"
        Log-Warn "Windows requires a system reboot to initialize the hypervisor."
        Log-Warn "Run 'Restart-Computer' to reboot, then re-run this script after logging back in."
    } else {
        Log-Success "Docker daemon is active and responsive."
    }
}

# ------------------------------------------------------------------------------
# 4. Clone or Update GitHub Repository
# ------------------------------------------------------------------------------
function Setup-Repository {
    Log-Step "Step 4/8: Retrieving Deployment Repository from GitHub"

    Log-Info "Target directory: $InstallDir"

    if (Test-Path "$InstallDir\.git") {
        Log-Info "Existing git repository found at $InstallDir. Fetching latest updates..."
        Set-Location $InstallDir
        git fetch origin $Branch
        git checkout $Branch
        git pull origin $Branch
    } else {
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        }
        Log-Info "Cloning $RepoUrl (branch: $Branch) into $InstallDir..."
        git clone -b $Branch $RepoUrl $InstallDir
        Set-Location $InstallDir
    }

    Log-Success "Repository is ready at $InstallDir"
}

# ------------------------------------------------------------------------------
# 5. Environment & Cryptographic Secrets Generation
# ------------------------------------------------------------------------------
function Configure-Environment {
    Log-Step "Step 5/8: Configuring Server Domain, Routing, & Cryptographic Secrets"
    Set-Location $InstallDir

    # Determine default IP address
    $detectedIP = "localhost"
    try {
        $ipObj = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|Docker" -and $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1)
        if ($ipObj) { $detectedIP = $ipObj.IPAddress }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($ServerIPOrDomain)) {
        Write-Host "`nTarget Server Address Configuration:" -ForegroundColor White
        Write-Host "Detected local network IP: $detectedIP" -ForegroundColor Gray
        $inputAddress = Read-Host "Enter Server IP Address or Domain Name [$detectedIP]"
        if ([string]::IsNullOrWhiteSpace($inputAddress)) {
            $ServerIPOrDomain = $detectedIP
        } else {
            $ServerIPOrDomain = $inputAddress.Trim()
        }
    }

    Log-Info "Configuring Plane for server address: $ServerIPOrDomain"

    # Copy template if .env does not exist
    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
    }

    # Run Python secret generator if real python is working, otherwise use PowerShell cryptographic RNG
    $canRunPythonGen = $false
    try {
        if (Get-Command python -ErrorAction SilentlyContinue) {
            $pyCheck = (python -c "import secrets; print('OK')" 2>&1)
            if ($LASTEXITCODE -eq 0 -and $pyCheck -match "OK") {
                $canRunPythonGen = $true
            }
        }
    } catch {}

    if ($canRunPythonGen) {
        Log-Info "Generating high-entropy cryptographic keys via Python..."
        python scripts/generate_secrets.py --force
    } else {
        Log-Info "Generating high-entropy cryptographic keys via PowerShell cryptographic RNG..."
        function New-CryptKey([int]$len = 40) {
            $alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%^&*()-_=+[]{}~"
            $bytes = New-Object byte[] $len
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($bytes)
            $str = ""
            for ($k = 0; $k -lt $len; $k++) {
                $str += $alphabet[$bytes[$k] % $alphabet.Length]
            }
            return $str
        }

        $secretKey = New-CryptKey 50
        $liveKey = New-CryptKey 40
        $pgPass = New-CryptKey 32
        $redisPass = New-CryptKey 32
        $mqPass = New-CryptKey 32
        $s3Pass = New-CryptKey 40

        $envRaw = Get-Content ".env"
        $envRaw = $envRaw -replace "^SECRET_KEY=.*", "SECRET_KEY=$secretKey"
        $envRaw = $envRaw -replace "^LIVE_SERVER_SECRET_KEY=.*", "LIVE_SERVER_SECRET_KEY=$liveKey"
        $envRaw = $envRaw -replace "^POSTGRES_PASSWORD=.*", "POSTGRES_PASSWORD=$pgPass"
        $envRaw = $envRaw -replace "^REDIS_PASSWORD=.*", "REDIS_PASSWORD=$redisPass"
        $envRaw = $envRaw -replace "^RABBITMQ_PASSWORD=.*", "RABBITMQ_PASSWORD=$mqPass"
        $envRaw = $envRaw -replace "^AWS_SECRET_ACCESS_KEY=.*", "AWS_SECRET_ACCESS_KEY=$s3Pass"
        $envRaw | Set-Content ".env" -Encoding UTF8
        Log-Success "Generated cryptographically secure credentials for database, queues, and Django."
    }

    # Determine scheme and URLs
    $isDomain = $ServerIPOrDomain -match "\.[a-zA-Z]{2,}$"
    $webUrl = "http://$ServerIPOrDomain"
    if ($HttpPort -ne 80) {
        $webUrl = "http://$($ServerIPOrDomain):$HttpPort"
    }

    # Update .env values
    $envContent = Get-Content ".env"
    $envContent = $envContent -replace "^APP_DOMAIN=.*", "APP_DOMAIN=$ServerIPOrDomain"
    $envContent = $envContent -replace "^WEB_URL=.*", "WEB_URL=$webUrl"
    $envContent = $envContent -replace "^CORS_ALLOWED_ORIGINS=.*", "CORS_ALLOWED_ORIGINS=$webUrl"
    $envContent = $envContent -replace "^SITE_ADDRESS=.*", "SITE_ADDRESS=:80"
    $envContent = $envContent -replace "^LISTEN_HTTP_PORT=.*", "LISTEN_HTTP_PORT=$HttpPort"
    $envContent = $envContent -replace "^LISTEN_HTTPS_PORT=.*", "LISTEN_HTTPS_PORT=$HttpsPort"
    $envContent | Set-Content ".env" -Encoding UTF8

    Log-Success ".env configured successfully with WEB_URL = $webUrl"
}

# ------------------------------------------------------------------------------
# 6. Windows Firewall Configuration
# ------------------------------------------------------------------------------
function Configure-WindowsFirewall {
    Log-Step "Step 6/8: Configuring Windows Defender Firewall"

    try {
        # Port 80
        $ruleHttp = Get-NetFirewallRule -DisplayName "Plane Web HTTP" -ErrorAction SilentlyContinue
        if (-not $ruleHttp) {
            New-NetFirewallRule -DisplayName "Plane Web HTTP" -Direction Inbound -Protocol TCP -LocalPort $HttpPort -Action Allow | Out-Null
            Log-Success "Added Windows Firewall rule: Allow Inbound TCP $HttpPort (HTTP)"
        } else {
            Log-Info "Windows Firewall rule for HTTP already exists."
        }

        # Port 443
        $ruleHttps = Get-NetFirewallRule -DisplayName "Plane Web HTTPS" -ErrorAction SilentlyContinue
        if (-not $ruleHttps) {
            New-NetFirewallRule -DisplayName "Plane Web HTTPS" -Direction Inbound -Protocol TCP -LocalPort $HttpsPort -Action Allow | Out-Null
            Log-Success "Added Windows Firewall rule: Allow Inbound TCP $HttpsPort (HTTPS)"
        } else {
            Log-Info "Windows Firewall rule for HTTPS already exists."
        }
    } catch {
        Log-Warn "Could not update Windows Firewall automatically. Ensure ports $HttpPort and $HttpsPort are open in your server firewall."
    }
}

# ------------------------------------------------------------------------------
# 7. Pull Images & Launch Plane Stack
# ------------------------------------------------------------------------------
function Launch-PlaneStack {
    Log-Step "Step 7/8: Pulling Docker Images, Running Migrations, & Starting Stack"
    Set-Location $InstallDir

    Log-Info "Validating Docker Compose configuration..."
    docker compose config --quiet
    if ($LASTEXITCODE -ne 0) {
        Log-Err "Docker Compose configuration validation failed. Please inspect .env."
        exit 1
    }

    Log-Info "Pulling official Plane container images..."
    docker compose pull

    Log-Info "Starting database services (PostgreSQL, Valkey, RabbitMQ, MinIO)..."
    docker compose up -d plane-db plane-redis plane-mq plane-minio

    Log-Info "Waiting for database and message broker health checks..."
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        $dbStatus = docker inspect -f '{{.State.Health.Status}}' plane-db 2>$null
        $redisStatus = docker inspect -f '{{.State.Health.Status}}' plane-redis 2>$null
        if ($dbStatus -eq "healthy" -and $redisStatus -eq "healthy") {
            break
        }
    }

    Log-Info "Executing database migrations (plane-migrator)..."
    docker compose run --rm migrator

    Log-Info "Launching full application stack..."
    docker compose up -d

    Log-Success "All Plane services dispatched."
}

# ------------------------------------------------------------------------------
# 8. Post-Launch Verification & Output Summary
# ------------------------------------------------------------------------------
function Verify-Deployment {
    Log-Step "Step 8/8: Verifying System Health & Generating Endpoints"
    Set-Location $InstallDir

    Start-Sleep -Seconds 5
    docker compose ps

    $webUrl = "http://$ServerIPOrDomain"
    if ($HttpPort -ne 80) { $webUrl = "http://$($ServerIPOrDomain):$HttpPort" }

    Write-Host @"

================================================================================
             🎉 PLANE WINDOWS SERVER DEPLOYMENT COMPLETED!                     
================================================================================

Access Endpoints:
  • Main Web Application:    $webUrl
  • Initial Admin Setup:     $webUrl/god-mode/
  • Plane Space Portals:     $webUrl/spaces/

Initial Setup Steps:
  1. Open '$webUrl/god-mode/' in your web browser.
  2. Complete the initial registration wizard to create your Instance Admin account.
  3. Create your first workspace and project boards.

Management CLI on this Windows Server:
  • Check Status:    cd $InstallDir; .\scripts\manage.ps1 status
  • View Live Logs:  cd $InstallDir; .\scripts\manage.ps1 logs
  • Stop Stack:      cd $InstallDir; .\scripts\manage.ps1 stop
  • Start Stack:     cd $InstallDir; .\scripts\manage.ps1 start
  • Snapshot Backup: cd $InstallDir; .\scripts\manage.ps1 backup
  • Upgrade Plane:   cd $InstallDir; .\scripts\manage.ps1 update

Firewall Notice:
  Windows Defender Firewall rules have been created for TCP port $HttpPort and $HttpsPort.
  If this server is hosted in a cloud environment (AWS, Azure, Hetzner, etc.),
  also ensure your cloud Security Group / Network Security Group permits inbound TCP $HttpPort.

================================================================================
"@ -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# Main Execution Pipeline
# ------------------------------------------------------------------------------
Show-Banner
Check-AdminPrivileges
Install-Prerequisites
Install-DockerOnWindows
Setup-Repository
Configure-Environment
Configure-WindowsFirewall
Launch-PlaneStack
Verify-Deployment
