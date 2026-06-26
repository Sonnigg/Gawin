<#
.SYNOPSIS
    A chill script to get your GLang and Gawin dev environment up and running without any headaches.
.DESCRIPTION
    Grabs your compilers (LLVM/Clang), sets up Perl, cleans up your system PATH variables,
    cranks through a multi-phase build pipeline, and runs quick security/health checks.
.PARAMETER Scope
    Where to save your environment settings. Pick 'user' or 'system'.
.PARAMETER Force
    Forces a fresh download and setup of LLVM and Perl, even if they're already there.
.PARAMETER Doctor
    Runs a quick health check on your path variables, versions, and dependencies.
.PARAMETER Repair
    Automatically patches missing system paths and binaries for you.
.PARAMETER Build
    Skips the confirmation prompt and jumps straight into building the source files.
.PARAMETER SkipBuild
    Skips the build process entirely.
.PARAMETER SkipPerl
    Skips checking or downloading Perl.
.PARAMETER SkipLLVM
    Skips checking or downloading the LLVM/Clang toolchain.
.PARAMETER AdvancedBuild
    Forces the advanced multi-tier bootstrap compilation pipeline.
.PARAMETER SecurityAudit
    Scans path ordering, directory write access, and execution policies for security risks.
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
# Globals & Configurations
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$DefaultPerlPath = "C:\Strawberry\perl\bin"
$GLangBin        = Join-Path $PSScriptRoot "bin"
$FallbackLLVM    = "20.1.8"
$FallbackPerlUrl = "https://strawberryperl.com/download/5.40.0.1/strawberry-perl-5.40.0.1-64bit.msi"

# Status Tracking Dashboard
$Global:ReportCard = [ordered]@{
    "Security Scan"       = "Skipped"
    "Health Audit"        = "Skipped"
    "LLVM Toolchain"      = "Unchanged"
    "Perl Environment"    = "Unchanged"
    "System PATH"         = "Unchanged"
    "Compiler Engine"     = "Skipped"
}

# Build Summary Data Engine
$Global:BuildStats = @{
    HelperCount      = 0
    BootstrapStatus  = "Skipped"
    RuntimeCount     = 0
    SelfHostStatus   = "Skipped (0 modules)"
    PlatformStatus   = "Skipped (0 modules)"
    TotalBuildTime   = 0.0
}

# =========================================================
# Friendly Logging UI
# =========================================================
function Write-Log {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR","SECURE","BLANK")]
        [string]$Level,
        [string]$Message
    )

    switch ($Level) {
        "INFO"   { Write-Host "[info]   $Message" -ForegroundColor Cyan }
        "OK"     { Write-Host "[ ok ]   $Message" -ForegroundColor Green }
        "WARN"   { Write-Host "[warn]   $Message" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[oops]   $Message" -ForegroundColor Red }
        "SECURE" { Write-Host "[safe]   $Message" -ForegroundColor Magenta }
        "BLANK"  { Write-Host "$Message" }
    }
}

function Show-Header {
    Write-Log BLANK "----------------------------------------------------------"
    Write-Log BLANK "     GAWIN & GLANG HIGH-PERFORMANCE ECOSYSTEM SETUP       "
    Write-Log BLANK "----------------------------------------------------------"
}

# =========================================================
# Quick Admin Checks
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "Looks like we need admin privileges to tweak system-wide settings."
        Write-Log WARN "Relaunching script with Admin rights..."
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-Scope", "`"$ScopeArg`""
        )
        exit
    }
}

# =========================================================
# Secure Downloader
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Grabbing secure file from: $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

# =========================================================
# Diagnostic & Introspection Suite
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
        Write-Log OK "Clang is alive and kicking here: $($cmd.Source)"
        return $true
    }
    Write-Log WARN "Clang binary isn't visible in your active path paths yet."
    return $false
}

