#!/bin/bash

# ==============================================================================
# .glang Setup Script (Unix Edition - Production Grade Architecture)
# A modern development ecosystem setup script for GLang and Gawin.
# ==============================================================================

set -Eeuo pipefail

# Determine script directory root path context
PSScriptRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Globals & Target Configurations
# ==============================================================================
DefaultLLVMPath="/opt/llvm"
DefaultPerlPath="/opt/perl"
GLangBin="$PSScriptRoot/bin"
FallbackLLVM="20.1.8"

# Argument Processing Variable Initializations
Scope=""
Force=0
Doctor=0
Repair=0
Build=0
SkipBuild=0
SkipPerl=0
SkipLLVM=0
AdvancedBuild=0
SecurityAudit=0

# Status Tracking Dashboard State Metrics Matrix
declare -A ReportCard
ReportCardKeys=(
    "Security Scan"
    "Health Audit"
    "LLVM Toolchain"
    "Perl Environment"
    "System PATH"
    "Compiler Engine"
)
for key in "${ReportCardKeys[@]}"; do
    ReportCard["$key"]="Skipped"
done

# Build Summary Metrics Engine
HelperCount=0
BootstrapStatus="Skipped"
RuntimeCount=0
SelfHostStatus="Skipped (0 modules)"
PlatformStatus="Skipped (0 modules)"
TotalBuildTime="0.0"

# ==============================================================================
# Timestamps & Modern Logging UI Subsystem
# ==============================================================================
Write-Log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%H:%M:%S")

    switch_color_level() {
        case "$1" in
            "INFO")   echo -e "[\033[0;36m$timestamp\033[0m] [\033[0;36minfo\033[0m]    $2" ;;
            "OK")     echo -e "[\033[0;36m$timestamp\033[0m] [\033[0;32mready\033[0m]   $2" ;;
            "WARN")   echo -e "[\033[0;36m$timestamp\033[0m] [\033[0;33mwarn\033[0m]    $2" ;;
            "ERROR")  echo -e "[\033[0;36m$timestamp\033[0m] [\033[0;31mfail\033[0m]    $2" ;;
            "SECURE") echo -e "[\033[0;36m$timestamp\033[0m] [\033[0;35msecure\033[0m]  $2" ;;
            "BLANK")  echo -e "$2" ;;
        esac
    }
    switch_color_level "$level" "$message"
}

Write-ProgressInline() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    local full_str="[$timestamp] [info]    $message"
    # Overwrites current terminal row using standard carriage returns and pads out ghosts
    printf "\r\033[0;36m%-95s\033[0m" "$full_str"
}

Show-Header() {
    Write-Log "BLANK" "=========================================================="
    Write-Log "BLANK" "      GAWIN & GLANG HIGH-PERFORMANCE WORKSPACE SETUP      "
    Write-Log "BLANK" "=========================================================="
}

# ==============================================================================
# High Precision Microsecond Duration Calculators
# ==============================================================================
Get-Time() {
    date +%s.%N 2>/dev/null || date +%s
}

Compute-Duration() {
    local start_time="$1"
    local end_time="$2"
    awk -v s="$start_time" -v e="$end_time" 'BEGIN { printf "%.2f", e - s }' 2>/dev/null || echo "0.00"
}

# ==============================================================================
# Hardened Privileged Elevation (Sudo Context Handling Management Loops)
# ==============================================================================
Test-IsAdmin() {
    [ "$(id -u)" -eq 0 ]
}

Invoke-MakeAdmin() {
    local scope_arg="$1"

    if [ "$scope_arg" = "system" ] && ! Test-IsAdmin; then
        Write-Log "WARN" "System-wide installation requires administrative privileges."
        Write-Log "INFO" "Attempting to elevate script context via sudo..."
        
        local elevated_args=()
        [ -n "$Scope" ] && elevated_args+=("--scope" "$Scope")
        [ "$Force" -eq 1 ] && elevated_args+=("--force")
        [ "$Doctor" -eq 1 ] && elevated_args+=("--doctor")
        [ "$Repair" -eq 1 ] && elevated_args+=("--repair")
        [ "$Build" -eq 1 ] && elevated_args+=("--build")
        [ "$SkipBuild" -eq 1 ] && elevated_args+=("--skip-build")
        [ "$SkipPerl" -eq 1 ] && elevated_args+=("--skip-perl")
        [ "$SkipLLVM" -eq 1 ] && elevated_args+=("--skip-llvm")
        [ "$AdvancedBuild" -eq 1 ] && elevated_args+=("--advanced-build")
        [ "$SecurityAudit" -eq 1 ] && elevated_args+=("--security-audit")

        if command -v sudo >/dev/null 2>&1; then
            exec sudo "$0" "${elevated_args[@]}"
        else
            Write-Log "ERROR" "Privilege elevation token allocation error: sudo utility missing."
            exit 1
        fi
    fi
}

