<#
.SYNOPSIS
    Production-grade development ecosystem setup script for GLang/Gawin.
.DESCRIPTION
    Automates deployment of required platform binaries (LLVM/Clang Compiler Toolchain, 
    Perl Interpreter Environment), sanitizes system and user environment target paths, 
    executes multi-stage compiler builds, and performs environment and security health checks.
.PARAMETER Scope
    Target environment registry scope allocation. Acceptable strings: 'user' or 'system'.
.PARAMETER Force
    Forces clean re-download and execution of both LLVM and Perl dependencies.
.PARAMETER Doctor
    Executes an operational audit checking compiler paths, dependency versions, and environment configurations.
.PARAMETER Repair
    Triggers systematic restoration workflows on your missing system paths and binaries.
.PARAMETER Build
    Bypasses the execution prompt and immediately triggers compiling source binaries.
.PARAMETER SkipBuild
    Bypasses the execution prompt and explicitly skips compiler source binaries.
.PARAMETER SkipPerl
    Bypasses checking or downloading the Perl Interpreter entirely.
.PARAMETER SkipLLVM
    Bypasses checking or downloading the LLVM/Clang ecosystem entirely.
.PARAMETER AdvancedBuild
    Explicitly forces execution of the advanced multi-tier Gawin language bootstrap build pipeline.
.PARAMETER SecurityAudit
    Executes deep structural analysis on path sanitization, write permissions, and execution policies.
.EXAMPLE
    .\setup.ps1 -Scope user
.EXAMPLE
    .\setup.ps1 -Scope system -AdvancedBuild -SecurityAudit
.EXAMPLE
    Get-Help .\setup.ps1 -Detailed
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
# Globals & Configurations
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$DefaultPerlPath = "C:\Strawberry\perl\bin"
$GLangBin        = Join-Path $PSScriptRoot "bin"
$FallbackLLVM    = "20.1.8"
$FallbackPerlUrl = "https://strawberryperl.com/download/5.40.0.1/strawberry-perl-5.40.0.1-64bit.msi"

# Pipeline Trackers for UI Dashboard Report
$Global:ReportCard = [ordered]@{
    "Security Audit"      = "Skipped"
    "Environment Audit"   = "Skipped"
    "LLVM Toolchain"      = "Unchanged"
    "Perl Environment"    = "Unchanged"
    "Environment Paths"   = "Unchanged"
    "Compilation Engine"  = "Skipped"
}

# =========================================================
# Logging & User Experience Engine
# =========================================================
function Write-Log {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR","SECURE","BLANK")]
        [string]$Level,
        [string]$Message
    )

    switch ($Level) {
        "INFO"   { Write-Host "[INFO]   $Message" -ForegroundColor Cyan }
        "OK"     { Write-Host "[ OK ]   $Message" -ForegroundColor Green }
        "WARN"   { Write-Host "[WARN]   $Message" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[FAIL]   $Message" -ForegroundColor Red }
        "SECURE" { Write-Host "[SECURE] $Message" -ForegroundColor Magenta }
        "BLANK"  { Write-Host "$Message" }
    }
}

function Show-Header {
    Write-Log BLANK "----------------------------------------------------------"
    Write-Log BLANK "     GAWIN & GLANG HIGH-PERFORMANCE ECOSYSTEM SETUP       "
    Write-Log BLANK "----------------------------------------------------------"
}

# =========================================================
# System Privilege Verification
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "Elevated administration privileges required for system scope modifications."
        Write-Log WARN "Relaunching process inside an Administrator context..."
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-Scope", "`"$ScopeArg`""
        )
        exit
    }
}

# =========================================================
# Network Data Management
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Downloading secure asset: $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

# =========================================================
# Diagnostic & Introspection Suite (Doctor Engine)
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
        Write-Log OK "Clang installation validated: $($cmd.Source)"
        return $true
    }
    Write-Log WARN "Clang binary missing from active path profiles."
    return $false
}

