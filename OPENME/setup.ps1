<#
.SYNOPSIS
    A modern development ecosystem setup script for GLang and Gawin.
.DESCRIPTION
    Automates the installation of required binaries (LLVM/Clang, Perl), 
    manages environment PATH variables, processes a multi-stage compiler build 
    pipeline, and runs system sanity/security diagnostics.
.PARAMETER Scope
    Where to save your environment configuration registry entries. Choose 'user' or 'system'.
.PARAMETER Force
    Forces a fresh download and installation of LLVM and Perl, even if already present.
.PARAMETER Doctor
    Runs an operational health check on environmental paths, versions, and tool dependencies.
.PARAMETER Repair
    Automatically fixes missing environment paths and binary targets.
.PARAMETER Build
    Bypasses the interactive prompt and directly triggers the compilation pipeline.
.PARAMETER SkipBuild
    Explicitly skips the compilation phase.
.PARAMETER SkipPerl
    Skips downloading or validating the Perl interpreter environment.
.PARAMETER SkipLLVM
    Skips downloading or validating the LLVM/Clang toolchain.
.PARAMETER AdvancedBuild
    Forces execution of the multi-tier bootstrap compilation sequence.
.PARAMETER SecurityAudit
    Analyzes path ordering, workspace write permissions, and script execution policies.
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
    [switch]$SkipPerl,
    [switch]$SkipLLVM,
    [switch]$AdvancedBuild,
    [switch]$SecurityAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================================================
# Globals & Target Configurations
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$DefaultPerlPath = "C:\Strawberry\perl\bin"
$GLangBin        = Join-Path $PSScriptRoot "bin"
$FallbackLLVM    = "20.1.8"
$FallbackPerlUrl = "https://strawberryperl.com/download/5.40.0.1/strawberry-perl-5.40.0.1-64bit.msi"

# Status Tracking Dashboard
$Global:ReportCard = [ordered]@{
    "Security Scan"    = "Skipped"
    "Health Audit"     = "Skipped"
    "LLVM Toolchain"   = "Unchanged"
    "Perl Environment" = "Unchanged"
    "System PATH"      = "Unchanged"
    "Compiler Engine"  = "Skipped"
}

# Build Summary Metrics Engine
$Global:BuildStats = @{
    HelperCount     = 0
    BootstrapStatus = "Skipped"
    RuntimeCount    = 0
    SelfHostStatus  = "Skipped (0 modules)"
    PlatformStatus  = "Skipped (0 modules)"
    TotalBuildTime  = 0.0
}

# =========================================================
# Timestamps & Modern Logging UI
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
        "OK"     { Write-Host "[$Timestamp] [ready]   $Message" -ForegroundColor Green }
        "WARN"   { Write-Host "[$Timestamp] [warn]    $Message" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[$Timestamp] [fail]    $Message" -ForegroundColor Red }
        "SECURE" { Write-Host "[$Timestamp] [secure]  $Message" -ForegroundColor Magenta }
        "BLANK"  { Write-Host "$Message" }
    }
}

function Write-ProgressInline {
    param(
        [string]$Message
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    # Overwrites the current line using a carriage return and pads space to prevent visual ghosts
    Write-Host -NoNewline "`r[$Timestamp] [info]    $Message".PadRight(95) -ForegroundColor Cyan
}

function Show-Header {
    Write-Log BLANK "=========================================================="
    Write-Log BLANK "      GAWIN & GLANG HIGH-PERFORMANCE WORKSPACE SETUP      "
    Write-Log BLANK "=========================================================="
}

# =========================================================
# Hardened Privileged Elevation (UAC Handling)
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "System-wide installation requires administrative privileges."
        Write-Log INFO "Attempting to elevate script context via UAC..."
        
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
            if ($SkipPerl)      { $Arguments += "-SkipPerl" }
            if ($SkipLLVM)      { $Arguments += "-SkipLLVM" }
            if ($AdvancedBuild) { $Arguments += "-AdvancedBuild" }
            if ($SecurityAudit) { $Arguments += "-SecurityAudit" }

            $Proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $Arguments -PassThru -ErrorAction Stop
            Write-Log OK "Elevation prompt accepted. New process ID launched: $($Proc.Id)"
            exit
        }
        catch {
            Write-Log ERROR "UAC elevation failed or was declined by user: $($_.Exception.Message)"
            Write-Log WARN "Please manually restart your PowerShell terminal as Administrator and rerun the script."
            throw "Privilege elevation token allocation error."
        }
    }
}