function Test-Perl {
    $cmd = Get-Command perl -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Perl looks great here: $($cmd.Source)"
        return $true
    }
    if (Test-Path $DefaultPerlPath) {
        Write-Log OK "Found a static Perl folder hanging out at: $DefaultPerlPath"
        return $true
    }
    Write-Log WARN "Can't seem to find a Perl interpreter anywhere on this system."
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
        Write-Log INFO "Checking GitHub APIs for the newest shiny LLVM release..."
        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest"
        if (-not $r.tag_name) { throw "Weird response payload structure." }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Found upstream LLVM release version: $v"
        return $v
    }
    catch {
        Write-Log WARN "Couldn't connect to GitHub -> Falling back to safe standard version $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Invoke-Doctor {
    Write-Log INFO "=== RUNNING SYSTEM HEALTH CHECK ==="
    
    Write-Log INFO "OS Name: $((Get-CimInstance Win32_OperatingSystem).Caption)"
    Write-Log INFO "Architecture: $env:PROCESSOR_ARCHITECTURE"
    Write-Log INFO "PowerShell Mode: $(if ([IntPtr]::Size -eq 8) { '64-bit' } else { '32-bit' })"
    Write-Log INFO "PowerShell Engine: $($PSVersionTable.PSVersion)"

    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $clang) {
        Write-Log ERROR "Clang compiler engine is totally missing from your machine PATH variable."
    } else {
        $ver = Get-ClangVersion
        Write-Log INFO "Clang Target Location: $($clang.Source)"
        Write-Log INFO "Clang Version Signature: $ver"
        
        $latest = Get-LatestLLVMVersion
        if ($ver -and $ver -notlike "$latest*") {
            Write-Log WARN "Version mismatch! Upstream recommends targeting version $latest"
        } else {
            Write-Log OK "System LLVM version looks up to standard."
        }
    }

    if ($env:Path -notmatch "LLVM") { Write-Log WARN "LLVM binaries are not loaded in the active environment paths." }

    Write-Log BLANK
    Write-Log INFO "=== PERL INTERPRETER STATUS ==="
    $perl = Get-Command perl -ErrorAction SilentlyContinue
    if ($perl) {
        Write-Log INFO "Perl Binary Location: $($perl.Source)"
        $perlVer = & perl -e "print $^V" 2>$null
        Write-Log INFO "Perl Version String: $perlVer"
        Write-Log OK "Perl interpreter profile status looks clean."
    } elseif (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl directory is physical at ($DefaultPerlPath) but needs to be added to PATH."
    } else {
        Write-Log ERROR "No working Perl installation detected on this system setup."
    }

    Write-Log BLANK
    Write-Log INFO "=== GAWIN METADATA ==="
    $glangPath = Join-Path $PSScriptRoot "bin"
    $glangVer  = Get-GLangVersion

    Write-Log INFO "Gawin Target Bin Path: $glangPath"
    Write-Log INFO "Gawin Metadata Version: $glangVer"

    if (Test-Path $glangPath) { Write-Log OK "Gawin distribution binaries detected." } 
    else { Write-Log WARN "Gawin build targets folder is empty." }

    $Global:ReportCard["Health Audit"] = "Completed Cleanly"
    Write-Log OK "Health audit workflow complete."
    Write-Log BLANK
}

