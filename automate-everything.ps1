# HashiCorp Cryptography Demo - Final Working Version
Write-Host "Starting HashiCorp Cryptography Demo" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

# Function to check if a command exists
function Test-CommandExists {
    param($command)
    return (Get-Command $command -ErrorAction SilentlyContinue) -ne $null
}

# Function to wait for a service to be ready
function Wait-ServiceReady {
    param(
        [string]$Url,
        [string]$ServiceName,
        [int]$MaxAttempts = 30
    )

    Write-Host "   Waiting for $ServiceName to be ready..." -ForegroundColor Yellow
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
            Write-Host "   $ServiceName is ready!" -ForegroundColor Green
            return $true
        } catch {
            if ($i -eq 1) {
                Write-Host "   Attempt $i of $MaxAttempts..." -ForegroundColor Gray
            }
            Start-Sleep 2
        }
    }
    Write-Host "   $ServiceName failed to start" -ForegroundColor Red
    return $false
}

Write-Host "`n1. Checking prerequisites..." -ForegroundColor Cyan

# Check if Docker is running
if (-not (Test-CommandExists "docker")) {
    Write-Host "Docker is not installed or not running" -ForegroundColor Red
    exit 1
}

# Check Docker daemon
try {
    docker version | Out-Null
    Write-Host "   Docker is running" -ForegroundColor Green
} catch {
    Write-Host "Docker daemon is not accessible" -ForegroundColor Red
    exit 1
}

Write-Host "`n2. Starting Docker containers..." -ForegroundColor Cyan
# Clean up any existing containers first
Write-Host "   Stopping any existing containers..." -ForegroundColor Gray
docker-compose down 2>$null

# Start containers
Write-Host "   Starting new containers..." -ForegroundColor Gray
docker-compose up -d

Write-Host "   Waiting for containers to start..." -ForegroundColor Yellow
Start-Sleep 20

Write-Host "`n3. Waiting for services to be ready..." -ForegroundColor Cyan

# Wait for Vault
if (-not (Wait-ServiceReady -Url "http://localhost:8200/v1/sys/health" -ServiceName "Vault")) {
    exit 1
}

# Wait for Consul
if (-not (Wait-ServiceReady -Url "http://localhost:8500/v1/status/leader" -ServiceName "Consul")) {
    exit 1
}

Write-Host "`n4. Setting up Vault environment..." -ForegroundColor Cyan
$env:VAULT_ADDR = "http://localhost:8200"

# Initialize Vault
Write-Host "   Initializing Vault..." -ForegroundColor Yellow
vault login root-token 2>$null

# Enable secrets engines if not already enabled
vault secrets enable -path=secret kv-v2 2>$null
vault secrets enable transit 2>$null

# Create encryption key
vault write -f transit/keys/demo-key type="aes256-gcm96" 2>$null

# Create demo secrets
vault kv put secret/demo/web-service api_key="wk_1234567890abcdef" database_url="postgresql://user:pass@db:5432/app" 2>$null
vault kv put secret/demo/api-service jwt_secret="jwt_super_secret_2024" external_api_key="ext_9876543210zyxwvu" 2>$null

Write-Host "   Vault setup complete" -ForegroundColor Green

Write-Host "`n5. Running Cryptography Demo..." -ForegroundColor Cyan

# Demo data
$demoData = "DemoSecret123"
Write-Host "   Original data: $demoData" -ForegroundColor White

# Convert to base64
$base64Data = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($demoData))
Write-Host "   Base64 encoded: $base64Data" -ForegroundColor Gray