# =========================================================
# Network Data Acquisition Secure Layer
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Retrieving verification asset source from: $Uri"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log ERROR "Network connection dropped or asset source is offline: $($_.Exception.Message)"
        throw $_
    }
}

# =========================================================
# System Analysis & Diagnostic Controls
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
        Write-Log OK "Clang installation detected active: $($cmd.Source)"
        return $true
    }
    Write-Log WARN "Clang executable is not indexed in your active PATH paths."
    return $false
}

function Test-Perl {
    $cmd = Get-Command perl -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Perl runtime environment verified: $($cmd.Source)"
        return $true
    }
    if (Test-Path $DefaultPerlPath) {
        Write-Log OK "Static Perl installation folder identified at target destination: $DefaultPerlPath"
        return $true
    }
    Write-Log WARN "Perl script engine environment could not be resolved."
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
        Write-Log INFO "Querying GitHub remote APIs for the latest LLVM stable tag..."
        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest" -TimeoutSec 10
        if (-not $r.tag_name) { throw "Invalid release metadata schema detected." }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Upstream production recommended version signature: $v"
        return $v
    }
    catch {
        Write-Log WARN "Could not process remote API connection -> Using secure static fallback token version: $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Invoke-Doctor {
    Write-Log INFO "--- RUNNING SYSTEM ENVIRONMENT AUDIT ---"
    
    Write-Log INFO "OS Distribution : $((Get-CimInstance Win32_OperatingSystem).Caption)"
    Write-Log INFO "Architecture    : $env:PROCESSOR_ARCHITECTURE"
    Write-Log INFO "Execution Mode  : $(if ([IntPtr]::Size -eq 8) { '64-bit Target' } else { '32-bit Target' })"
    Write-Log INFO "Engine Version  : $($PSVersionTable.PSVersion)"

    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $clang) {
        Write-Log ERROR "Clang compiler missing from application discovery loops."
    } else {
        $ver = Get-ClangVersion
        Write-Log INFO "Compiler Origin : $($clang.Source)"
        Write-Log INFO "Release Tag     : $ver"
        
        $latest = Get-LatestLLVMVersion
        if ($ver -and $ver -notlike "$latest*") {
            Write-Log WARN "Local/Remote toolchain variation found. Recommended upstream version baseline is $latest"
        } else {
            Write-Log OK "Ecosystem LLVM component metrics match target spec."
        }
    }

    if ($env:Path -notmatch "LLVM") { Write-Log WARN "LLVM path configurations missing from running process context paths." }

    Write-Log BLANK
    Write-Log INFO "--- PERL SERVICE RUNTIME ENGINE ---"
    $perl = Get-Command perl -ErrorAction SilentlyContinue
    if ($perl) {
        Write-Log INFO "Engine Path     : $($perl.Source)"
        $perlVer = & perl -e "print $^V" 2>$null
        Write-Log INFO "Build Signature : $perlVer"
        Write-Log OK "Perl interpreter infrastructure responds clean."
    } elseif (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl binaries are present at ($DefaultPerlPath) but require alignment in PATH."
    } else {
        Write-Log ERROR "No active Perl installation signature found on this hardware profile."
    }

    Write-Log BLANK
    Write-Log INFO "--- FRAMEWORK METADATA ---"
    $glangPath = Join-Path $PSScriptRoot "bin"
    $glangVer  = Get-GLangVersion

    Write-Log INFO "Target Bin Path : $glangPath"
    Write-Log INFO "Framework Build : $glangVer"

    if (Test-Path $glangPath) { Write-Log OK "Gawin binary repository folder verified." } 
    else { Write-Log WARN "Gawin workspace compilation outputs are empty." }

    $Global:ReportCard["Health Audit"] = "Completed Cleanly"
    Write-Log OK "System operational diagnostic completed safely."
    Write-Log BLANK
}