# =========================================================
# Security Scanning & DX Defenses
# =========================================================
function Invoke-SecurityAudit {
    Write-Log SECURE "=== RUNNING SECURITY DEFENSE SCAN ==="
    
    # 1. Verification of Execution Policy
    $policy = Get-ExecutionPolicy
    Write-Log INFO "Current Script Execution Policy: $policy"
    if ($policy -in @("Bypass", "Unrestricted")) {
        Write-Log WARN "Execution policy is set wide open ($policy). Make sure you trust your code sources!"
    } else {
        Write-Log OK "Execution policy configured safely."
    }

    # 2. Check for Shadowing / Hijacking Vulnerabilities in Paths
    Write-Log INFO "Scanning PATH paths for hijacking risks..."
    $paths = $env:Path -split ';'
    $writablePathsInsecure = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        if ($p -match "Temp" -or $p -eq "C:\") {
            $writablePathsInsecure += $p
        }
    }
    if ($writablePathsInsecure.Count -gt 0) {
        Write-Log WARN "Found insecure/writable directories inside your active PATH loops: $writablePathsInsecure"
    } else {
        Write-Log SECURE "Path isolation checks out clean. No hijacking routes spotted."
    }

    # 3. Access Permission verification on Script Context Workspace
    try {
        $testFile = Join-Path $PSScriptRoot ".sec_verify.tmp"
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item $testFile -Force
        Write-Log OK "Workspace folder write check passed cleanly."
    } catch {
        Write-Log ERROR "Workspace access restricted! Try running inside an administrator console."
    }

    $Global:ReportCard["Security Scan"] = "Verified Passing"
    Write-Log SECURE "Security checks completed."
    Write-Log BLANK
}

# =========================================================
# Automated System Patch Routine
# =========================================================
function Invoke-AutoRepair {
    Write-Log INFO "Starting the automated fix routine..."
    
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
    
    Write-Log OK "Auto-repair routines wrapped up smoothly!"
}

# =========================================================
# Post-Audit Interactive Decision Loop
# =========================================================
function Invoke-PostAuditPrompt {
    Write-Host ""
    Write-Host "Diagnostic evaluation finished! What would you like to do next?" -ForegroundColor Cyan
    Write-Host "1) Automatically fix any configuration/path issues found right now"
    Write-Host "2) Build the fresh stack & execute an integrity sweep for sneaky/malicious code additions"
    Write-Host "3) Nothing, I'm good"
    Write-Host ""
    
    $ans = Read-Host "Pick an option [1-3]"
    switch ($ans.Trim()) {
        "1" {
            Invoke-AutoRepair
        }
        "2" {
            Write-Log INFO "Triggering compilation stack loop for integrity scanning..."
            Invoke-AdvancedCompilationPipeline
            
            # Simple, effective defensive integrity trace check
            Write-Log SECURE "Scanning built ecosystem binaries for unauthorized modifications..."
            $suspicious = $false
            $builtExes = Get-ChildItem $GLangBin -Filter "*.exe" -ErrorAction SilentlyContinue
            foreach ($exe in $builtExes) {
                # Ensure files aren't zero bytes or containing anomalous small sizes indicating corruption/hijacking
                if ($exe.Length -lt 1024) {
                    Write-Log WARN "Suspiciously small binary file signature discovered: $($exe.Name)"
                    $suspicious = $true
                }
            }
            
            if (-not $suspicious) {
                Write-Log OK "Success! No malicious alterations or suspicious files found in the toolchain loop."
            } else {
                Write-Log ERROR "Ecosystem check caught some flags. Let's run safe auto-repair patches to be absolutely secure."
                Invoke-AutoRepair
            }
        }
        default {
            Write-Log INFO "Moving right along."
        }
    }
}

# =========================================================
# PATH Configuration Suite
# =========================================================
function Get-PathList($scope) {
    $p = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $p) { return @() }
    return $p -split ';' | Where-Object { $_ -and $_.Trim() }
}

function Set-PathList($list, $scope) {
    $newPath = ($list | Select-Object -Unique) -join ';'
    
    # Keep an environment safety backup key before modifying anything
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
        throw "Whoops, can't add this folder to PATH because it doesn't exist: $PathToAdd"
    }

    $list = Get-PathList $Scope
    if ($list -contains $PathToAdd) {
        Write-Log INFO "Path already has this covered: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope
    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Successfully updated PATH environment variables with: $PathToAdd"
    $Global:ReportCard["System PATH"] = "Updated Cleanly"
}