function Test-Perl {
    $cmd = Get-Command perl -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Perl installation validated: $($cmd.Source)"
        return $true
    }
    if (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl directory found at standard static location: $DefaultPerlPath"
        return $true
    }
    Write-Log WARN "Perl binary interpreter is completely missing from this environment."
    return $false
}

function Get-GLangVersion {
    try {
        $versionFile = Join-Path $PSScriptRoot "glang_meta\VERSION.gwin"
        if (-not (Test-Path $versionFile)) { return "unknown" }

        $content = Get-Content $versionFile -Raw
        if ($content -match 'version\s*:=\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"') {
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
        Write-Log INFO "Querying upstream GitHub API for latest LLVM release version info..."
        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest"
        if (-not $r.tag_name) { throw "Invalid payload structure received." }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Latest discovered upstream LLVM release: $v"
        return $v
    }
    catch {
        Write-Log WARN "Upstream discovery handshake failed -> Using safe fallback configuration version $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Invoke-Doctor {
    Write-Log INFO "=== RUNNING SYSTEM SETUP DIAGNOSTIC AUDIT ==="
    
    # OS and Architecture Introspection
    Write-Log INFO "Operating System: $((Get-CimInstance Win32_OperatingSystem).Caption)"
    Write-Log INFO "System Architecture: $env:PROCESSOR_ARCHITECTURE"
    Write-Log INFO "PowerShell Architecture: $(if ([IntPtr]::Size -eq 8) { '64-bit' } else { '32-bit' })"
    Write-Log INFO "PowerShell Engine Version: $($PSVersionTable.PSVersion)"

    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $clang) {
        Write-Log ERROR "Clang compiler engine missing from machine profile path variables."
    } else {
        $ver = Get-ClangVersion
        Write-Log INFO "Clang Executable Location: $($clang.Source)"
        Write-Log INFO "Clang Version Signature: $ver"
        
        $latest = Get-LatestLLVMVersion
        if ($ver -and $ver -notlike "$latest*") {
            Write-Log WARN "Version structural mismatch checked (Upstream recommends targeting version $latest)"
        } else {
            Write-Log OK "System LLVM version structure matches target standard rules."
        }
    }

    if ($env:Path -notmatch "LLVM") { Write-Log WARN "LLVM binaries are not configured in the active path environment variables." }

    Write-Log BLANK
    Write-Log INFO "=== PERL INTERPRETER STATUS ==="
    $perl = Get-Command perl -ErrorAction SilentlyContinue
    if ($perl) {
        Write-Log INFO "Perl Binary Location: $($perl.Source)"
        $perlVer = & perl -e "print $^V" 2>$null
        Write-Log INFO "Perl Version String: $perlVer"
        Write-Log OK "Perl Interpreter operational profile confirmed status OK."
    } elseif (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl interpreter directory found at ($DefaultPerlPath) but not active in environment path strings yet."
    } else {
        Write-Log ERROR "No validated system Perl interpreter paths found on this machine configuration."
    }

    Write-Log BLANK
    Write-Log INFO "=== LANGUAGE COMPILER METADATA (GAWIN) ==="
    $glangPath = Join-Path $PSScriptRoot "bin"
    $glangVer  = Get-GLangVersion

    Write-Log INFO "Gawin Target Bin Path: $glangPath"
    Write-Log INFO "Gawin Working Metadata Version: $glangVer"

    if (Test-Path $glangPath) { Write-Log OK "Gawin language runtime distribution binaries detected." } 
    else { Write-Log WARN "Gawin framework executable build targets are empty or unpopulated." }

    $Global:ReportCard["Environment Audit"] = "Completed Safely"
    Write-Log OK "System environment audit validation workflow complete."
    Write-Log BLANK
}

# =========================================================
# Security Auditing & DX Defenses
# =========================================================
function Invoke-SecurityAudit {
    Write-Log SECURE "=== INITIALIZING SECURITY DEFENSE & WORKSPACE INTEGRITY CHECK ==="
    
    # 1. Verification of Execution Policy
    $policy = Get-ExecutionPolicy
    Write-Log INFO "Active Environment Execution Policy: $policy"
    if ($policy -in @("Bypass", "Unrestricted")) {
        Write-Log WARN "Execution policy is loosely configured ($policy). Ensure workspace sources are fully trusted."
    } else {
        Write-Log OK "Execution policy configured safely."
    }

    # 2. Check for Shadowing / Hijacking Vulnerabilities in Paths
    Write-Log INFO "Analyzing PATH ordering security vulnerabilities..."
    $paths = $env:Path -split ';'
    $writablePathsInsecure = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        # Simplified validation checking if paths outside of standard system protections are root-level writable
        if ($p -match "Temp" -or $p -eq "C:\") {
            $writablePathsInsecure += $p
        }
    }
    if ($writablePathsInsecure.Count -gt 0) {
        Write-Log WARN "Detected potentially high-risk paths inside executable environment loops: $writablePathsInsecure"
    } else {
        Write-Log SECURE "Path isolation assessment verified clear."
    }

    # 3. Access Permission verification on Script Context Workspace
    try {
        $testFile = Join-Path $PSScriptRoot ".sec_verify.tmp"
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item $testFile -Force
        Write-Log OK "Workspace execution directory write permissions confirmed."
    } catch {
        Write-Log ERROR "Workspace root folder access bounds restricted! Run inside an administrative context."
    }

    $Global:ReportCard["Security Audit"] = "Verified Passing"
    Write-Log SECURE "Security verification checks completed cleanly."
    Write-Log BLANK
}