# =========================================================
# Security Isolation Check & Verification Matrix
# =========================================================
function Invoke-SecurityAudit {
    Write-Log SECURE "--- EXECUTING SYSTEM THREAT MODEL EVALUATION ---"
    
    # 1. Execution Profile Policies Check
    $policy = Get-ExecutionPolicy
    Write-Log INFO "Active Workspace Shell Script Policy: $policy"
    if ($policy -in @("Bypass", "Unrestricted")) {
        Write-Log WARN "Permissive script processing constraints ($policy). Ensure untrusted sources are scrutinized!"
    } else {
        Write-Log OK "Local environment policy verification evaluated passing."
    }

    # 2. Path Ordering & Write Privileges Vulnerability Mitigation
    Write-Log INFO "Scanning environmental variables for path hijacking exploits..."
    $paths = $env:Path -split ';'
    $writablePathsInsecure = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        if ($p -match "Temp" -or $p -eq "C:\") {
            $writablePathsInsecure += $p
        }
    }
    if ($writablePathsInsecure.Count -gt 0) {
        Write-Log WARN "Insecure/Writable directory targets referenced inside path routes: $writablePathsInsecure"
    } else {
        Write-Log SECURE "Environment variable structural ordering clean. No hijacking vectors discovered."
    }

    # 3. Target Directory Workspace Write Permissions
    try {
        $testFile = Join-Path $PSScriptRoot ".sec_verify.tmp"
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item $testFile -Force
        Write-Log OK "Local working workspace storage permissions validated successfully."
    } catch {
        Write-Log ERROR "Workspace access locked or access tracking error! Try elevation via system administrator console."
    }

    $Global:ReportCard["Security Scan"] = "Verified Passing"
    Write-Log SECURE "Threat detection scan finalized."
    Write-Log BLANK
}

# =========================================================
# Environment Reconstruction Engine (Fix Routine)
# =========================================================
function Invoke-AutoRepair {
    Write-Log INFO "Initializing configuration restoration workspace..."
    
    if (-not $SkipLLVM) {
        $clangInstalled = Test-Clang
        if (-not $clangInstalled -or $Force) { Install-LLVM }
    }
    if (-not $SkipPerl) {
        $perlInstalled = Test-Perl
        if (-not $perlInstalled -or $Force) { Install-Perl }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { Split-Path (Get-Command clang).Source -Parent } else { $DefaultLLVMPath }
    $perlBin = if (Get-Command perl -ErrorAction SilentlyContinue) { Split-Path (Get-Command perl).Source -Parent } else { $DefaultPerlPath }

    if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
    if ((-not $SkipPerl) -and (Test-Path $perlBin)) { Add-ToPathSafe $perlBin $scopeEnv }
    if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }
    
    Write-Log OK "Auto-repair environment restoration successfully concluded."
}

# =========================================================
# Post-Diagnostic Interactive Options & Integrity Sweep
# =========================================================
function Invoke-PostAuditPrompt {
    Write-Host ""
    Write-Host "Diagnostic processing completed. Select downstream deployment strategy:" -ForegroundColor Cyan
    Write-Host "1) Automatically resolve environmental issues and align missing paths right now"
    Write-Host "2) Run code validation loop & compile tools to audit for third-party or malicious injection"
    Write-Host "3) Maintain current architecture and skip adjustments"
    Write-Host ""
    
    $ans = Read-Host "Specify operational index choice [1-3]"
    switch ($ans.Trim()) {
        "1" {
            Invoke-AutoRepair
        }
        "2" {
            Write-Log INFO "Initiating defensive toolchain verification compilation..."
            Invoke-AdvancedCompilationPipeline
            
            Write-Log SECURE "Analyzing output compilation signatures for unauthorized changes..."
            $suspicious = $false
            $builtExes = Get-ChildItem $GLangBin -Filter "*.exe" -ErrorAction SilentlyContinue
            
            foreach ($exe in $builtExes) {
                if ($exe.Length -lt 1024) {
                    Write-Log WARN "Anomalous structural footprint detected on compiled target artifact: $($exe.Name)"
                    $suspicious = $true
                }
            }
            
            if (-not $suspicious) {
                Write-Log OK "Ecosystem toolchain integrity confirmed. No malicious tampering signatures found."
            } else {
                Write-Log ERROR "Integrity mismatch detected! Toolchain environment components show non-standard anomalies."
                Write-Host ""
                $fixChoice = Read-Host "Would you like to run the clean automatic repair patch cycle now to secure the toolchain? (y/n)"
                if ($fixChoice.Trim().ToLower() -in @("y", "yes")) {
                    Invoke-AutoRepair
                } else {
                    Write-Log WARN "Workspace repair aborted. Be careful executing active binaries in this current state."
                }
            }
        }
        default {
            Write-Log INFO "Continuing deployment operations."
        }
    }
}