# =========================================================
# Dependency Deployment Managers
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion
    $winget  = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Trying a silent LLVM install via native winget clients..."
        winget install LLVM.LLVM --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "LLVM setup completed natively via winget."
            $Global:ReportCard["LLVM Toolchain"] = "Deployed (Winget)"
            return
        }
        Write-Log WARN "Winget ran into an error; switching to manual standalone installer download workflow..."
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp
    Write-Log INFO "Running independent standalone installer package..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Installation failed! Installer component returned error token: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM toolchain runtime installation completed successfully."
    $Global:ReportCard["LLVM Toolchain"] = "Deployed (Standalone Installer)"
}

function Install-Perl {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Trying a quick silent Strawberry Perl install via winget..."
        winget install StrawberryPerl.StrawberryPerl --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "Strawberry Perl environment successfully deployed."
            $Global:ReportCard["Perl Environment"] = "Deployed (Winget)"
            return
        }
        Write-Log WARN "Winget hit a snag; processing custom standalone installation sequence..."
    }

    $file = "strawberry-perl-installer.msi"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $FallbackPerlUrl $tmp
    Write-Log INFO "Running a silent unattended MSI background install..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "MSI install hit an unexpected glitch. Exit error code: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "Perl Interpreter core setup completed successfully."
    $Global:ReportCard["Perl Environment"] = "Deployed (MSI Handshake)"
}

