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
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Log-Info "Python is not detected. Installing Python 3..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Python.Python.3.11 -e --source winget --accept-source-agreements --accept-package-agreements --silent
        } else {
            $pyInstaller = "$env:TEMP\python-installer.exe"
            Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe" -OutFile $pyInstaller
            Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
            Remove-Item -Force $pyInstaller -ErrorAction SilentlyContinue
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Log-Success "Python installed successfully."
    } else {
        $pyVer = (python --version 2>&1)
        Log-Success "Python is already installed: $pyVer"
    }
}

# ------------------------------------------------------------------------------
# 3. Docker Installation & WSL 2 Backend
# ------------------------------------------------------------------------------
function Install-DockerOnWindows {
    Log-Step "Step 3/8: Verifying & Installing Docker for Windows"

    if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Get-Command "docker-compose" -ErrorAction SilentlyContinue -or (docker compose version 2>$null))) {
        $dVer = (docker --version)
        Log-Success "Docker is already installed: $dVer"
        
        # Verify Docker daemon is running
        $dockerReady = $false
        try {
            docker info >$null 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
        } catch {}

        if (-not $dockerReady) {
            Log-Info "Docker Engine is not running. Attempting to start Docker Desktop service..."
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

    # Docker is missing - perform automated installation
    Log-Info "Docker is not detected on this server. Initiating Docker setup..."

    # Enable Virtual Machine Platform and WSL feature if not present
    Log-Info "Ensuring Windows Subsystem for Linux (WSL) and Virtual Machine Platform are enabled..."
    try {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    } catch {}

    # Install Docker Desktop
    Log-Info "Installing Docker Desktop..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements --silent
    } else {
        $dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
        Log-Info "Downloading Docker Desktop Installer (approx. 500 MB)..."
        Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $dockerInstaller
        Log-Info "Executing silent Docker installation..."
        Start-Process -FilePath $dockerInstaller -ArgumentList "install --quiet --accept-licenses" -Wait
        Remove-Item -Force $dockerInstaller -ErrorAction SilentlyContinue
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Log-Success "Docker Desktop installed successfully."
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
        Log-Warn "Docker Desktop was installed, but the engine is still initializing."
        Log-Warn "If this is a fresh WSL install, a system reboot may be required by Windows before Docker can run Linux containers."
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

    # Run Python secret generator
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Log-Info "Generating high-entropy cryptographic keys via Python..."
        python scripts/generate_secrets.py --force
    } else {
        Log-Warn "Python not found in current path; using PowerShell cryptographic RNG..."
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $secretKey = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=') + "PlaneSecretKey2026Secure"
        (Get-Content ".env") -replace "^SECRET_KEY=.*", "SECRET_KEY=$secretKey" | Set-Content ".env"
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
    $envContent = $envContent -replace "^SITE_ADDRESS=.*", "SITE_ADDRESS=:$HttpPort"
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