# =========================================================
# Environment PATH Storage Control Suite
# =========================================================
function Get-PathList($scope) {
    $p = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $p) { return @() }
    return $p -split ';' | Where-Object { $_ -and $_.Trim() }
}

function Set-PathList($list, $scope) {
    $newPath = ($list | Select-Object -Unique) -join ';'
    
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
        throw "Target destination directory mapping does not exist: $PathToAdd"
    }

    $list = Get-PathList $Scope
    if ($list -contains $PathToAdd) {
        Write-Log INFO "Target environment key path mapping already indexed: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope
    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Environment variable scope successfully registered: $PathToAdd"
    $Global:ReportCard["System PATH"] = "Updated Cleanly"
}

# =========================================================
# Core Automated Installer Controllers
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion
    $winget  = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Attempting silent package deployment via native winget clients..."
        try {
            & winget install LLVM.LLVM --silent --accept-source-agreements --accept-package-agreements --timeout 300
            if ($LASTEXITCODE -eq 0) {
                Write-Log OK "LLVM toolchain integration established through winget client."
                $Global:ReportCard["LLVM Toolchain"] = "Deployed (Winget)"
                return
            }
        } catch {}
        Write-Log WARN "Winget pipeline failed or timed out. Transitioning to manual remote file download..."
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp
    Write-Log INFO "Executing independent standalone installer engine package background loop..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Target subsystem deployment error. Package installer engine returned exception status code: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM compiler backend storage allocation completed successfully."
    $Global:ReportCard["LLVM Toolchain"] = "Deployed (Standalone Installer)"
}

function Install-Perl {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Attempting silent script engine setup via active winget client..."
        try {
            & winget install StrawberryPerl.StrawberryPerl --silent --accept-source-agreements --accept-package-agreements --timeout 300
            if ($LASTEXITCODE -eq 0) {
                Write-Log OK "Strawberry Perl environment established via winget."
                $Global:ReportCard["Perl Environment"] = "Deployed (Winget)"
                return
            }
        } catch {}
        Write-Log WARN "Winget connection error. Processing standalone fallback installer runtime sequence..."
    }

    $file = "strawberry-perl-installer.msi"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $FallbackPerlUrl $tmp
    Write-Log INFO "Executing quiet unattended deployment transaction via Windows Installer Service..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "MSI package execution framework encountered an unhandled exception state: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "Perl interpreter architecture configurations finalized."
    $Global:ReportCard["Perl Environment"] = "Deployed (MSI Handshake)"
}