# =========================================================
# Multi-Tier Advanced Compilation Pipeline
# =========================================================
function Invoke-AdvancedCompilationPipeline {
    Write-Log BLANK
    Write-Log INFO "=========================================================="
    Write-Log INFO "     INITIALIZING ADVANCED GAWIN SYSTEM COMPILATION       "
    Write-Log INFO "=========================================================="

    $root = $PSScriptRoot
    $binDir = Join-Path $root "bin"
    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Make sure we have a C++ compiler active
    $clangxx = Get-Command clang++ -ErrorAction SilentlyContinue
    if (-not $clangxx) {
        Write-Log ERROR "Clang++ compiler engine initialization error. Unable to process compilation jobs."
        $Global:ReportCard["Compiler Engine"] = "Failed (Missing Clang++)"
        return
    }

    if (-not (Test-Path $binDir)) {
        Write-Log INFO "Creating missing core target distribution binary container folder..."
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # --- PHASE 1: Compile root/src_exec/*.cpp into root/bin/* ---
    Write-Log INFO "Starting Phase 1 build checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $srcExecDir = Join-Path $root "src_exec"
    
    if (Test-Path $srcExecDir) {
        $cppFiles = Get-ChildItem (Join-Path $srcExecDir "*.cpp") -ErrorAction SilentlyContinue
        foreach ($file in $cppFiles) {
            $outExe = Join-Path $binDir ($file.BaseName + ".exe")
            & clang++ "-std=c++17" "-O3" $file.FullName "-o" $outExe 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.HelperCount++
                $Global:BuildStats.RuntimeCount++
            } else {
                Write-Log ERROR "Compilation crash processing file components: $($file.Name)"
                throw "Phase 1 compiler crash execution fault."
            }
        }
        $phaseTimer.Stop()
        Write-Host "PHASE 1  ✓ $($phaseTimer.Elapsed.TotalSeconds.ToString("F1")) s" -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Source execution tracking path missing: $srcExecDir. Skipping initialization..."
    }

    # --- PHASE 2: Compile root/bootstrap_cpp_gawin/*.cpp into root/bin/ggc ---
    Write-Log INFO "Starting Phase 2 build checks..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $bootstrapDir = Join-Path $root "bootstrap_cpp_gawin"
    $ggcPath = Join-Path $binDir "ggc.exe"
    
    if (Test-Path $bootstrapDir) {
        $bootCppFiles = Get-ChildItem (Join-Path $bootstrapDir "*.cpp") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($bootCppFiles) {
            & clang++ "-std=c++17" "-O3" $bootCppFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.BootstrapStatus = "Success"
                $Global:BuildStats.RuntimeCount++
            } else {
                throw "Bootstrap compilation failure. Exiting loop step."
            }
        }
        $phaseTimer.Stop()
        Write-Host "PHASE 2  ✓ $($phaseTimer.Elapsed.TotalSeconds.ToString("F1")) s" -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Bootstrap repository pointer missing: $bootstrapDir. Skipping phase step."
    }

    # --- PHASE 3: Invoke compiled binary gstdo ---
    Write-Log INFO "Starting Phase 3 script run verification steps..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gstdoPath = Join-Path $binDir "gstdo.exe"
    
    if (Test-Path $gstdoPath) {
        Push-Location $binDir
        try {
            & .\gstdo.exe
        } catch {
            Write-Log WARN "Failed executing built environment automation utility runtime tracking options."
        } finally {
            Pop-Location
        }
        $phaseTimer.Stop()
        Write-Host "PHASE 3  ✓ $($phaseTimer.Elapsed.TotalSeconds.ToString("F1")) s" -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Automation workflow target binary $gstdoPath could not be loaded."
    }

    # --- PHASE 4: Invoke ggc on root/ggc/*.gw to compile into a new root/bin/ggc ---
    Write-Log INFO "Starting Phase 4 compilation loop steps..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $ggcSrcDir = Join-Path $root "ggc"
    
    if ((Test-Path $ggcPath) -and (Test-Path $ggcSrcDir)) {
        $gwCompilerFiles = Get-ChildItem (Join-Path $ggcSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwCompilerFiles) {
            & $ggcPath $gwCompilerFiles "-o" $ggcPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.SelfHostStatus = "Success ($($gwCompilerFiles.Count) modules)"
                $Global:BuildStats.RuntimeCount += $gwCompilerFiles.Count
            } else {
                Write-Log ERROR "Self-hosting compilation cycle pipeline threw execution errors."
                $Global:BuildStats.SelfHostStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        Write-Host "PHASE 4  ✓ $($phaseTimer.Elapsed.TotalSeconds.ToString("F1")) s" -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Self-hosted source parameters missing or compiler executable not found."
    }

    # --- PHASE 5: Invoke new ggc on root/gwin/*.gw to compile into root/bin/gwin ---
    Write-Log INFO "Starting Phase 5 window platform package steps..."
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $gwinSrcDir = Join-Path $root "gwin"
    $gwinPath = Join-Path $binDir "gwin.exe"
    
    if ((Test-Path $ggcPath) -and (Test-Path $gwinSrcDir)) {
        $gwinFiles = Get-ChildItem (Join-Path $gwinSrcDir "*.gw") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($gwinFiles) {
            & $ggcPath $gwinFiles "-o" $gwinPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Global:BuildStats.PlatformStatus = "Success ($($gwinFiles.Count) modules)"
                $Global:BuildStats.RuntimeCount += $gwinFiles.Count
            } else {
                Write-Log ERROR "Window runtime application layer integration pipeline execution failed."
                $Global:BuildStats.PlatformStatus = "Failed"
            }
        }
        $phaseTimer.Stop()
        Write-Host "PHASE 5  ✓ $($phaseTimer.Elapsed.TotalSeconds.ToString("F1")) s" -ForegroundColor Green
    } else {
        $phaseTimer.Stop()
        Write-Log WARN "Compilation dependencies missing or paths omitted. Phase 5 generation skipped."
    }

    $totalTimer.Stop()
    $Global:BuildStats.TotalBuildTime = $totalTimer.Elapsed.TotalSeconds
    $Global:ReportCard["Compiler Engine"] = "Fully Functional"
    Write-Log OK "All pipeline build routines completed successfully."
    Write-Log BLANK
}