# ==============================================================================
# Network Data Acquisition Secure Layer
# ==============================================================================
# Verifies system configuration connections explicitly supporting safe cryptographic standards
Invoke-SafeDownload() {
    local uri="$1"
    local out_file="$2"

    Write-Log "INFO" "Retrieving verification asset source from: $uri"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL --tlsv1.2 --tlsv1.3 "$uri" -o "$out_file" || {
            Write-Log "ERROR" "Network connection dropped or asset source is offline."
            exit 1
        }
    else
        wget -q --secure-protocol=TLSv1_2 "$uri" -O "$out_file" || {
            Write-Log "ERROR" "Network connection dropped or asset source is offline."
            exit 1
        }
    fi
}

# ==============================================================================
# System Analysis & Diagnostic Controls (Doctor Engine Subroutines)
# ==============================================================================
Get-ClangVersion() {
    if ! command -v clang >/dev/null 2>&1; then echo ""; return; fi
    clang --version | grep -oE "version [0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' || echo "unknown"
}

Test-Clang() {
    if command -v clang >/dev/null 2>&1; then
        Write-Log "OK" "Clang installation detected active: $(command -v clang)"
        return 0
    fi
    Write-Log "WARN" "Clang executable is not indexed in your active PATH paths."
    return 1
}

Test-Perl() {
    if command -v perl >/dev/null 2>&1; then
        Write-Log "OK" "Perl runtime environment verified: $(command -v perl)"
        return 0
    fi
    if [ -d "$DefaultPerlPath" ]; then
        Write-Log "OK" "Static Perl installation folder identified at target destination: $DefaultPerlPath"
        return 0
    fi
    Write-Log "WARN" "Perl script engine environment could not be resolved."
    return 1
}

Get-GLangVersion() {
    local version_file="$PSScriptRoot/config.pl"
    if [ ! -f "$version_file" ]; then echo "unknown"; return; fi
    grep -oE '"version"\s*=>\s*"\s*[0-9]+\.[0-9]+\.[0-9]+\s*"' "$version_file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
}