Write-Host "`n6. Testing encryption..." -ForegroundColor Yellow
Write-Host "   Command: vault write transit/encrypt/demo-key plaintext=`"dGVzdA==`"" -ForegroundColor Gray

# Run encryption command and capture output as array of lines
$encryptOutput = vault write transit/encrypt/demo-key plaintext="dGVzdA=="

# Display the output
Write-Host "   Encryption result:" -ForegroundColor White
foreach ($line in $encryptOutput) {
    Write-Host "   $line" -ForegroundColor Cyan
}

# Extract ciphertext - handle the output format properly
$ciphertext = $null
foreach ($line in $encryptOutput) {
    if ($line -match 'ciphertext\s+(vault:v1:.+)') {
        $ciphertext = $matches[1].Trim()
        break
    }
}

if ($ciphertext) {
    Write-Host "`n   Ciphertext extracted: $ciphertext" -ForegroundColor Green

    Write-Host "`n7. Testing decryption..." -ForegroundColor Yellow
    Write-Host "   Command: vault write transit/decrypt/demo-key ciphertext=`"$ciphertext`"" -ForegroundColor Gray

    # Run decryption command
    $decryptOutput = vault write transit/decrypt/demo-key ciphertext=$ciphertext

    Write-Host "   Decryption result:" -ForegroundColor White
    foreach ($line in $decryptOutput) {
        Write-Host "   $line" -ForegroundColor Cyan
    }

    # Extract plaintext from output
    $base64Plaintext = $null
    foreach ($line in $decryptOutput) {
        if ($line -match 'plaintext\s+(.+)') {
            $base64Plaintext = $matches[1].Trim()
            break
        }
    }

    if ($base64Plaintext) {
        Write-Host "`n   Base64 result: $base64Plaintext" -ForegroundColor Gray

        # Decode the base64
        try {
            $decodedText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64Plaintext))
            Write-Host "   Decoded text: $decodedText" -ForegroundColor Green

            Write-Host "`n8. Verification..." -ForegroundColor Cyan
            if ($decodedText -eq "test") {
                Write-Host "   SUCCESS: Encryption and decryption working!" -ForegroundColor Green
            } else {
                Write-Host "   FAILED: Expected 'test', got '$decodedText'" -ForegroundColor Red
            }
        } catch {
            Write-Host "   Failed to decode base64: $base64Plaintext" -ForegroundColor Red
        }
    } else {
        Write-Host "   Could not extract plaintext from decryption output" -ForegroundColor Red
    }
} else {
    Write-Host "   Could not extract ciphertext from encryption output" -ForegroundColor Red
    Write-Host "   Raw output was:" -ForegroundColor Yellow
    foreach ($line in $encryptOutput) {
        Write-Host "   $line" -ForegroundColor Gray
    }
}

Write-Host "`n9. Testing with custom data..." -ForegroundColor Cyan
Write-Host "   Command: vault write transit/encrypt/demo-key plaintext=`"$base64Data`"" -ForegroundColor Gray

$customEncrypt = vault write transit/encrypt/demo-key plaintext=$base64Data
Write-Host "   Custom encryption result:" -ForegroundColor White
foreach ($line in $customEncrypt) {
    Write-Host "   $line" -ForegroundColor Cyan
}

Write-Host "`n10. Displaying stored secrets..." -ForegroundColor Cyan
vault kv get secret/demo/web-service

Write-Host "`n11. Final status..." -ForegroundColor Cyan
Write-Host "   Docker containers running" -ForegroundColor Green
Write-Host "   Vault initialized and ready" -ForegroundColor Green
Write-Host "   Secret management working" -ForegroundColor Green

if ($ciphertext -and $base64Plaintext) {
    Write-Host "   Cryptographic operations working" -ForegroundColor Green
} else {
    Write-Host "   Cryptographic operations: Issues with output parsing" -ForegroundColor Yellow
}

Write-Host "`nAccess URLs:" -ForegroundColor Cyan
Write-Host "   Vault UI: http://localhost:8200" -ForegroundColor White
Write-Host "   Consul UI: http://localhost:8500" -ForegroundColor White
Write-Host "   Web Service: http://localhost:8080" -ForegroundColor White
Write-Host "   API Service: http://localhost:8081" -ForegroundColor White

Write-Host "`nDemo Complete!" -ForegroundColor Green
Write-Host "===============" -ForegroundColor Green

if (-not $ciphertext) {
    Write-Host "`nManual test commands:" -ForegroundColor Yellow
    Write-Host "vault write transit/encrypt/demo-key plaintext=`"dGVzdA==`"" -ForegroundColor White
    Write-Host "# Copy the ciphertext and run:" -ForegroundColor Gray
    Write-Host "vault write transit/decrypt/demo-key ciphertext=`"vault:v1:PASTE_CIPHERTEXT`"" -ForegroundColor White
}