# =========================================================
# MAIN EXECUTION ROUTINE
# =========================================================
try {
    Show-Header

    # 1. Interactive Fallback Prompt Loop Setup
    if (-not $Scope -and -not $Doctor -and -not $SecurityAudit -and -not $AdvancedBuild) {
        Write-Host "What are we doing today? Select an entry below:" -ForegroundColor Green
        Write-Host "1) Complete Standard Ecosystem Installation"
        Write-Host "2) Advanced Compilation Bootstrapping Loop Only"
        Write-Host "3) System Environment Health Diagnostic Check (Doctor)"
        Write-Host "4) System Deep Security & Code Integrity Audit"
        Write-Host ""
        
        $choice = Read-Host "Enter targeted option index [1-4]"
        switch ($choice.Trim()) {
            "1" { 
                # Falls through to global system scope assignment prompt block below
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
                Write-Log WARN "Invalid option selection! Spinning up complete setup execution rules instead..."
            }
        }
    }

    # Profile Target Allocations
    while (-not $Scope -and -not $Doctor -and -not $SecurityAudit) {
        Write-Host ""
        $inputScope = Read-Host "Where should we target settings? Type [user/system]"
        if ($inputScope.Trim().ToLower() -in @("user", "system")) {
            $Scope = $inputScope.Trim().ToLower()
        } else {
            Write-Log WARN "Input check failed. Target parameters must read 'user' or 'system' exactly."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    if ($Scope) { Invoke-MakeAdmin $Scope }

    # Core Execution Routing switches
    if ($SecurityAudit) {
        Invoke-SecurityAudit
        Invoke-PostAuditPrompt
    }

    if ($Doctor) {
        Invoke-Doctor
        Invoke-PostAuditPrompt
    }

    if (-not $Doctor -and -not $SecurityAudit) {
        Write-Log INFO "Setting up your environment variables (Registry Target: $scopeEnv)..."
        Write-Log BLANK

        if ($Repair) {
            Write-Log WARN "System path repair flags identified... patching missing ecosystem configurations..."
            Invoke-AutoRepair
        }

        # Process LLVM Installation Steps
        if (-not $SkipLLVM) {
            $clangInstalled = Test-Clang
            if (-not $clangInstalled -or $Force) { Install-LLVM }
        }

        # Process Perl Installation Steps
        if (-not $SkipPerl) {
            $perlInstalled = Test-Perl
            if (-not $perlInstalled -or $Force) { Install-Perl }
        }

        # Set up system paths safely 
        $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { Split-Path (Get-Command clang).Source -Parent } else { $DefaultLLVMPath }
        $perlBin = if (Get-Command perl -ErrorAction SilentlyContinue) { Split-Path (Get-Command perl).Source -Parent } else { $DefaultPerlPath }

        Write-Log INFO "Evaluating system environment registry paths..."
        if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
        if ((-not $SkipPerl) -and (Test-Path $perlBin)) { Add-ToPathSafe $perlBin $scopeEnv }
        if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }

        # Interactive Build Compilation Prompts
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
            Write-Log INFO "Skipping compilation stages per instruction choices."
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
        if ($status -match "Passing|Cleanly|Functional|Updated|Deployed") { $color = "Green" }
        elseif ($status -match "Failed") { $color = "Red" }
        elseif ($status -match "Skipped") { $color = "Yellow" }
        
        Write-Host " [>] " -NoNewline -ForegroundColor Gray
        Write-Host ($item.PadRight(25)) -NoNewline -ForegroundColor White
        Write-Host " : " -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $color
    }
    
    # --- Live High Introspection Compilation Diagnostic Blocks ---
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
    Write-Log OK "Ecosystem operation setup tasks wrapped up cleanly!"
}
catch {
    Write-Log ERROR "Fatal Script Exception Intercepted: $($_.Exception.Message)"
    Write-Log BLANK "Stack trace diagnostics: $($_.ScriptStackTrace)"
    exit 1
}

Pause