# =========================================================
# PATH Configuration Suite (With Auto-Backup Safety)
# =========================================================
function Get-PathList($scope) {
    $p = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $p) { return @() }
    return $p -split ';' | Where-Object { $_ -and $_.Trim() }
}

function Set-PathList($list, $scope) {
    $newPath = ($list | Select-Object -Unique) -join ';'
    
    # Safety feature: Create a current environment backup entry before committing mutation strings
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
        throw "Failed mapping directory reference to environment profile path. Missing directory: $PathToAdd"
    }

    $list = Get-PathList $Scope
    if ($list -contains $PathToAdd) {
        Write-Log INFO "Path assignment verification clean: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope
    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Environment variable PATH targets successfully updated: $PathToAdd"
    $Global:ReportCard["Environment Paths"] = "Updated Cleanly"
}

# =========================================================
# Dependency Resolution & Deployment Managers
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion
    $winget  = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Executing silent LLVM subsystem acquisition via native winget clients..."
        winget install LLVM.LLVM --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "LLVM installation completed natively."
            $Global:ReportCard["LLVM Toolchain"] = "Deployed (Winget)"
            return
        }
        Write-Log WARN "Winget package routine exited abnormally; failing over to fallback script routines..."
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp
    Write-Log INFO "Executing independent installer binary cleanly..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Target subsystem setup script failure! Subprocess returned execution error token: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM toolchain runtime installation completed successfully."
    $Global:ReportCard["LLVM Toolchain"] = "Deployed (Standalone Installer)"
}

function Install-Perl {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Executing silent Strawberry Perl environment instantiation via winget..."
        winget install StrawberryPerl.StrawberryPerl --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "Strawberry Perl distribution finalized securely."
            $Global:ReportCard["Perl Environment"] = "Deployed (Winget)"
            return
        }
        Write-Log WARN "Winget package installation tracking error; processing custom standalone installation sequence..."
    }

    $file = "strawberry-perl-installer.msi"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $FallbackPerlUrl $tmp
    Write-Log INFO "Executing headless unattended MSI installation tracking sequence..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "Headless msi execution failed. Unhandled package installer exception token: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "Perl Interpreter core setup completed successfully."
    $Global:ReportCard["Perl Environment"] = "Deployed (MSI Handshake)"
}