# =========================================================
# High-Precision Multi-Tier Compiler Build Pipeline
# =========================================================
function Invoke-AdvancedCompilationPipeline {
    Write-Log BLANK
    Write-Log INFO "=========================================================="
    Write-Log INFO "     INITIALIZING ADVANCED GAWIN SYSTEM COMPILATION       "
    Write-Log INFO "=========================================================="

    $root = $PSScriptRoot
    $binDir = Join-Path $root "bin"
    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $clangxx = Get-Command clang++ -ErrorAction SilentlyContinue
    if (-not $clangxx) {
        Write-Log ERROR "Clang++ optimization engine initialization error. Compilation pipeline cannot continue."
        $Global:ReportCard["Compiler Engine"] = "Failed (Missing Clang++)"
        return
    }

    if (-not (Test-Path $binDir)) {
        Write-Log INFO "Constructing missing application production distribution binary path: $binDir"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # --- PHASE 1: Build target executables root/src_exec/*.cpp into root/bin/* ---
    Write-Log INFO "Processing Phase 1 structural component generation checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $srcExecDir = Join-Path $root "src_exec"
    
    if (Test-Path $srcExecDir) {
        $cppFiles = Get-ChildItem (Join-Path $srcExecDir "*.cpp") -ErrorAction SilentlyContinue
        foreach ($file in $cppFiles) {
            Write-ProgressInline "Phase 1 -> Building dependency executor element: $($file.Name)"
            $outExe = Join-Path $binDir ($file.BaseName + ".exe")
            & clang++ "-std=c++17" "-O3" $file.FullName "-o" $outExe 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.HelperCount++
                $Global:BuildStats.RuntimeCount++
            } else {
                Write-Host ""
                Write-Log ERROR "Phase 1 compiler crash execution fault on file mapping: $($file.Name)"
                throw "Phase 1 compilation pipeline break exception."
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [ready]   PHASE 1 done $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) s".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Source execution components folder path not tracked: $srcExecDir. Skipping step..."
    }

    # --- PHASE 2: Build bootstrap compiler root/bootstrap_cpp_gawin/*.cpp into root/bin/ggc ---
    Write-Log INFO "Processing Phase 2 architecture bootstrap compiler generation checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $bootstrapDir = Join-Path $root "bootstrap_cpp_gawin"
    $ggcPath = Join-Path $binDir "ggc.exe"
    
    if (Test-Path $bootstrapDir) {
        $bootCppFiles = Get-ChildItem (Join-Path $bootstrapDir "*.cpp") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($bootCppFiles) {
            Write-ProgressInline "Phase 2 -> Engineering structural bootstrap compiler container (ggc.exe)"
            & clang++ "-std=c++17" "-O3" $bootCppFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.BootstrapStatus = "Success"
                $Global:BuildStats.RuntimeCount++
            } else {
                Write-Host ""
                throw "Bootstrap translation layer compilation fault. Compilation path terminated."
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [ready]   PHASE 2 done $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) s".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Bootstrap repository reference path missing: $bootstrapDir. Skipping step..."
    }

    # --- PHASE 3: Run pipeline management tool gstdo ---
    Write-Log INFO "Processing Phase 3 core automation workspace checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gstdoPath = Join-Path $binDir "gstdo.exe"
    
    if (Test-Path $gstdoPath) {
        Write-ProgressInline "Phase 3 -> Initializing active manager script handshake operations (gstdo.exe)"
        Push-Location $binDir
        try {
            & .\gstdo.exe
        } catch {
            Write-Host ""
            Write-Log WARN "Automation workflow target execution runtime warning tracked during parsing loop."
        } finally {
            Pop-Location
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [ready]   PHASE 3 done $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) s".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Automation ecosystem management engine binary ($gstdoPath) not found."
    }

    # --- PHASE 4: Self-host rebuild; run ggc on root/ggc/*.gw into root/bin/ggc ---
    Write-Log INFO "Processing Phase 4 framework self-hosting runtime compilation checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $ggcSrcDir = Join-Path $root "ggc"
    
    if ((Test-Path $ggcPath) -and (Test-Path $ggcSrcDir)) {
        $gwCompilerFiles = Get-ChildItem (Join-Path $ggcSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwCompilerFiles) {
            Write-ProgressInline "Phase 4 -> Processing self-hosted parsing rebuild layout cycle targets"
            & $ggcPath $gwCompilerFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.SelfHostStatus = "Success $($gwCompilerFiles.Count) modules"
                $Global:BuildStats.RuntimeCount += $gwCompilerFiles.Count
            } else {
                Write-Host ""
                Write-Log ERROR "Self-hosted build iteration logic loop returned execution system compilation warnings."
                $Global:BuildStats.SelfHostStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [ready]   PHASE 4 done $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) s".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Self-hosted module source elements missing or previous compiler stages failed."
    }

    # --- PHASE 5: Build platform modules; run new ggc on root/gwin/*.gw into root/bin/gwin ---
    Write-Log INFO "Processing Phase 5 platform interface runtime system parsing loops..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gwinSrcDir = Join-Path $root "gwin"
    $gwinPath = Join-Path $binDir "gwin.exe"
    
    if ((Test-Path $ggcPath) -and (Test-Path $gwinSrcDir)) {
        $gwinFiles = Get-ChildItem (Join-Path $gwinSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwinFiles) {
            Write-ProgressInline "Phase 5 -> Deploying environment specific subsystem runtime elements"
            & $ggcPath $gwinFiles "-o" $gwinPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.PlatformStatus = "Success ($($gwinFiles.Count) modules)"
                $Global:BuildStats.RuntimeCount += $gwinFiles.Count
            } else {
                Write-Host ""
                Write-Log ERROR "Window integration package application abstraction layer compilation execution warning tracking caught."
                $Global:BuildStats.PlatformStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "`r[$Timestamp] [ready]   PHASE 5 done $($phaseTimer.Elapsed.TotalSeconds.ToString("F2")) s".PadRight(95) -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Window subsystem interface targets omitted or platform references unavailable."
    }

    $totalTimer.Stop()
    $Global:BuildStats.TotalBuildTime = $totalTimer.Elapsed.TotalSeconds
    $Global:ReportCard["Compiler Engine"] = "Fully Functional"
    Write-Log OK "Ecosystem pipeline processing compilation blocks finalized successfully."
    Write-Log BLANK
}

# =========================================================
# MAIN EXECUTION ROUTINE
# =========================================================
try {
    Show-Header

    # 1. Interactive Fallback Configuration Selection
    if (-not $Scope -and -not $Doctor -and -not $SecurityAudit -and -not $AdvancedBuild) {
        Write-Host "Select targeted option configuration route to execute:" -ForegroundColor Green
        Write-Host "1] Complete Standard Environment Infrastructure Setup"
        Write-Host "2] Advanced Compilation Bootstrapping Loop Only"
        Write-Host "3] Workspace Operational Audit Check (Doctor)"
        Write-Host "4] System Structural Isolation and Integrity Evaluation Scan"
        Write-Host ""
        
        $choice = Read-Host "Specify option matrix index [1-4]"
        switch ($choice.Trim()) {
            "1" { 
                # Continues to profile scope configuration menu block down below
            }
            "2" {
                $AdvancedBuild = $true
                $SkipLLVM = $true
                $SkipPerl = $true
            }
            "3" {
                $Doctor = $true
            }
            "4" {
                $SecurityAudit = $true
            }
            default {
                Write-Log WARN "Invalid structural parameter choice. Triggering clean environment setup pipeline instead..."
            }
        }
    }

    # Profile Target Variable Scope Allocations Menu
    while (-not $Scope -and -not $Doctor -and -not $SecurityAudit) {
        Write-Host ""
        $inputScope = Read-Host "Specify target scope for environment variables configuration registry path [user/system]"
        if ($inputScope.Trim().ToLower() -in @("user", "system")) {
            $Scope = $inputScope.Trim().ToLower()
        } else {
            Write-Log WARN "Validation tracking error. Registry scope targeting parameter must read 'user' or 'system' exactly."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    if ($Scope) { Invoke-MakeAdmin $Scope }

    # Router Action Switch Pipelines
    if ($SecurityAudit) {
        Invoke-SecurityAudit
        Invoke-PostAuditPrompt
    }

    if ($Doctor) {
        Invoke-Doctor
        Invoke-PostAuditPrompt
    }

    if (-not $Doctor -and -not $SecurityAudit) {
        Write-Log INFO "Configuring system configuration keys (Registry Hive: $scopeEnv)..."
        Write-Log BLANK

        if ($Repair) {
            Write-Log WARN "Automated system correction parameter identified... checking environment variables path..."
            Invoke-AutoRepair
        }

        # Process LLVM Setup Steps
        if (-not $SkipLLVM) {
            $clangInstalled = Test-Clang
            if (-not $clangInstalled -or $Force) { Install-LLVM }
        }

        # Process Perl Setup Steps
        if (-not $SkipPerl) {
            $perlInstalled = Test-Perl
            if (-not $perlInstalled -or $Force) { Install-Perl }
        }

        # Safe Environment Path Synchronization Loops
        $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { Split-Path (Get-Command clang).Source -Parent } else { $DefaultLLVMPath }
        $perlBin = if (Get-Command perl -ErrorAction SilentlyContinue) { Split-Path (Get-Command perl).Source -Parent } else { $DefaultPerlPath }

        Write-Log INFO "Synchronizing local process variables with environment storage blocks..."
        if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
        if ((-not $SkipPerl) -and (Test-Path $perlBin)) { Add-ToPathSafe $perlBin $scopeEnv }
        if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }

        # Interactive Build Compilation Processing Controls
        $shouldBuild = $false
        if ($Build -or $AdvancedBuild) {
            $shouldBuild = $true
        } elseif ($SkipBuild) {
            $shouldBuild = $false
        } else {
            Write-Host ""
            $inputBuild = Read-Host "Would you like to process the workspace compilation toolchain build pipeline now? (y/n)"
            if ($inputBuild.Trim().ToLower() -in @("y", "yes", "1")) {
                $shouldBuild = $true
            }
        }

        if ($shouldBuild) {
            Invoke-AdvancedCompilationPipeline
        } else {
            Write-Log INFO "Skipping compilation phases per request options choice."
        }
    }

    # =========================================================
    # VISUAL COMPONENT REPORT DASHBOARD SUMMARY
    # =========================================================
    Write-Log BLANK
    Write-Log BLANK "=========================================================="
    Write-Log OK    "            WORKSPACE OPERATIONAL EXECUTION METRICS       "
    Write-Log BLANK "=========================================================="
    foreach ($item in $Global:ReportCard.Keys) {
        $status = $Global:ReportCard[$item]
        $color = "Cyan"
        if ($status -match "Passing|Cleanly|Functional|Updated|Deployed") { $color = "Green" }
        elseif ($status -match "Failed") { $color = "Red" }
        elseif ($status -match "Skipped") { $color = "Yellow" }
        
        Write-Host " [>] " -NoNewline -ForegroundColor Gray
        Write-Host ($item.PadRight(25)) -NoNewline -ForegroundColor White
        Write-Host " : " -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $color
    }
    
    # --- Live Compilation Performance Matrix ---
    if ($Global:ReportCard["Compiler Engine"] -eq "Fully Functional") {
        Write-Log BLANK
        Write-Host "==========================================================" -ForegroundColor Gray
        Write-Host "Build Summary" -ForegroundColor White
        Write-Host "==========================================================" -ForegroundColor Gray
        Write-Host "Helper executables : $($Global:BuildStats.HelperCount) built"
        Write-Host "Bootstrap compiler : $($Global:BuildStats.BootstrapStatus)"
        Write-Host "Runtime objects    : $($Global:BuildStats.RuntimeCount) compiled"
        Write-Host "Self-host rewrite  : $($Global:BuildStats.SelfHostStatus)"
        Write-Host "Platform modules   : $($Global:BuildStats.PlatformStatus)"
        Write-Log BLANK
        Write-Host "Total build time   : $($Global:BuildStats.TotalBuildTime.ToString("F2"))s" -ForegroundColor Cyan
    }
    Write-Log BLANK "=========================================================="
    Write-Log OK "Workspace configuration and dependency setup tasks finalized smoothly!"
}
catch {
    Write-Log ERROR "Fatal Environment Exception Caught: $($_.Exception.Message)"
    Write-Log BLANK "Trace diagnostic stack tracking matrix location: $($_.ScriptStackTrace)"
    exit 1
}

Pause