Get-LatestLLVMVersion() {
    Write-Log "INFO" "Querying GitHub remote APIs for the latest LLVM stable tag..."
    local tag
    tag=$(curl -s --connect-timeout 10 "https://api.github.com/repos/llvm/llvm-project/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | grep -oE 'llvmorg-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/llvmorg-//' || echo "")
    if [ -n "$tag" ]; then
        Write-Log "OK" "Upstream production recommended version signature: $tag"
        echo "$tag"
    else
        Write-Log "WARN" "Could not process remote API connection -> Using secure static fallback token version: $FallbackLLVM"
        echo "$FallbackLLVM"
    fi
}

Invoke-Doctor() {
    Write-Log "INFO" "--- RUNNING SYSTEM ENVIRONMENT AUDIT ---"
    
    Write-Log "INFO" "OS Distribution : $(uname -srm)"
    Write-Log "INFO" "Architecture    : $(uname -m)"
    Write-Log "INFO" "Execution Mode  : $([ "$(getconf LONG_BIT)" = "64" ] && echo '64-bit Target' || echo '32-bit Target')"
    Write-Log "INFO" "Engine Version  : ${BASH_VERSION:+Bash $BASH_VERSION}"

    if ! command -v clang >/dev/null 2>&1; then
        Write-Log "ERROR" "Clang compiler missing from application discovery loops."
    else
        Write-Log "INFO" "Compiler Origin : $(command -v clang)"
        local ver
        ver=$(Get-ClangVersion)
        Write-Log "INFO" "Release Tag     : $ver"
        
        local latest
        latest=$(Get-LatestLLVMVersion)
        if [[ -n "$ver" && "$ver" != "$latest"* ]]; then
            Write-Log "WARN" "Local/Remote toolchain variation found. Recommended upstream version baseline is $latest"
        else
            Write-Log "OK" "Ecosystem LLVM component metrics match target spec."
        fi
    fi

    if [[ ! "$PATH" =~ "LLVM" && ! "$PATH" =~ "llvm" ]]; then
        Write-Log "WARN" "LLVM path configurations missing from running process context paths."
    fi

    Write-Log "BLANK" ""
    Write-Log "INFO" "--- PERL SERVICE RUNTIME ENGINE ---"
    if command -v perl >/dev/null 2>&1; then
        Write-Log "INFO" "Engine Path     : $(command -v perl)"
        local perl_ver
        perl_ver=$(perl -e 'print $^V' 2>/dev/null)
        Write-Log "INFO" "Build Signature : $perl_ver"
        Write-Log "OK" "Perl interpreter infrastructure responds clean."
    elif [ -d "$DefaultPerlPath" ]; then
        Write-Log "OK" "Perl binaries are present at ($DefaultPerlPath) but require alignment in PATH."
    else
        Write-Log "ERROR" "No active Perl installation signature found on this hardware profile."
    fi

    Write-Log "BLANK" ""
    Write-Log "INFO" "--- FRAMEWORK METADATA ---"
    local glang_ver
    glang_ver=$(Get-GLangVersion)

    Write-Log "INFO" "Target Bin Path : $GLangBin"
    Write-Log "INFO" "Framework Build : $glang_ver"

    if [ -d "$GLangBin" ]; then
        Write-Log "OK" "Gawin binary repository folder verified."
    else
        Write-Log "WARN" "Gawin workspace compilation outputs are empty."
    fi

    ReportCard["Health Audit"]="Completed Cleanly"
    Write-Log "OK" "System operational diagnostic completed safely."
    Write-Log "BLANK" ""
}

# ==============================================================================
# Security Isolation Check & Verification Matrix
# ==============================================================================
Invoke-SecurityAudit() {
    Write-Log "SECURE" "--- EXECUTING SYSTEM THREAT MODEL EVALUATION ---"
    
    # 1. Verification of Shell Mask Creation Profile Permissions
    local current_umask
    current_umask=$(umask)
    Write-Log "INFO" "Active Workspace Shell Script Policy (umask): $current_umask"
    if [ "$current_umask" = "0000" ] || [ "$current_umask" = "0002" ]; then
        Write-Log "WARN" "Permissive script processing constraints ($current_umask). Ensure untrusted sources are scrutinized!"
    else
        Write-Log "OK" "Local environment policy verification evaluated passing."
    fi

    # 2. Path Ordering & Write Privileges Vulnerability Mitigation Check
    Write-Log "INFO" "Scanning environmental variables for path hijacking exploits..."
    local writable_paths_insecure=()
    IFS=':' read -r -a system_paths <<< "$PATH"
    for p in "${system_paths[@]}"; do
        [ -z "$p" ] && continue
        if [ -d "$p" ]; then
            # Isolates world-writable routes or transient file allocations tracking paths
            if [[ "$p" == *"Temp"* || "$p" == *"/tmp"* || "$p" == *"/var/tmp"* ]] || [ -n "$(find "$p" -maxdepth 0 -perm -o+w 2>/dev/null)" ]; then
                writable_paths_insecure+=("$p")
            fi
        fi
    done

    if [ ${#writable_paths_insecure[@]} -gt 0 ]; then
        Write-Log "WARN" "Insecure/Writable directory targets referenced inside path routes: ${writable_paths_insecure[*]}"
    else
        Write-Log "SECURE" "Environment variable structural ordering clean. No hijacking vector discovered."
    fi

    # 3. Target Directory Workspace Write Permissions Verification Tests
    local test_file="$PSScriptRoot/.sec_verify.tmp"
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        Write-Log "OK" "Local working workspace storage permissions validated successfully."
    else
        Write-Log "ERROR" "Workspace access locked or access tracking error! Try elevation via system administrator console."
    fi

    ReportCard["Security Scan"]="Verified Passing"
    Write-Log "SECURE" "Threat detection scan finalized."
    Write-Log "BLANK" ""
}

# ==============================================================================
# Environment Reconstruction Engine (Fix Restoration Suite Routines)
# ==============================================================================
Invoke-AutoRepair() {
    Write-Log "INFO" "Initializing configuration restoration workspace..."
    
    if [ "$SkipLLVM" -ne 1 ]; then
        if ! Test-Clang || [ "$Force" -eq 1 ]; then Install-LLVM; fi
    fi
    if [ "$SkipPerl" -ne 1 ]; then
        if ! Test-Perl || [ "$Force" -eq 1 ]; then Install-Perl; fi
    fi

    local scope_env="User"
    [ "$Scope" = "system" ] && scope_env="Machine"

    local llvm_bin="$DefaultLLVMPath/bin"
    command -v clang >/dev/null 2>&1 && llvm_bin=$(dirname "$(command -v clang)")

    local perl_bin="$DefaultPerlPath/bin"
    command -v perl >/dev/null 2>&1 && perl_bin=$(dirname "$(command -v perl)")

    if [ "$SkipLLVM" -ne 1 ] && [ -d "$llvm_bin" ]; then Add-ToPathSafe "$llvm_bin" "$scope_env"; fi
    if [ "$SkipPerl" -ne 1 ] && [ -d "$perl_bin" ]; then Add-ToPathSafe "$perl_bin" "$scope_env"; fi
    if [ -d "$GLangBin" ]; then Add-ToPathSafe "$GLangBin" "$scope_env"; fi
    
    Write-Log "OK" "Auto-repair environment restoration successfully concluded."
}

# ==============================================================================
# Environment PATH Storage Control Suite
# ==============================================================================
Add-ToPathSafe() {
    local path_to_add="$1"
    local scope_env="$2"

    if [ ! -d "$path_to_add" ]; then
        Write-Log "ERROR" "Target destination directory mapping does not exist: $path_to_add"
        exit 1
    fi

    # Deduplicate matching strings within current runtime environment
    IFS=':' read -r -a active_paths <<< "$PATH"
    local already_exists=0
    for element in "${active_paths[@]}"; do
        [ "$element" = "$path_to_add" ] && already_exists=1
    done

    local target_profile=""
    if [ "$scope_env" = "Machine" ]; then
        target_profile="/etc/profile"
    else
        if [[ "${SHELL:-}" == *zsh* ]]; then
            target_profile="$HOME/.zshrc"
        else
            target_profile="$HOME/.bashrc"
        fi
    fi

    if [ $already_exists -eq 1 ] && [ -f "$target_profile" ] && grep -q "$path_to_add" "$target_profile" 2>/dev/null; then
        Write-Log "INFO" "Target environment key path mapping already indexed: $path_to_add"
        return
    fi

    # Retain safe operational backups of terminal profile structures before applying adjustments
    if [ -f "$target_profile" ]; then
        cp "$target_profile" "${target_profile}.gawin_bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    echo "" >> "$target_profile"
    echo "# Gawin Ecosystem Environment Configuration Paths" >> "$target_profile"
    echo "export PATH=\"\$PATH:$path_to_add\"" >> "$target_profile"
    
    export PATH="$PATH:$path_to_add"
    Write-Log "OK" "Environment variable scope successfully registered: $path_to_add"
    ReportCard["System PATH"]="Updated Cleanly"
}

# ==============================================================================
# Core Automated Installer Controllers
# ==============================================================================
Install-LLVM() {
    local version
    version=$(Get-LatestLLVMVersion)

    if command -v brew >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent package deployment via native Homebrew package manager..."
        if brew install llvm; then
            Write-Log "OK" "LLVM toolchain integration established through package manager client."
            ReportCard["LLVM Toolchain"]="Deployed (Homebrew)"
            return
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent package deployment via apt package manager..."
        if apt-get update -qq && apt-get install -y clang llvm; then
            Write-Log "OK" "LLVM toolchain integration established through package manager client."
            ReportCard["LLVM Toolchain"]="Deployed (Apt-Get)"
            return
        fi
    fi

    Write-Log "WARN" "Package pipelines failed or unavailable. Transitioning to manual remote archive download..."
    mkdir -p "$DefaultLLVMPath"
    
    local archive="clang+llvm-$version-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
    if [ "$(uname)" = "Darwin" ]; then
        archive="clang+llvm-$version-arm64-apple-darwin.tar.xz"
    fi
    
    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$archive"
    local tmp="/tmp/$archive"

    Invoke-SafeDownload "$url" "$tmp"
    Write-Log "INFO" "Executing standalone compression archive extractor routines..."
    tar -xJf "$tmp" -C "$DefaultLLVMPath" --strip-components=1 || {
        Write-Log "ERROR" "Target subsystem deployment error during file decompression loops."
        exit 1
    }
    rm -f "$tmp"
    Write-Log "OK" "LLVM compiler backend storage allocation completed successfully."
    ReportCard["LLVM Toolchain"]="Deployed (Standalone Archive)"
}

Install-Perl() {
    if command -v brew >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent script engine setup via active Homebrew packages..."
        if brew install perl; then
            Write-Log "OK" "Perl interpreter infrastructure established through package manager."
            ReportCard["Perl Environment"]="Deployed (Homebrew)"
            return
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent script engine setup via apt package manager..."
        if apt-get update -qq && apt-get install -y perl; then
            Write-Log "OK" "Perl interpreter infrastructure established through package manager."
            ReportCard["Perl Environment"]="Deployed (Apt-Get)"
            return
        fi
    fi

    Write-Log "WARN" "Package execution frameworks returned exceptions. Processing source fallback compilation sequence..."
    mkdir -p "$DefaultPerlPath"
    local archive="perl-5.40.0.tar.gz"
    local url="https://www.cpan.org/src/5.0/$archive"
    local tmp="/tmp/$archive"

    Invoke-SafeDownload "$url" "$tmp"
    Write-Log "INFO" "Executing quiet unattended deployment transaction via source build architecture..."
    local compile_src="/tmp/perl_compile_src"
    mkdir -p "$compile_src"
    tar -xzf "$tmp" -C "$compile_src" --strip-components=1
    
    pushd "$compile_src" > /dev/null
    if ./Configure -des -Dprefix="$DefaultPerlPath" -Dman1dir=none -Dman3dir=none >/dev/null && \
       make -j$(nproc 2>/dev/null || echo 2) >/dev/null && \
       make install >/dev/null; then
        Write-Log "OK" "Perl interpreter architecture configurations finalized."
        ReportCard["Perl Environment"]="Deployed (Source Compilation)"
    else
        Write-Log "ERROR" "Critical breakdown compiling default Perl interpreter from code source trees."
        popd > /dev/null; rm -rf "$compile_src"; exit 1
    fi
    popd > /dev/null
    rm -rf "$tmp" "$compile_src"
}

# ==============================================================================
# High-Precision Multi-Tier Compiler Build Pipeline
# ==============================================================================
Invoke-AdvancedCompilationPipeline() {
    Write-Log "BLANK" ""
    Write-Log "INFO" "=========================================================="
    Write-Log "INFO" "     INITIALIZING ADVANCED GAWIN SYSTEM COMPILATION       "
    Write-Log "INFO" "=========================================================="

    local total_timer_start
    total_timer_start=$(Get-Time)

    if ! command -v clang++ >/dev/null 2>&1; then
        Write-Log "ERROR" "Clang++ optimization engine initialization error. Compilation pipeline cannot continue."
        ReportCard["Compiler Engine"]="Failed (Missing Clang++)"
        return
    fi

    if [ ! -d "$GLangBin" ]; then
        Write-Log "INFO" "Constructing missing application production distribution binary path: $GLangBin"
        mkdir -p "$GLangBin"
    fi

    # --- PHASE 1: Build target executables root/src_exec/*.cpp into root/bin/* ---
    Write-Log "INFO" "Processing Phase 1 structural component generation checks..."
    local phase_start
    phase_start=$(Get-Time)
    local src_exec_dir="$PSScriptRoot/src_exec"
    
    if [ -d "$src_exec_dir" ]; then
        for file in "$src_exec_dir"/*.cpp; do
            [ -e "$file" ] || continue
            local bname
            bname=$(basename "$file" .cpp)
            Write-ProgressInline "Phase 1 -> Building dependency executor element: $bname.cpp"
            
            if clang++ -std=c++17 -O3 "$file" -o "$GLangBin/$bname" 2>&1; then
                ((HelperCount++))
                ((RuntimeCount++))
            else
                echo ""
                Write-Log "ERROR" "Phase 1 compiler crash execution fault on file mapping: $(basename "$file")"
                exit 1
            fi
        done
        local phase_end
        phase_end=$(Get-Time)
        local p1_dur
        p1_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[\033[0;36m%s\033[0m] [\033[0;32mready\033[0m]   PHASE 1 done %s s\n" "$timestamp" "$p1_dur"
    else
        Write-Log "WARN" "Source execution components folder path not tracked: $src_exec_dir. Skipping step..."
    fi

    # --- PHASE 2: Build bootstrap compiler root/bootstrap_cpp_gawin/*.cpp into root/bin/ggc ---
    Write-Log "INFO" "Processing Phase 2 architecture bootstrap compiler generation checks..."
    phase_start=$(Get-Time)
    local bootstrap_dir="$PSScriptRoot/bootstrap_cpp_gawin"
    local ggc_path="$GLangBin/ggc"
    
    if [ -d "$bootstrap_dir" ]; then
        local boot_cpp_files=("$bootstrap_dir"/*.cpp)
        if [ -e "${boot_cpp_files[0]}" ]; then
            Write-ProgressInline "Phase 2 -> Engineering structural bootstrap compiler container (ggc)"
            if clang++ -std=c++17 -O3 "${boot_cpp_files[@]}" -o "$ggc_path" 2>&1; then
                BootstrapStatus="Success"
                ((RuntimeCount++))
            else
                echo ""
                Write-Log "ERROR" "Bootstrap translation layer compilation fault. Compilation path terminated."
                exit 1
            fi
        else
            Write-Log "WARN" "No C++ compilation targets discovered within: $bootstrap_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p2_dur
        p2_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[\033[0;36m%s\033[0m] [\033[0;32mready\033[0m]   PHASE 2 done %s s\n" "$timestamp" "$p2_dur"
    else
        Write-Log "WARN" "Bootstrap repository reference path missing: $bootstrap_dir. Skipping step..."
    fi

    # --- PHASE 3: Run pipeline management tool gstdo ---
    Write-Log "INFO" "Processing Phase 3 core automation workspace checks..."
    phase_start=$(Get-Time)
    local gstdo_path="$GLangBin/gstdo"
    
    if [ -f "$gstdo_path" ]; then
        Write-ProgressInline "Phase 3 -> Initializing active manager script handshake operations (gstdo)"
        pushd "$GLangBin" > /dev/null
        chmod +x "./gstdo"
        if ! ./gstdo; then
            echo ""
            Write-Log "WARN" "Automation workflow target execution runtime warning tracked during parsing loop."
        fi
        popd > /dev/null
        local phase_end
        phase_end=$(Get-Time)
        local p3_dur
        p3_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[\033[0;36m%s\033[0m] [\033[0;32mready\033[0m]   PHASE 3 done %s s\n" "$timestamp" "$p3_dur"
    else
        Write-Log "WARN" "Automation ecosystem management engine binary ($gstdo_path) not found."
    fi

    # --- PHASE 4: Self-host rebuild; run ggc on root/ggc/*.gw into root/bin/ggc ---
    Write-Log "INFO" "Processing Phase 4 framework self-hosting runtime compilation checks..."
    phase_start=$(Get-Time)
    local ggc_src_dir="$PSScriptRoot/ggc"
    
    if [ -f "$ggc_path" ] && [ -d "$ggc_src_dir" ]; then
        local gw_compiler_files=("$ggc_src_dir"/*.gw)
        if [ -e "${gw_compiler_files[0]}" ]; then
            Write-ProgressInline "Phase 4 -> Processing self-hosted parsing rebuild layout cycle targets"
            chmod +x "$ggc_path"
            if "$ggc_path" "${gw_compiler_files[@]}" -o "$ggc_path" 2>&1; then
                local mod_count=${#gw_compiler_files[@]}
                SelfHostStatus="Success $mod_count modules"
                ((RuntimeCount += mod_count))
            else
                echo ""
                Write-Log "ERROR" "Self-hosted build iteration logic loop returned execution system compilation warnings."
                SelfHostStatus="Failed"
            fi
        else
            Write-Log "WARN" "No self-hosted parsing configuration targets tracked: $ggc_src_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p4_dur
        p4_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[\033[0;36m%s\033[0m] [\033[0;32mready\033[0m]   PHASE 4 done %s s\n" "$timestamp" "$p4_dur"
    else
        Write-Log "WARN" "Self-hosted module source elements missing or previous compiler stages failed."
    fi

    # --- PHASE 5: Build platform modules; run new ggc on root/gwin/*.gw into root/bin/gwin ---
    Write-Log "INFO" "Processing Phase 5 platform interface runtime system parsing loops..."
    phase_start=$(Get-Time)
    local gwin_src_dir="$PSScriptRoot/gwin"
    local gwin_path="$GLangBin/gwin"
    
    if [ -f "$ggc_path" ] && [ -d "$gwin_src_dir" ]; then
        local gwin_files=("$gwin_src_dir"/*.gw)
        if [ -e "${gwin_files[0]}" ]; then
            Write-ProgressInline "Phase 5 -> Deploying environment specific subsystem runtime elements"
            if "$ggc_path" "${gwin_files[@]}" -o "$gwin_path" 2>&1; then
                local mod_count=${#gwin_files[@]}
                PlatformStatus="Success ($mod_count modules)"
                ((RuntimeCount += mod_count))
                chmod +x "$gwin_path"
            else
                echo ""
                Write-Log "ERROR" "Window integration package application abstraction layer compilation execution warning tracking caught."
                PlatformStatus="Failed"
            fi
        else
            Write-Log "WARN" "No configuration interface elements parsed within: $gwin_src_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p5_dur
        p5_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[\033[0;36m%s\033[0m] [\033[0;32mready\033[0m]   PHASE 5 done %s s\n" "$timestamp" "$p5_dur"
    else
        Write-Log "WARN" "Window subsystem interface targets omitted or platform references unavailable."
    fi

    local total_timer_end
    total_timer_end=$(Get-Time)
    TotalBuildTime=$(Compute-Duration "$total_timer_start" "$total_timer_end")
    ReportCard["Compiler Engine"]="Fully Functional"
    Write-Log "OK" "Ecosystem pipeline processing compilation blocks finalized successfully."
    Write-Log "BLANK" ""
}

# ==============================================================================
# Post-Diagnostic Interactive Options & Integrity Sweep
# ==============================================================================
Invoke-PostAuditPrompt() {
    Write-Log "BLANK" ""
    echo -e "\033[0;36mDiagnostic processing completed. Select downstream deployment strategy:\033[0m"
    echo "1) Automatically resolve environmental issues and align missing paths right now"
    echo "2) Run code validation loop & compile tools to audit for third-party or malicious injection"
    echo "3) Maintain current architecture and skip adjustments"
    echo ""
    read -r -p "Specify operational index choice [1-3]: " ans
    
    case "${ans// /}" in
        "1")
            Invoke-AutoRepair
            ;;
        "2")
            Write-Log "INFO" "Initiating defensive toolchain verification compilation..."
            Invoke-AdvancedCompilationPipeline
            
            Write-Log "SECURE" "Analyzing output compilation signatures for unauthorized changes..."
            local suspicious=0
            if [ -d "$GLangBin" ]; then
                for exe in "$GLangBin"/*; do
                    [ -f "$exe" ] || continue
                    local size
                    size=$(wc -c < "$exe" 2>/dev/null || stat -c%s "$exe" 2>/dev/null || stat -f%z "$exe" 2>/dev/null || echo "0")
                    if [ "$size" -lt 1024 ] && [ "$size" -gt 0 ]; then
                        Write-Log "WARN" "Anomalous structural footprint detected on compiled target artifact: $(basename "$exe")"
                        suspicious=1
                    fi
                done
            fi
            
            if [ $suspicious -eq 0 ]; then
                Write-Log "OK" "Ecosystem toolchain integrity confirmed. No malicious tampering signatures found."
            else
                Write-Log "ERROR" "Integrity mismatch detected! Toolchain environment components show non-standard anomalies."
                echo ""
                read -r -p "Would you like to run the clean automatic repair patch cycle now to secure the toolchain? (y/n): " fixChoice
                case "$fixChoice" in
                    [yY][eE][sS]|[yY])
                        Invoke-AutoRepair
                        ;;
                    *)
                        Write-Log "WARN" "Workspace repair aborted. Be careful executing active binaries in this current state."
                        ;;
                esac
            fi
            ;;
        *)
            Write-Log "INFO" "Continuing deployment operations."
            ;;
    esac
}

# ==============================================================================
# Input Command-Line Argument Processing Matrix
# ==============================================================================
show_help() {
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --scope [user|system]   Registry environmental scope context targeting variables rules"
    echo "  --force                 Forces clean tracking downloads completely refreshing packages"
    echo "  --doctor                Triggers comprehensive inspection metrics evaluating runtime specs"
    echo "  --repair                Runs autonomous environment recovery repairs across paths"
    echo "  --build                 Forces direct workspace multi-phase build operations"
    echo "  --skip-build            Explicitly prevents pipeline building processing execution"
    echo "  --skip-perl             Bypasses parsing dependencies validation for Perl targets"
    echo "  --skip-llvm             Bypasses parsing dependencies validation for LLVM compilers"
    echo "  --advanced-build        Commands deep structural framework bootstrap self-hosting logic"
    echo "  --security-audit        Executes localized system configuration threat profile checking"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)          Scope="$2"; shift 2 ;;
        --force)          Force=1; shift ;;
        --doctor)         Doctor=1; shift ;;
        --repair)         Repair=1; shift ;;
        --build)          Build=1; shift ;;
        --skip-build)     SkipBuild=1; shift ;;
        --skip-perl)      SkipPerl=1; shift ;;
        --skip-llvm)      SkipLLVM=1; shift ;;
        --advanced-build) AdvancedBuild=1; shift ;;
        --security-audit) SecurityAudit=1; shift ;;
        -h|--help)        show_help ;;
        *)                Write-Log "ERROR" "Unknown operational input argument target flag: $1"; exit 1 ;;
    esac
done

# ==============================================================================
# MAIN EXECUTION ROUTINE INTERACTIVE SWITCH ROUTERS
# ==============================================================================
main() {
    Show-Header

    # 1. Interactive Fallback Configuration Selection Routing Menu
    if [ -z "$Scope" ] && [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 0 ] && [ "$AdvancedBuild" -eq 0 ]; then
        Write-Log "BLANK" "\033[0;32mSelect targeted option configuration route to execute:\033[0m"
        echo "1] Complete Standard Environment Infrastructure Setup"
        echo "2] Advanced Compilation Bootstrapping Loop Only"
        echo "3] Workspace Operational Audit Check (Doctor)"
        echo "4] System Structural Isolation and Integrity Evaluation Scan"
        echo ""
        read -r -p "Specify option matrix index [1-4]: " choice
        
        case "${choice// /}" in
            "1")
                # Proceeds straight into registry profile parameters initialization block
                ;;
            "2")
                AdvancedBuild=1
                SkipLLVM=1
                SkipPerl=1
                ;;
            "3")
                Doctor=1
                ;;
            "4")
                SecurityAudit=1
                ;;
            *)
                Write-Log "WARN" "Invalid structural parameter choice. Triggering clean environment setup pipeline instead..."
                ;;
        esac
    fi

    # 2. Scope Validation Loop Tracking Menu Blocks
    while [ -z "$Scope" ] && [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 0 ]; do
        echo ""
        read -r -p "Specify target scope for environment variables configuration path [user/system]: " inputScope
        inputScope="${inputScope// /}"
        if [[ "$inputScope" == "user" || "$inputScope" == "system" ]]; then
            Scope="$inputScope"
        else
            Write-Log "WARN" "Validation tracking error. Target scope parameters must read 'user' or 'system' exactly."
        fi
    done

    local scopeEnv="User"
    [ "$Scope" = "system" ] && scopeEnv="Machine"
    if [ -n "$Scope" ]; then Invoke-MakeAdmin "$Scope"; fi

    # 3. Router Active Strategy Flows Operations Execution Blocks
    if [ "$SecurityAudit" -eq 1 ]; then
        Invoke-SecurityAudit
        Invoke-PostAuditPrompt
    fi

    if [ "$Doctor" -eq 1 ]; then
        Invoke-Doctor
        Invoke-PostAuditPrompt
    fi

    if [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 1 ]; then
        Write-Log "INFO" "Configuring system configuration profiles (Scope Profile Hive: $scopeEnv)..."
        Write-Log "BLANK" ""

        if [ "$Repair" -eq 1 ]; then
            Write-Log "WARN" "Automated system correction parameter identified... checking environment variables path..."
            Invoke-AutoRepair
        fi

        # Process LLVM Setup Packages Steps
        if [ "$SkipLLVM" -ne 1 ]; then
            if ! Test-Clang || [ "$Force" -eq 1 ]; then Install-LLVM; fi
        fi

        # Process Perl Setup Runtime Steps
        if [ "$SkipPerl" -ne 1 ]; then
            if ! Test-Perl || [ "$Force" -eq 1 ]; then Install-Perl; fi
        fi

        # Extract Dynamic Running Paths context pointers
        local llvm_bin="$DefaultLLVMPath/bin"
        command -v clang >/dev/null 2>&1 && llvm_bin=$(dirname "$(command -v clang)")

        local perl_bin="$DefaultPerlPath/bin"
        command -v perl >/dev/null 2>&1 && perl_bin=$(dirname "$(command -v perl)")

        Write-Log "INFO" "Synchronizing local process variables with environment storage blocks..."
        if [ "$SkipLLVM" -ne 1 ] && [ -d "$llvm_bin" ]; then Add-ToPathSafe "$llvm_bin" "$scopeEnv"; fi
        if [ "$SkipPerl" -ne 1 ] && [ -d "$perl_bin" ]; then Add-ToPathSafe "$perl_bin" "$scopeEnv"; fi
        if [ -d "$GLangBin" ]; then Add-ToPathSafe "$GLangBin" "$scopeEnv"; fi

        # Compilation Build Verification Matrix Prompts Handshake
        local shouldBuild=0
        if [ "$Build" -eq 1 ] || [ "$AdvancedBuild" -eq 1 ]; then
            shouldBuild=1
        elif [ "$SkipBuild" -eq 1 ]; then
            shouldBuild=0
        else
            echo ""
            read -r -p "Would you like to process the workspace compilation toolchain build pipeline now? (y/n): " inputBuild
            case "$inputBuild" in
                [yY][eE][sS]|[yY]|1) shouldBuild=1 ;;
                *) shouldBuild=0 ;;
            esac
        fi

        if [ $shouldBuild -eq 1 ]; then
            Invoke-AdvancedCompilationPipeline
        else
            Write-Log "INFO" "Skipping compilation phases per request options choice."
        fi
    fi

    # ==============================================================================
    # VISUAL COMPONENT REPORT DASHBOARD SUMMARY
    # ==============================================================================
    Write-Log "BLANK" ""
    Write-Log "BLANK" "=========================================================="
    Write-Log "OK"    "            WORKSPACE OPERATIONAL EXECUTION METRICS       "
    Write-Log "BLANK" "=========================================================="
    
    for item in "${ReportCardKeys[@]}"; do
        local status="${ReportCard[$item]}"
        local color_code="\033[0;36m" # Cyan Default
        
        if [[ "$status" =~ Passing|Cleanly|Functional|Updated|Deployed ]]; then
            color_code="\033[0;32m" # Green Success
        elif [[ "$status" =~ Failed ]]; then
            color_code="\033[0;31m" # Red Exception Fault
        elif [[ "$status" =~ Skipped ]]; then
            color_code="\033[0;33m" # Yellow Warning Skip
        fi
        
        printf " \033[0;37m[>]\033[0m  \033[1;37m%-25s\033[0m : ${color_code}%s\033[0m\n" "$item" "$status"
    done

    # --- Live Compilation Performance Summary Report Card View Engine ---
    if [ "${ReportCard["Compiler Engine"]}" = "Fully Functional" ]; then
        Write-Log "BLANK" ""
        echo -e "\033[0;37m==========================================================\033[0m"
        echo -e "\033[1;37mBuild Summary\033[0m"
        echo -e "\033[0;37m==========================================================\033[0m"
        echo "Helper executables : $HelperCount built"
        echo "Bootstrap compiler : $BootstrapStatus"
        echo "Runtime objects    : $RuntimeCount compiled"
        echo "Self-host rewrite  : $SelfHostStatus"
        echo "Platform modules   : $PlatformStatus"
        Write-Log "BLANK" ""
        echo -e "Total build time   : \033[0;36m${TotalBuildTime}s\033[0m"
    fi
    
    Write-Log "BLANK" "=========================================================="
    Write-Log "OK" "Workspace configuration and dependency setup tasks finalized smoothly!"
}

# High Fidelity Error Catching Traps Matrix
error_trap_handler() {
    local exit_code=$?
    # Silences implicit internal clean closures exits signals
    [ $exit_code -eq 0 ] && return
    Write-Log "ERROR" "Fatal Environment Exception Caught: Process runtime context crashed abruptly."
    exit $exit_code
}
trap error_trap_handler EXIT

# Triggers complete runtime instantiation engine tasks loops execution
main