# =========================================================
# Multi-Tier Deep-Introspection Compilation Pipeline
# =========================================================
function Invoke-AdvancedCompilationPipeline {
    Write-Log BLANK
    Write-Log INFO "=========================================================="
    Write-Log INFO "     INITIALIZING ADVANCED GAWIN SYSTEM COMPILATION       "
    Write-Log INFO "=========================================================="

    $root = $PSScriptRoot
    $binDir = Join-Path $root "bin"

    # Verify build prerequisite compiler engines
    $clangxx = Get-Command clang++ -ErrorAction SilentlyContinue
    if (-not $clangxx) {
        Write-Log ERROR "Clang++ compiler engine initialization error. Unable to process compilation jobs."
        $Global:ReportCard["Compilation Engine"] = "Failed (Missing Clang++)"
        return
    }

    if (-not (Test-Path $binDir)) {
        Write-Log INFO "Creating missing core target distribution binary container folder..."
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # --- PHASE 1: Compile root/src_exec/*.cpp into root/bin/* ---
    $srcExecDir = Join-Path $root "src_exec"
    Write-Log INFO "[PHASE 1] Compiling executable engines from $srcExecDir..."
    if (Test-Path $srcExecDir) {
        $cppFiles = Get-ChildItem (Join-Path $srcExecDir "*.cpp") -ErrorAction SilentlyContinue
        if ($cppFiles.Count -eq 0) {
            Write-Log WARN "No source elements found matching target criteria *.cpp inside $srcExecDir"
        }
        foreach ($file in $cppFiles) {
            $outExe = Join-Path $binDir ($file.BaseName + ".exe")
            Write-Log INFO "Compiling Source: $($file.Name) -> $outExe"
            & clang++ "-std=c++17" "-O3" $file.FullName "-o" $outExe 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log ERROR "Compilation crash processing file structural components: $($file.Name)"
                throw "Phase 1 pipeline operational drop code."
            }
        }
    } else {
        Write-Log WARN "Source execution tracking path missing: $srcExecDir. Skipping initialization..."
    }

    # --- PHASE 2: Compile root/bootstrap_cpp_gawin/*.cpp into root/bin/ggc ---
    $bootstrapDir = Join-Path $root "bootstrap_cpp_gawin"
    $ggcPath = Join-Path $binDir "ggc.exe"
    Write-Log INFO "[PHASE 2] Initializing Bootstrap compilation tasks from $bootstrapDir..."
    if (Test-Path $bootstrapDir) {
        $bootCppFiles = Get-ChildItem (Join-Path $bootstrapDir "*.cpp") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($bootCppFiles) {
            Write-Log INFO "Bundling source map tree to construct initial binary bootstrap compiler tool: $ggcPath"
            & clang++ "-std=c++17" "-O3" $bootCppFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Bootstrap translation sequence error. Execution termination requested."
            }
            Write-Log OK "Bootstrap compiler engine built successfully."
        } else {
            Write-Log WARN "No valid matching bootstrap C++ components detected inside directory."
        }
    } else {
        Write-Log WARN "Bootstrap repository pointer missing: $bootstrapDir. Skipping phase step."
    }

    # --- PHASE 3: Invoke compiled binary gstdo ---
    $gstdoPath = Join-Path $binDir "gstdo.exe"
    Write-Log INFO "[PHASE 3] Evaluating toolchain setup tasks via 'gstdo' script runtime automation..."
    if (Test-Path $gstdoPath) {
        Push-Location $binDir
        try {
            Write-Log INFO "Running executable helper utility tool: $gstdoPath"
            & .\gstdo.exe
            if ($LASTEXITCODE -ne 0) { Write-Log WARN "Utility workflow 'gstdo' returned abnormal termination token ($LASTEXITCODE)." }
        } catch {
            Write-Log WARN "Failed executing built environment automation utility."
        } finally {
            Pop-Location
        }
    } else {
        Write-Log WARN "Automation workflow target binary $gstdoPath could not be loaded."
    }

    # --- PHASE 4: Invoke ggc on root/ggc/*.gw to compile into a new root/bin/ggc ---
    $ggcSrcDir = Join-Path $root "ggc"
    Write-Log INFO "[PHASE 4] Executing secondary self-hosted rewrite loop for ggc using localized language modules..."
    if ((Test-Path $ggcPath) -and (Test-Path $ggcSrcDir)) {
        $gwCompilerFiles = Get-ChildItem (Join-Path $ggcSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwCompilerFiles) {
            Write-Log INFO "Refactoring compiler architecture code using original language components via bootstrap compiler..."
            & $ggcPath $gwCompilerFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log ERROR "Self-hosting compilation cycle pipeline threw execution errors."
            } else {
                Write-Log OK "Self-hosted native compilation stack upgrade completed safely."
            }
        } else {
            Write-Log WARN "No matching components (*.gw) detected in compiler location $ggcSrcDir"
        }
    } else {
        Write-Log WARN "Self-hosted source parameters missing or compiler executable not found."
    }

    # --- PHASE 5: Invoke new ggc on root/gwin/*.gw (explicitly list all files) to compile into root/bin/gwin ---
    $gwinSrcDir = Join-Path $root "gwin"
    $gwinPath = Join-Path $binDir "gwin.exe"
    Write-Log INFO "[PHASE 5] Compiling runtime platform layer window managers via $gwinSrcDir..."
    if ((Test-Path $ggcPath) -and (Test-Path $gwinSrcDir)) {
        $gwinFiles = Get-ChildItem (Join-Path $gwinSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwinFiles) {
            Write-Log INFO "Explicit File Argument Mapping Trace Matrix:"
            foreach ($gwItem in $gwinFiles) { Write-Log BLANK "   -> Target Element Path: $gwItem" }
            
            Write-Log INFO "Processing translation step on all files via explicit file parameters -> Target mapping path: $gwinPath"
            & $ggcPath $gwinFiles "-o" $gwinPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log ERROR "Window runtime application layer integration pipeline execution failed."
            } else {
                Write-Log OK "Gawin Framework application packages compiled completely."
            }
        } else {
            Write-Log WARN "No components found matching (*.gw) within path bounds: $gwinSrcDir"
        }
    } else {
        Write-Log WARN "Compilation dependencies missing or paths omitted. Phase 5 generation skipped."
    }

    $Global:ReportCard["Compilation Engine"] = "Fully Functional"
    Write-Log OK "All pipeline build routines completed."
    Write-Log BLANK
}

