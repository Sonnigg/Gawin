<#
.SYNOPSIS
    Setup script for the GLang and Gawin development environment.
.DESCRIPTION
    Automates installing LLVM/Clang, managing PATH environment variables,
    building the compiler pipeline, and running basic health and security checks.
.PARAMETER Scope
    Where to save environment variables. Choose 'user' or 'system'.
.PARAMETER Force
    Forces a fresh download and install of LLVM even if it is already installed.
.PARAMETER Doctor
    Runs a health check on paths, software versions, and dependencies.
.PARAMETER Repair
    Automatically fixes missing environment paths and binary files.
.PARAMETER Build
    Skips prompts and directly starts building the compiler.
.PARAMETER SkipBuild
    Skips the build phase completely.
.PARAMETER SkipLLVM
    Skips downloading or checking the LLVM/Clang toolchain.
.PARAMETER AdvancedBuild
    Forces the full multi-stage bootstrap build sequence.
.PARAMETER SecurityAudit
    Checks folder permissions, PATH health, and script execution policies.
.EXAMPLE
    .\setup.ps1 -Scope user
.EXAMPLE
    .\setup.ps1 -Scope system -AdvancedBuild -SecurityAudit
#>

[CmdletBinding()]
param(
    [ValidateSet("user", "system")]
    [string]$Scope,

    [switch]$Force,
    [switch]$Doctor,
    [switch]$Repair,
    [switch]$Build,
    [switch]$SkipBuild,
    [switch]$SkipLLVM,
    [switch]$AdvancedBuild,
    [switch]$SecurityAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================================================
# Configuration & Global Settings
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$GLangBin        = Join-Path $PSScriptRoot "bin"
$FallbackLLVM    = "20.1.8"

# Status Tracking
$Global:ReportCard = [ordered]@{
    "Security Scan"   = "Skipped"
    "Health Audit"    = "Skipped"
    "LLVM Toolchain"  = "Unchanged"
    "System PATH"     = "Unchanged"
    "Compiler Engine" = "Skipped"
}

# Build Metrics
$Global:BuildStats = @{
    HelperCount     = 0
    BootstrapStatus = "Skipped"
    RuntimeCount    = 0
    SelfHostStatus  = "Skipped (0 modules)"
    PlatformStatus  = "Skipped (0 modules)"
    TotalBuildTime  = 0.0
}

# =========================================================
# Logging and UI Functions
# =========================================================
function Write-Log {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR","SECURE","BLANK")]
        [string]$Level,
        [string]$Message
    )

    $Timestamp = Get-Date -Format "HH:mm:ss"

    switch ($Level) {
        "INFO"   { Write-Host "[$Timestamp] [info]    $Message" -ForegroundColor Cyan }
        "OK"     { Write-Host "[$Timestamp] [success] $Message" -ForegroundColor Green }
        "WARN"   { Write-Host "[$Timestamp] [warning] $Message" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[$Timestamp] [failed]  $Message" -ForegroundColor Red }
        "SECURE" { Write-Host "[$Timestamp] [security] $Message" -ForegroundColor Magenta }
        "BLANK"  { Write-Host "$Message" }
    }
}

function Write-ProgressInline {
    param(
        [string]$Message
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host -NoNewline "`r[$Timestamp] [info]    $Message".PadRight(95) -ForegroundColor Cyan
}

function Show-Header {
    Write-Log BLANK "=========================================================="
    Write-Log BLANK "          GAWIN & GLANG WORKSPACE SETUP SCRIPT            "
    Write-Log BLANK "=========================================================="
}

# =========================================================
# Admin Rights / UAC Handling
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "System-wide setup requires administrator permissions."
        Write-Log INFO "Asking for admin rights (UAC prompt)..."
        
        try {
            $Arguments = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", "`"$PSCommandPath`"",
                "-Scope", "`"$ScopeArg`""
            )
            
            if ($Force)         { $Arguments += "-Force" }
            if ($Doctor)        { $Arguments += "-Doctor" }
            if ($Repair)        { $Arguments += "-Repair" }
            if ($Build)         { $Arguments += "-Build" }
            if ($SkipBuild)     { $Arguments += "-SkipBuild" }
            if ($SkipLLVM)      { $Arguments += "-SkipLLVM" }
            if ($AdvancedBuild) { $Arguments += "-AdvancedBuild" }
            if ($SecurityAudit) { $Arguments += "-SecurityAudit" }

            $Proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $Arguments -PassThru -ErrorAction Stop
            Write-Log OK "Admin access granted. New process started with ID: $($Proc.Id)"
            exit
        }
        catch {
            Write-Log ERROR "Admin prompt was denied or failed: $($_.Exception.Message)"
            Write-Log WARN "Please open PowerShell as Administrator manually and run this script again."
            throw "Could not get administrator rights."
        }
    }
}

# =========================================================
# File Downloader
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Downloading file from: $Uri"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log ERROR "Download failed. Check your internet connection: $($_.Exception.Message)"
        throw $_
    }
}

# =========================================================
# System Health Checks
# =========================================================
function Get-ClangVersion {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }

    $out = & clang --version 2>$null
    $m = [regex]::Match($out, "version\s+([0-9]+\.[0-9]+\.[0-9]+)")
    if ($m.Success) { return $m.Groups[1].Value }
    return "unknown"
}

function Test-Clang {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Clang is available at: $($cmd.Source)"
        return $true
    }
    Write-Log WARN "Clang was not found in your current PATH variables."
    return $false
}

function Get-GLangVersion {
    try {
        $versionFile = Join-Path $PSScriptRoot "config.pl"
        if (-not (Test-Path $versionFile)) { return "unknown" }

        $content = Get-Content $versionFile -Raw
        if ($content -match '"version"\s*\=\>\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"') {
            return $matches[1]
        }
        return "unknown"
    }
    catch {
        return "unknown"
    }
}

function Get-LatestLLVMVersion {
    try {
        Write-Log INFO "Checking GitHub for the latest stable LLVM version..."
        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest" -TimeoutSec 10
        if (-not $r.tag_name) { throw "Could not read GitHub response format." }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Latest recommended version on GitHub: $v"
        return $v
    }
    catch {
        Write-Log WARN "Could not connect to GitHub. Using default fallback version: $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Invoke-Doctor {
    Write-Log INFO "--- RUNNING HEALTH AUDIT ---"
    
    Write-Log INFO "Windows Version : $((Get-CimInstance Win32_OperatingSystem).Caption)"
    Write-Log INFO "Architecture    : $env:PROCESSOR_ARCHITECTURE"
    Write-Log INFO "Target Mode     : $(if ([IntPtr]::Size -eq 8) { '64-bit' } else { '32-bit' })"
    Write-Log INFO "PowerShell Ver  : $($PSVersionTable.PSVersion)"

    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $clang) {
        Write-Log ERROR "Clang compiler is missing from your system."
    } else {
        $ver = Get-ClangVersion
        Write-Log INFO "Compiler Path   : $($clang.Source)"
        Write-Log INFO "Clang Version   : $ver"
        
        $latest = Get-LatestLLVMVersion
        if ($ver -and $ver -notlike "$latest*") {
            Write-Log WARN "Your local Clang version differs from the latest online version ($latest)."
        } else {
            Write-Log OK "Your LLVM version matches the recommended spec."
        }
    }

    if ($env:Path -notmatch "LLVM") { 
        Write-Log WARN "LLVM folder paths are missing from your environment variables." 
    }

    Write-Log BLANK
    Write-Log INFO "--- GLANG FRAMEWORK ---"
    $glangPath = Join-Path $PSScriptRoot "bin"
    $glangVer  = Get-GLangVersion

    Write-Log INFO "Output Bin Path : $glangPath"
    Write-Log INFO "Framework Build : $glangVer"

    if (Test-Path $glangPath) { 
        Write-Log OK "Gawin bin folder exists." 
    } else { 
        Write-Log WARN "The bin folder is empty. Run a build to generate compiler files." 
    }

    $Global:ReportCard["Health Audit"] = "Completed"
    Write-Log OK "Health check finished."
    Write-Log BLANK
}

# =========================================================
# Security Audits
# =========================================================
function Invoke-SecurityAudit {
    Write-Log SECURE "--- RUNNING SECURITY CHECK ---"
    
    # 1. Execution Policy Check
    $policy = Get-ExecutionPolicy
    Write-Log INFO "Current Script Execution Policy: $policy"
    if ($policy -in @("Bypass", "Unrestricted")) {
        Write-Log WARN "Your shell policy is highly permissive ($policy). Be careful when running untrusted scripts."
    } else {
        Write-Log OK "Local script policy looks reasonably secure."
    }

    # 2. Path Integrity Check
    Write-Log INFO "Scanning PATH paths for unsecured folders..."
    $paths = $env:Path -split ';'
    $writablePathsInsecure = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        if ($p -match "Temp" -or $p -eq "C:\") {
            $writablePathsInsecure += $p
        }
    }
    if ($writablePathsInsecure.Count -gt 0) {
        Write-Log WARN "Found globally writable or temporary folders in your PATH: $writablePathsInsecure"
    } else {
        Write-Log SECURE "Environment paths look secure. No obvious issues found."
    }

    # 3. Write Permissions Check
    try {
        $testFile = Join-Path $PSScriptRoot ".sec_verify.tmp"
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item $testFile -Force
        Write-Log OK "Folder write permissions verified successfully."
    } catch {
        Write-Log ERROR "Cannot write to workspace! Try running this script as Administrator."
    }

    $Global:ReportCard["Security Scan"] = "Verified"
    Write-Log SECURE "Security check complete."
    Write-Log BLANK
}

# =========================================================
# Auto-Repair Engine
# =========================================================
function Invoke-AutoRepair {
    Write-Log INFO "Starting environment auto-repair..."
    
    if (-not $SkipLLVM) {
        $clangInstalled = Test-Clang
        if (-not $clangInstalled -or $Force) { Install-LLVM }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { Split-Path (Get-Command clang).Source -Parent } else { $DefaultLLVMPath }

    if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
    if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }
    
    Write-Log OK "Auto-repair has finished fixing paths and dependencies."
}

# =========================================================
# Interactive Audit Prompts
# =========================================================
function Invoke-PostAuditPrompt {
    Write-Host ""
    Write-Host "Diagnostic checks completed. What would you like to do next?" -ForegroundColor Cyan
    Write-Host "1) Automatically fix missing paths and install missing tools right now"
    Write-Host "2) Build the tools and run a validation check on compiled files"
    Write-Host "3) Do nothing and keep current settings"
    Write-Host ""
    
    $ans = Read-Host "Select an option [1-3]"
    switch ($ans.Trim()) {
        "1" {
            Invoke-AutoRepair
        }
        "2" {
            Write-Log INFO "Starting the build pipeline..."
            Invoke-AdvancedCompilationPipeline
            
            Write-Log SECURE "Checking for abnormally small or suspicious executables..."
            $suspicious = $false
            $builtExes = Get-ChildItem $GLangBin -Filter "*.exe" -ErrorAction SilentlyContinue
            
            foreach ($exe in $builtExes) {
                if ($exe.Length -lt 1024) {
                    Write-Log WARN "Suspiciously small executable found: $($exe.Name)"
                    $suspicious = $true
                }
            }
            
            if (-not $suspicious) {
                Write-Log OK "All compiled executables look standard and clean."
            } else {
                Write-Log ERROR "One or more files look suspicious."
                Write-Host ""
                $fixChoice = Read-Host "Would you like me to try repairing the workspace? (y/n)"
                if ($fixChoice.Trim().ToLower() -in @("y", "yes")) {
                    Invoke-AutoRepair
                } else {
                    Write-Log WARN "Repair canceled. Exercise caution if you run these tools."
                }
            }
        }
        default {
            Write-Log INFO "Continuing setup tasks."
        }
    }
}

# =========================================================
# PATH Management Tools
# =========================================================
function Get-PathList($scope) {
    $p = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $p) { return @() }
    return $p -split ';' | Where-Object { $_ -and $_.Trim() }
}

function Set-PathList($list, $scope) {
    $newPath = ($list | Select-Object -Unique) -join ';'
    
    # Create a backup of the PATH before modifying it
    $backupKeyName = "Path_Gawin_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    [Environment]::SetEnvironmentVariable($backupKeyName, [Environment]::GetEnvironmentVariable("Path", $scope), $scope)
    
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
}

function Add-ToPathSafe {
    param(
        [string]$PathToAdd,
        [EnvironmentVariableTarget]$Scope
    )

    if (-not (Test-Path $PathToAdd)) {
        throw "The target folder does not exist: $PathToAdd"
    }

    $list = Get-PathList $Scope
    if ($list -contains $PathToAdd) {
        Write-Log INFO "Folder is already inside your PATH environment variables: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope
    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Successfully added folder to PATH: $PathToAdd"
    $Global:ReportCard["System PATH"] = "Updated"
}

# =========================================================
# Installer Operations
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion
    $winget  = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Attempting silent install via winget..."
        try {
            & winget install LLVM.LLVM --silent --accept-source-agreements --accept-package-agreements --timeout 300
            if ($LASTEXITCODE -eq 0) {
                Write-Log OK "LLVM toolchain installed successfully via winget."
                $Global:ReportCard["LLVM Toolchain"] = "Installed (Winget)"
                return
            }
        } catch {}
        Write-Log WARN "Winget install failed or timed out. Falling back to direct download..."
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp
    Write-Log INFO "Running the LLVM installer silently..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "The LLVM installer failed with exit code: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM has been installed successfully!"
    $Global:ReportCard["LLVM Toolchain"] = "Installed (Standalone)"
}

# =========================================================
# Compiler Build Pipeline
# =========================================================
function Invoke-AdvancedCompilationPipeline {
    Write-Log BLANK
    Write-Log INFO "=========================================================="
    Write-Log INFO "               STARTING GAWIN COMPILER BUILD              "
    Write-Log INFO "=========================================================="

    $root = $PSScriptRoot
    $binDir = Join-Path $root "bin"
    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $clangxx = Get-Command clang++ -ErrorAction SilentlyContinue
    if (-not $clangxx) {
        Write-Log ERROR "Clang++ is missing. Cannot build the pipeline."
        $Global:ReportCard["Compiler Engine"] = "Failed (Missing Clang++)"
        return
    }

    if (-not (Test-Path $binDir)) {
        Write-Log INFO "Creating missing binary directory: $binDir"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # --- PHASE 1: Build source files in root/src_exec/*.cpp ---
    Write-Log INFO "Phase 1: Building utility source files..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $srcExecDir = Join-Path $root "src_exec"
    
    if (Test-Path $srcExecDir) {
        $cppFiles = Get-ChildItem (Join-Path $srcExecDir "*.cpp") -ErrorAction SilentlyContinue
        foreach ($file in $cppFiles) {
            Write-ProgressInline "Phase 1 -> Building helper component: $($file.Name)"
            $outExe = Join-Path $binDir ($file.BaseName + ".exe")
            & clang++ "-std=c++17" "-O3" $file.FullName "-o" $outExe 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.HelperCount++
                $Global:BuildStats.RuntimeCount++
            } else {
                Write-Host ""
                Write-Log ERROR "Phase 1 compilation failed on file: $($file.Name)"
                throw "Phase 1 build error encountered."
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [success] PHASE 1 complete in $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) seconds".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Source directory missing ($srcExecDir). Skipping Step..."
    }

    # --- PHASE 2: Build bootstrap compiler root/bootstrap_cpp_gawin/*.cpp ---
    Write-Log INFO "Phase 2: Building bootstrap compiler (ggc.exe)..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $bootstrapDir = Join-Path $root "bootstrap_cpp_gawin"
    $ggcPath = Join-Path $binDir "ggc.exe"
    
    if (Test-Path $bootstrapDir) {
        $bootCppFiles = Get-ChildItem (Join-Path $bootstrapDir "*.cpp") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($bootCppFiles) {
            Write-ProgressInline "Phase 2 -> Generating compiler base container"
            & clang++ "-std=c++17" "-O3" $bootCppFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.BootstrapStatus = "Success"
                $Global:BuildStats.RuntimeCount++
            } else {
                Write-Host ""
                throw "Phase 2 bootstrap build failed."
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [success] PHASE 2 complete in $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) seconds".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Bootstrap source directory missing ($bootstrapDir). Skipping step..."
    }

    # --- PHASE 3: Run pipeline manager tool gstdo ---
    Write-Log INFO "Phase 3: Running internal pipeline automation tool..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gstdoPath = Join-Path $binDir "gstdo.exe"
    
    if (Test-Path $gstdoPath) {
        Write-ProgressInline "Phase 3 -> Running automation checks via gstdo.exe"
        Push-Location $binDir
        try {
            & .\gstdo.exe
        } catch {
            Write-Host ""
            Write-Log WARN "Automation task returned a warning during execution."
        } finally {
            Pop-Location
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [success] PHASE 3 complete in $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) seconds".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Automation binary missing ($gstdoPath). Skipping step..."
    }

    # --- PHASE 4: Self-host rebuild; run ggc on root/ggc/*.gw ---
    Write-Log INFO "Phase 4: Rebuilding compiler using itself (Self-hosting)..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $ggcSrcDir = Join-Path $root "ggc"
    
    if ((Test-Path $ggcPath) -and (Test-Path $ggcSrcDir)) {
        $gwCompilerFiles = Get-ChildItem (Join-Path $ggcSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwCompilerFiles) {
            Write-ProgressInline "Phase 4 -> Processing self-hosted rewrite loop modules"
            & $ggcPath $gwCompilerFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.SelfHostStatus = "Success ($($gwCompilerFiles.Count) modules)"
                $Global:BuildStats.RuntimeCount += $gwCompilerFiles.Count
            } else {
                Write-Host ""
                Write-Log ERROR "Self-hosted build phase returned unexpected errors."
                $Global:BuildStats.SelfHostStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [success] PHASE 4 complete in $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) seconds".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Self-host modules or baseline compiler files are missing. Skipping step..."
    }

    # --- PHASE 5: Build platform modules; run new ggc on root/gwin/*.gw ---
    Write-Log INFO "Phase 5: Building platform core interface components..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gwinSrcDir = Join-Path $root "gwin"
    $gwinPath = Join-Path $binDir "gwin.exe"
    
    if ((Test-Path $ggcPath) -and (Test-Path $gwinSrcDir)) {
        $gwinFiles = Get-ChildItem (Join-Path $gwinSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwinFiles) {
            Write-ProgressInline "Phase 5 -> Deploying environment specific libraries"
            & $ggcPath $gwinFiles "-o" $gwinPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.PlatformStatus = "Success ($($gwinFiles.Count) modules)"
                $Global:BuildStats.RuntimeCount += $gwinFiles.Count
            } else {
                Write-Host ""
                Write-Log ERROR "Platform abstraction modules failed to compile cleanly."
                $Global:BuildStats.PlatformStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [success] PHASE 5 complete in $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) seconds".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Windows specific source modules are not available. Skipping step..."
    }

    $totalTimer.Stop()
    $Global:BuildStats.TotalBuildTime = $totalTimer.Elapsed.TotalSeconds
    $Global:ReportCard["Compiler Engine"] = "Fully Functional"
    Write-Log OK "All build stages successfully finished!"
    Write-Log BLANK
}

# =========================================================
# MAIN EXECUTION SCRIPT
# =========================================================
try {
    Show-Header

    # 1. Main Interactive Menu
    if (-not $Scope -and -not $Doctor -and -not $SecurityAudit -and -not $AdvancedBuild) {
        Write-Host "Select an action to perform:" -ForegroundColor Green
        Write-Host "1] Standard System Setup (Install dependencies & paths)"
        Write-Host "2] Build the Compiler Pipeline Only"
        Write-Host "3] Run System Health Checks (Doctor)"
        Write-Host "4] Run Environment Security Checks"
        Write-Host ""
        
        $choice = Read-Host "Specify option index [1-4]"
        switch ($choice.Trim()) {
            "1" { 
                # Continues to target scope config menu
            }
            "2" {
                $AdvancedBuild = $true
                $SkipLLVM = $true
            }
            "3" {
                $Doctor = $true
            }
            "4" {
                $SecurityAudit = $true
            }
            default {
                Write-Log WARN "Invalid entry. Defaulting to a standard fresh environment setup..."
            }
        }
    }

    # Scope Selection Prompt
    while (-not $Scope -and -not $Doctor -and -not $SecurityAudit) {
        Write-Host ""
        $inputScope = Read-Host "Save environment variables for the current [user] or the whole [system]?"
        if ($inputScope.Trim().ToLower() -in @("user", "system")) {
            $Scope = $inputScope.Trim().ToLower()
        } else {
            Write-Log WARN "Invalid entry. Please choose 'user' or 'system' exactly."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    if ($Scope) { Invoke-MakeAdmin $Scope }

    # Task Router
    if ($SecurityAudit) {
        Invoke-SecurityAudit
        Invoke-PostAuditPrompt
    }

    if ($Doctor) {
        Invoke-Doctor
        Invoke-PostAuditPrompt
    }

    if (-not $Doctor -and -not $SecurityAudit) {
        Write-Log INFO "Writing configuration records (Target Hive: $scopeEnv)..."
        Write-Log BLANK

        if ($Repair) {
            Write-Log WARN "Repair parameter active. Checking environment settings..."
            Invoke-AutoRepair
        }

        # Process LLVM Steps
        if (-not $SkipLLVM) {
            $clangInstalled = Test-Clang
            if (-not $clangInstalled -or $Force) { Install-LLVM }
        }

        # Synchronize Paths
        $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { Split-Path (Get-Command clang).Source -Parent } else { $DefaultLLVMPath }

        Write-Log INFO "Updating environmental path configs..."
        if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
        if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }

        # Build Prompts
        $shouldBuild = $false
        if ($Build -or $AdvancedBuild) {
            $shouldBuild = $true
        } elseif ($SkipBuild) {
            $shouldBuild = $false
        } else {
            Write-Host ""
            $inputBuild = Read-Host "Would you like to build the workspace compiler components now? (y/n)"
            if ($inputBuild.Trim().ToLower() -in @("y", "yes", "1")) {
                $shouldBuild = $true
            }
        }

        if ($shouldBuild) {
            Invoke-AdvancedCompilationPipeline
        } else {
            Write-Log INFO "Skipping compilation stages per user request."
        }
    }

    # =========================================================
    # TASK REPORT SUMMARY
    # =========================================================
    Write-Log BLANK
    Write-Log BLANK "=========================================================="
    Write-Log OK    "                    SUMMARY REPORT CARD                   "
    Write-Log BLANK "=========================================================="
    foreach ($item in $Global:ReportCard.Keys) {
        $status = $Global:ReportCard[$item]
        $color = "Cyan"
        if ($status -match "Verified|Completed|Functional|Updated|Installed") { $color = "Green" }
        elseif ($status -match "Failed") { $color = "Red" }
        elseif ($status -match "Skipped") { $color = "Yellow" }
        
        Write-Host " [>] " -NoNewline -ForegroundColor Gray
        Write-Host ($item.PadRight(25)) -NoNewline -ForegroundColor White
        Write-Host " : " -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $color
    }
    
    # Live Performance Metrics
    if ($Global:ReportCard["Compiler Engine"] -eq "Fully Functional") {
        Write-Log BLANK
        Write-Host "==========================================================" -ForegroundColor Gray
        Write-Host "Build Summary Data" -ForegroundColor White
        Write-Host "==========================================================" -ForegroundColor Gray
        Write-Host "Helper utilities   : $($Global:BuildStats.HelperCount) compiled"
        Write-Host "Bootstrap engine   : $($Global:BuildStats.BootstrapStatus)"
        Write-Host "Compiled objects   : $($Global:BuildStats.RuntimeCount) files completed"
        Write-Host "Self-hosted build  : $($Global:BuildStats.SelfHostStatus)"
        Write-Host "Platform binaries  : $($Global:BuildStats.PlatformStatus)"
        Write-Log BLANK
        Write-Host "Total Build Time   : $($Global:BuildStats.TotalBuildTime.ToString("F2"))s" -ForegroundColor Cyan
    }
    Write-Log BLANK "=========================================================="
    Write-Log OK "Workspace configuration and setup steps completed successfully!"
}
catch {
    Write-Log ERROR "A fatal error occurred: $($_.Exception.Message)"
    Write-Log BLANK "Error Location Trace: $($_.ScriptStackTrace)"
    exit 1
}

Pause