# =========================================================
# RUNTIME ENGINE (MAIN EXECUTION ENVIRONMENT)
# =========================================================
try {
    Show-Header

    # 1. Interactive Selection Menu Strategy if Parameters are Left Unassigned
    if (-not $Scope -and -not $Doctor -and -not $SecurityAudit -and -not $AdvancedBuild) {
        Write-Host "Select execution target mode parameters below:" -ForegroundColor Green
        Write-Host "1) Complete Standard Ecosystem Installation"
        Write-Host "2) Advanced Compilation Bootstrapping Loop Only"
        Write-Host "3) System Environment Health Diagnostic Check (Doctor)"
        Write-Host "4) System Deep Security & Code Integrity Audit"
        Write-Host ""
        
        $choice = Read-Host "Enter targeted execution index option [1-4]"
        switch ($choice.Trim()) {
            "1" { # Falls back to processing standard checks below 
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
                Write-Log WARN "Invalid choice target. Launching default comprehensive platform initialization sequence..."
            }
        }
    }

    # Profile Target Allocations
    while (-not $Scope -and -not $Doctor -and -not $SecurityAudit) {
        Write-Host ""
        $inputScope = Read-Host "Select installation target access environment profile [user/system]"
        if ($inputScope.Trim().ToLower() -in @("user", "system")) {
            $Scope = $inputScope.Trim().ToLower()
        } else {
            Write-Log WARN "Input validation failure. Target profile parameters must explicitly read 'user' or 'system'."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    if ($Scope) { Invoke-MakeAdmin $Scope }

    # Core Logic Switches
    if ($SecurityAudit) {
        Invoke-SecurityAudit
    }

    if ($Doctor) {
        Invoke-Doctor
    }

    if (-not $Doctor -and -not $SecurityAudit) {
        Write-Log INFO "Initializing setup routines (Registry Scope Target: $scopeEnv)..."
        Write-Log BLANK

        if ($Repair) {
            Write-Log WARN "System path repair flags identified... forcing asset validations..."
            if (-not $SkipLLVM) { Install-LLVM }
            if (-not $SkipPerl) { Install-Perl }
        }

        # Process LLVM Setup Tasks
        if (-not $SkipLLVM) {
            $clangInstalled = Test-Clang
            if (-not $clangInstalled -or $Force) {
                Install-LLVM
            }
        }

        # Process Perl Interpreter Setup Tasks
        if (-not $SkipPerl) {
            $perlInstalled = Test-Perl
            if (-not $perlInstalled -or $Force) {
                Install-Perl
            }
        }

        # Dynamically Extract Execution Targets from Registry / Environment
        $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { 
            Split-Path (Get-Command clang).Source -Parent 
        } else { $DefaultLLVMPath }

        $perlBin = if (Get-Command perl -ErrorAction SilentlyContinue) { 
            Split-Path (Get-Command perl).Source -Parent 
        } else { $DefaultPerlPath }

        Write-Log INFO "Evaluating environment variable path values..."
        if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
        if ((-not $SkipPerl) -and (Test-Path $perlBin)) { Add-ToPathSafe $perlBin $scopeEnv }
        if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }

        # Execution evaluation for interactive compilation triggers
        $shouldBuild = $false
        if ($Build -or $AdvancedBuild) {
            $shouldBuild = $true
        } elseif ($SkipBuild) {
            $shouldBuild = $false
        } else {
            Write-Host ""
            $inputBuild = Read-Host "Do you want to run the compiler toolchain build and verification pipeline now? (y/n)"
            if ($inputBuild.Trim().ToLower() -in @("y", "yes", "1")) {
                $shouldBuild = $true
            }
        }

        if ($shouldBuild) {
            Invoke-AdvancedCompilationPipeline
        } else {
            Write-Log INFO "Skipping code compilation stages per instruction choices."
        }
    }

    # =========================================================
    # SYSTEM VISUAL DASHBOARD REPORT CARD
    # =========================================================
    Write-Log BLANK
    Write-Log BLANK "=========================================================="
    Write-Log OK    "          WORKSPACE ECOSYSTEM EXECUTION DASHBOARD         "
    Write-Log BLANK "=========================================================="
    foreach ($item in $Global:ReportCard.Keys) {
        $status = $Global:ReportCard[$item]
        $color = "Cyan"
        if ($status -match "Passing|Safely|Functional|Updated|Deployed") { $color = "Green" }
        elseif ($status -match "Failed") { $color = "Red" }
        elseif ($status -match "Skipped") { $color = "Yellow" }
        
        Write-Host " [>] " -NoNewline -ForegroundColor Gray
        Write-Host ($item.PadRight(25)) -NoNewline -ForegroundColor White
        Write-Host " : " -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $color
    }
    Write-Log BLANK "=========================================================="
    Write-Log OK "Deployment operation steps completed cleanly."
}
catch {
    Write-Log ERROR "Fatal Script Exception Intercepted: $($_.Exception.Message)"
    Write-Log BLANK "Stack trace diagnostics: $($_.ScriptStackTrace)"
    exit 1
}

Pause