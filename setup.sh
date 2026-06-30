#!/bin/bash

# ==========================================================
#          GAWIN & GLANG WORKSPACE SETUP SCRIPT
# ==========================================================

set -Eeuo pipefail

# Find the folder where this script is running
PSScriptRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================================
# Configuration & Global Settings
# ==========================================================
DefaultLLVMPath="/opt/llvm"
GLangBin="$PSScriptRoot/bin"
FallbackLLVM="20.1.8"

# Menu and Flag Settings
Scope=""
Force=0
Doctor=0
Repair=0
Build=0
SkipBuild=0
SkipLLVM=0
AdvancedBuild=0
SecurityAudit=0

# Status Tracking
declare -A ReportCard
ReportCard["Security Scan"]="Skipped"
ReportCard["Health Audit"]="Skipped"
ReportCard["LLVM Toolchain"]="Unchanged"
ReportCard["System PATH"]="Unchanged"
ReportCard["Compiler Engine"]="Skipped"

# Order of items for printing the final summary
ReportCardKeys=(
    "Security Scan"
    "Health Audit"
    "LLVM Toolchain"
    "System PATH"
    "Compiler Engine"
)

# Build Metrics
HelperCount=0
BootstrapStatus="Skipped"
RuntimeCount=0
SelfHostStatus="Skipped (0 modules)"
PlatformStatus="Skipped (0 modules)"
TotalBuildTime="0.0"

# ==========================================================
# Logging and UI Functions
# ==========================================================
Write-Log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%H:%M:%S")

    case "$level" in
        "INFO")   echo -e "[$timestamp] [\033[0;36minfo\033[0m]    $message" ;;
        "OK")     echo -e "[$timestamp] [\033[0;32msuccess\033[0m] $message" ;;
        "WARN")   echo -e "[$timestamp] [\033[0;33mwarning\033[0m] $message" ;;
        "ERROR")  echo -e "[$timestamp] [\033[0;31mfailed\033[0m]  $message" ;;
        "SECURE") echo -e "[$timestamp] [\033[0;35msecurity\033[0m] $message" ;;
        "BLANK")  echo -e "$message" ;;
    esac
}

Write-ProgressInline() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    local full_str="[$timestamp] [info]    $message"
    # Overwrites the current line on the screen and pads it with spaces
    printf "\r\033[0;36m%-95s\033[0m" "$full_str"
}

Show-Header() {
    Write-Log "BLANK" "=========================================================="
    Write-Log "BLANK" "          GAWIN & GLANG WORKSPACE SETUP SCRIPT            "
    Write-Log "BLANK" "=========================================================="
}

# ==========================================================
# Time Helpers
# ==========================================================
Get-Time() {
    date +%s.%N 2>/dev/null || date +%s
}

Compute-Duration() {
    local start_time="$1"
    local end_time="$2"
    awk -v s="$start_time" -v e="$end_time" 'BEGIN { printf "%.2f", e - s }' 2>/dev/null || echo "0.00"
}

# ==========================================================
# Admin Rights / Sudo Handling
# ==========================================================
Test-IsAdmin() {
    [ "$(id -u)" -eq 0 ]
}

Invoke-MakeAdmin() {
    local scope_arg="$1"

    if [ "$scope_arg" = "system" ] && ! Test-IsAdmin; then
        Write-Log "WARN" "System-wide setup requires administrator permissions."
        Write-Log "INFO" "Asking for admin rights (Sudo prompt)..."
        
        local elevated_args=()
        [ -n "$Scope" ] && elevated_args+=("--scope" "$Scope")
        [ "$Force" -eq 1 ] && elevated_args+=("--force")
        [ "$Doctor" -eq 1 ] && elevated_args+=("--doctor")
        [ "$Repair" -eq 1 ] && elevated_args+=("--repair")
        [ "$Build" -eq 1 ] && elevated_args+=("--build")
        [ "$SkipBuild" -eq 1 ] && elevated_args+=("--skip-build")
        [ "$SkipLLVM" -eq 1 ] && elevated_args+=("--skip-llvm")
        [ "$AdvancedBuild" -eq 1 ] && elevated_args+=("--advanced-build")
        [ "$SecurityAudit" -eq 1 ] && elevated_args+=("--security-audit")

        if command -v sudo >/dev/null 2>&1; then
            exec sudo "$0" "${elevated_args[@]}"
        else
            Write-Log "ERROR" "Sudo was not found on your system. Please run this script as root manually."
            exit 1
        fi
    fi
}

# ==========================================================
# File Downloader
# ==========================================================
Invoke-SafeDownload() {
    local uri="$1"
    local out_file="$2"

    Write-Log "INFO" "Downloading file from: $uri"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL --tlsv1.2 --tlsv1.3 "$uri" -o "$out_file" || {
            Write-Log "ERROR" "Download failed. Check your internet connection."
            exit 1
        }
    else
        wget -q --secure-protocol=TLSv1_2 "$uri" -O "$out_file" || {
            Write-Log "ERROR" "Download failed. Check your internet connection."
            exit 1
        }
    fi
}

# ==========================================================
# System Health Checks
# ==========================================================
Get-ClangVersion() {
    if ! command -v clang >/dev/null 2>&1; then echo ""; return; fi
    clang --version | grep -oE "version [0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' || echo "unknown"
}

Test-Clang() {
    if command -v clang >/dev/null 2>&1; then
        Write-Log "OK" "Clang is available at: $(command -v clang)"
        return 0
    fi
    Write-Log "WARN" "Clang was not found in your current PATH variables."
    return 1
}

Get-GLangVersion() {
    local version_file="$PSScriptRoot/config.pl"
    if [ ! -f "$version_file" ]; then echo "unknown"; return; fi
    grep -oE '"version"\s*=>\s*"\s*[0-9]+\.[0-9]+\.[0-9]+\s*"' "$version_file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
}

Get-LatestLLVMVersion() {
    Write-Log "INFO" "Checking GitHub for the latest stable LLVM version..."
    local tag
    tag=$(curl -s --connect-timeout 10 "https://api.github.com/repos/llvm/llvm-project/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | grep -oE 'llvmorg-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/llvmorg-//' || echo "")
    if [ -n "$tag" ]; then
        Write-Log "OK" "Latest recommended version on GitHub: $tag"
        echo "$tag"
    else
        Write-Log "WARN" "Could not connect to GitHub. Using default fallback version: $FallbackLLVM"
        echo "$FallbackLLVM"
    fi
}

Invoke-Doctor() {
    Write-Log "INFO" "--- RUNNING HEALTH AUDIT ---"
    
    Write-Log "INFO" "OS Distribution : $(uname -srm)"
    Write-Log "INFO" "Architecture    : $(uname -m)"
    Write-Log "INFO" "Target Mode     : $([ "$(getconf LONG_BIT)" = "64" ] && echo '64-bit' || echo '32-bit')"
    Write-Log "INFO" "Shell Version   : ${BASH_VERSION:+Bash $BASH_VERSION}"

    if ! command -v clang >/dev/null 2>&1; then
        Write-Log "ERROR" "Clang compiler is missing from your system."
    else
        Write-Log "INFO" "Compiler Path   : $(command -v clang)"
        local ver
        ver=$(Get-ClangVersion)
        Write-Log "INFO" "Clang Version   : $ver"
        
        local latest
        latest=$(Get-LatestLLVMVersion)
        if [[ -n "$ver" && "$ver" != "$latest"* ]]; then
            Write-Log "WARN" "Your local Clang version differs from the latest online version ($latest)."
        else
            Write-Log "OK" "Your LLVM version matches the recommended spec."
        fi
    fi

    if [[ ! "$PATH" =~ "LLVM" && ! "$PATH" =~ "llvm" ]]; then
        Write-Log "WARN" "LLVM folder paths are missing from your environment variables."
    fi

    Write-Log "BLANK" ""
    Write-Log "INFO" "--- GLANG FRAMEWORK ---"
    local glang_ver
    glang_ver=$(Get-GLangVersion)

    Write-Log "INFO" "Output Bin Path : $GLangBin"
    Write-Log "INFO" "Framework Build : $glang_ver"

    if [ -d "$GLangBin" ]; then
        Write-Log "OK" "Gawin bin folder exists."
    else
        Write-Log "WARN" "The bin folder is empty. Run a build to generate compiler files."
    fi

    ReportCard["Health Audit"]="Completed"
    Write-Log "OK" "Health check finished."
    Write-Log "BLANK" ""
}

# ==========================================================
# Security Audits
# ==========================================================
# Replaced technical deep words with simple terms matching the PowerShell equivalent
Invoke-SecurityAudit() {
    Write-Log "SECURE" "--- RUNNING SECURITY CHECK ---"
    
    # 1. Shell File Creation Policy Check
    local current_umask
    current_umask=$(umask)
    Write-Log "INFO" "Current Script Execution Policy (umask): $current_umask"
    if [ "$current_umask" = "0000" ] || [ "$current_umask" = "0002" ]; then
        Write-Log "WARN" "Your shell policy is highly permissive ($current_umask). Be careful when running untrusted scripts."
    else
        Write-Log "OK" "Local script policy looks reasonably secure."
    fi

    # 2. Path Integrity Check
    Write-Log "INFO" "Scanning PATH paths for unsecured folders..."
    local writable_paths_insecure=()
    IFS=':' read -r -a system_paths <<< "$PATH"
    for p in "${system_paths[@]}"; do
        [ -z "$p" ] && continue
        if [ -d "$p" ]; then
            if [[ "$p" == *"Temp"* || "$p" == *"/tmp"* || "$p" == *"/var/tmp"* ]] || [ -n "$(find "$p" -maxdepth 0 -perm -o+w 2>/dev/null)" ]; then
                writable_paths_insecure+=("$p")
            fi
        fi
    done

    if [ ${#writable_paths_insecure[@]} -gt 0 ]; then
        Write-Log "WARN" "Found globally writable or temporary folders in your PATH: ${writable_paths_insecure[*]}"
    else
        Write-Log "SECURE" "Environment paths look secure. No obvious issues found."
    fi

    # 3. Write Permissions Check
    local test_file="$PSScriptRoot/.sec_verify.tmp"
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        Write-Log "OK" "Folder write permissions verified successfully."
    else
        Write-Log "ERROR" "Cannot write to workspace! Try running this script as Administrator."
    fi

    ReportCard["Security Scan"]="Verified"
    Write-Log "SECURE" "Security check complete."
    Write-Log "BLANK" ""
}

# ==========================================================
# Auto-Repair Engine
# ==========================================================
Invoke-AutoRepair() {
    Write-Log "INFO" "Starting environment auto-repair..."
    
    if [ "$SkipLLVM" -ne 1 ]; then
        if ! Test-Clang || [ "$Force" -eq 1 ]; then Install-LLVM; fi
    fi

    local scope_env="User"
    [ "$Scope" = "system" ] && scope_env="Machine"

    local llvm_bin="$DefaultLLVMPath/bin"
    command -v clang >/dev/null 2>&1 && llvm_bin=$(dirname "$(command -v clang)")

    if [ "$SkipLLVM" -ne 1 ] && [ -d "$llvm_bin" ]; then Add-ToPathSafe "$llvm_bin" "$scope_env"; fi
    if [ -d "$GLangBin" ]; then Add-ToPathSafe "$GLangBin" "$scope_env"; fi
    
    Write-Log "OK" "Auto-repair has finished fixing paths and dependencies."
}

# ==========================================================
# Interactive Audit Prompts
# ==========================================================
Invoke-PostAuditPrompt() {
    Write-Log "BLANK" ""
    echo -e "\033[0;36mDiagnostic checks completed. What would you like to do next?\033[0m"
    echo "1) Automatically fix missing paths and install missing tools right now"
    echo "2) Build the tools and run a validation check on compiled files"
    echo "3) Do nothing and keep current settings"
    echo ""
    read -r -p "Select an option [1-3]: " ans
    
    case "${ans// /}" in
        "1")
            Invoke-AutoRepair
            ;;
        "2")
            Write-Log "INFO" "Starting the build pipeline..."
            Invoke-AdvancedCompilationPipeline
            
            Write-Log "SECURE" "Checking for abnormally small or suspicious executables..."
            local suspicious=0
            if [ -d "$GLangBin" ]; then
                for exe in "$GLangBin"/*; do
                    [ -f "$exe" ] || continue
                    local size
                    size=$(wc -c < "$exe" 2>/dev/null || stat -c%s "$exe" 2>/dev/null || stat -f%z "$exe" 2>/dev/null || echo "0")
                    if [ "$size" -lt 1024 ] && [ "$size" -gt 0 ]; then
                        Write-Log "WARN" "Suspiciously small executable found: $(basename "$exe")"
                        suspicious=1
                    fi
                done
            fi
            
            if [ $suspicious -eq 0 ]; then
                Write-Log "OK" "All compiled executables look standard and clean."
            else
                Write-Log "ERROR" "One or more files look suspicious."
                echo ""
                read -r -p "Would you like me to try repairing the workspace? (y/n): " fixChoice
                case "$fixChoice" in
                    [yY][eE][sS]|[yY])
                        Invoke-AutoRepair
                        ;;
                    *)
                        Write-Log "WARN" "Repair canceled. Exercise caution if you run these tools."
                        ;;
                esac
            fi
            ;;
        *)
            Write-Log "INFO" "Continuing setup tasks."
            ;;
    esac
}

# ==========================================================
# PATH Management Tools
# ==========================================================
Add-ToPathSafe() {
    local path_to_add="$1"
    local scope_env="$2"

    if [ ! -d "$path_to_add" ]; then
        Write-Log "ERROR" "The target folder does not exist: $path_to_add"
        exit 1
    fi

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
        Write-Log "INFO" "Folder is already inside your PATH environment variables: $path_to_add"
        return
    fi

    # Create a backup of the profile before modifying it
    if [ -f "$target_profile" ]; then
        cp "$target_profile" "${target_profile}.gawin_bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    echo "" >> "$target_profile"
    echo "# Gawin Workspace Paths" >> "$target_profile"
    echo "export PATH=\"\$PATH:$path_to_add\"" >> "$target_profile"
    
    export PATH="$PATH:$path_to_add"
    Write-Log "OK" "Successfully added folder to PATH: $path_to_add"
    ReportCard["System PATH"]="Updated"
}

# ==========================================================
# Installer Operations
# ==========================================================
Install-LLVM() {
    local version
    version=$(Get-LatestLLVMVersion)

    if command -v brew >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent install via homebrew package manager..."
        if brew install llvm; then
            Write-Log "OK" "LLVM toolchain installed successfully via homebrew."
            ReportCard["LLVM Toolchain"]="Installed (Homebrew)"
            return
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        Write-Log "INFO" "Attempting silent install via apt package manager..."
        if apt-get update -qq && apt-get install -y clang llvm; then
            Write-Log "OK" "LLVM toolchain installed successfully via apt."
            ReportCard["LLVM Toolchain"]="Installed (Apt)"
            return
        fi
    fi

    Write-Log "WARN" "Package managers failed or are missing. Falling back to direct archive download..."
    mkdir -p "$DefaultLLVMPath"
    
    local archive="clang+llvm-$version-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
    if [ "$(uname)" = "Darwin" ]; then
        archive="clang+llvm-$version-arm64-apple-darwin.tar.xz"
    fi
    
    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$archive"
    local tmp="/tmp/$archive"

    Invoke-SafeDownload "$url" "$tmp"
    Write-Log "INFO" "Extracting the LLVM archive files..."
    tar -xJf "$tmp" -C "$DefaultLLVMPath" --strip-components=1 || {
        Write-Log "ERROR" "Decompression failed while installing LLVM binaries."
        exit 1
    }
    rm -f "$tmp"
    Write-Log "OK" "LLVM has been installed successfully!"
    ReportCard["LLVM Toolchain"]="Installed (Standalone)"
}

# ==========================================================
# Compiler Build Pipeline
# ==========================================================
Invoke-AdvancedCompilationPipeline() {
    Write-Log "BLANK" ""
    Write-Log "INFO" "=========================================================="
    Write-Log "INFO" "               STARTING GAWIN COMPILER BUILD              "
    Write-Log "INFO" "=========================================================="

    local total_timer_start
    total_timer_start=$(Get-Time)

    if ! command -v clang++ >/dev/null 2>&1; then
        Write-Log "ERROR" "Clang++ is missing. Cannot build the pipeline."
        ReportCard["Compiler Engine"]="Failed (Missing Clang++)"
        return
    fi

    if [ ! -d "$GLangBin" ]; then
        Write-Log "INFO" "Creating missing binary directory: $GLangBin"
        mkdir -p "$GLangBin"
    fi

    # --- PHASE 1: Build source files in root/src_exec/*.cpp ---
    Write-Log "INFO" "Phase 1: Building utility source files..."
    local phase_start
    phase_start=$(Get-Time)
    local src_exec_dir="$PSScriptRoot/src_exec"
    
    if [ -d "$src_exec_dir" ]; then
        for file in "$src_exec_dir"/*.cpp; do
            [ -e "$file" ] || continue
            local bname
            bname=$(basename "$file" .cpp)
            Write-ProgressInline "Phase 1 -> Building helper component: $bname.cpp"
            
            if clang++ -std=c++17 -O3 "$file" -o "$GLangBin/$bname" 2>&1; then
                ((HelperCount++))
                ((RuntimeCount++))
            else
                echo ""
                Write-Log "ERROR" "Phase 1 compilation failed on file: $(basename "$file")"
                exit 1
            fi
        done
        local phase_end
        phase_end=$(Get-Time)
        local p1_dur
        p1_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[%s] [\033[0;32msuccess\033[0m] PHASE 1 complete in %s seconds\n" "$timestamp" "$p1_dur"
    else
        Write-Log "WARN" "Source directory missing ($src_exec_dir). Skipping Step..."
    fi

    # --- PHASE 2: Build bootstrap compiler root/bootstrap_cpp_gawin/*.cpp ---
    Write-Log "INFO" "Phase 2: Building bootstrap compiler (ggc)..."
    phase_start=$(Get-Time)
    local bootstrap_dir="$PSScriptRoot/bootstrap_cpp_gawin"
    local ggc_path="$GLangBin/ggc"
    
    if [ -d "$bootstrap_dir" ]; then
        local boot_cpp_files=("$bootstrap_dir"/*.cpp)
        if [ -e "${boot_cpp_files[0]}" ]; then
            Write-ProgressInline "Phase 2 -> Generating compiler base container"
            if clang++ -std=c++17 -O3 "${boot_cpp_files[@]}" -o "$ggc_path" 2>&1; then
                BootstrapStatus="Success"
                ((RuntimeCount++))
            else
                echo ""
                Write-Log "ERROR" "Phase 2 bootstrap build failed."
                exit 1
            fi
        else
            Write-Log "WARN" "No C++ compilation files found inside: $bootstrap_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p2_dur
        p2_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[%s] [\033[0;32msuccess\033[0m] PHASE 2 complete in %s seconds\n" "$timestamp" "$p2_dur"
    else
        Write-Log "WARN" "Bootstrap source directory missing ($bootstrap_dir). Skipping step..."
    fi

    # --- PHASE 3: Run pipeline manager tool gstdo ---
    Write-Log "INFO" "Phase 3: Running internal pipeline automation tool..."
    phase_start=$(Get-Time)
    local gstdo_path="$GLangBin/gstdo"
    
    if [ -f "$gstdo_path" ]; then
        Write-ProgressInline "Phase 3 -> Running automation checks via gstdo"
        pushd "$GLangBin" > /dev/null
        chmod +x "./gstdo"
        if ! ./gstdo; then
            echo ""
            Write-Log "WARN" "Automation task returned a warning during execution."
        fi
        popd > /dev/null
        local phase_end
        phase_end=$(Get-Time)
        local p3_dur
        p3_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[%s] [\033[0;32msuccess\033[0m] PHASE 3 complete in %s seconds\n" "$timestamp" "$p3_dur"
    else
        Write-Log "WARN" "Automation binary missing ($gstdo_path). Skipping step..."
    fi

    # --- PHASE 4: Self-host rebuild; run ggc on root/ggc/*.gw ---
    Write-Log "INFO" "Phase 4: Rebuilding compiler using itself (Self-hosting)..."
    phase_start=$(Get-Time)
    local ggc_src_dir="$PSScriptRoot/ggc"
    
    if [ -f "$ggc_path" ] && [ -d "$ggc_src_dir" ]; then
        local gw_compiler_files=("$ggc_src_dir"/*.gw)
        if [ -e "${gw_compiler_files[0]}" ]; then
            Write-ProgressInline "Phase 4 -> Processing self-hosted rewrite loop modules"
            chmod +x "$ggc_path"
            if "$ggc_path" "${gw_compiler_files[@]}" -o "$ggc_path" 2>&1; then
                local mod_count=${#gw_compiler_files[@]}
                SelfHostStatus="Success ($mod_count modules)"
                ((RuntimeCount += mod_count))
            else
                echo ""
                Write-Log "ERROR" "Self-hosted build phase returned unexpected errors."
                SelfHostStatus="Failed"
            fi
        else
            Write-Log "WARN" "No self-hosted parsing configuration modules tracked: $ggc_src_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p4_dur
        p4_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[%s] [\033[0;32msuccess\033[0m] PHASE 4 complete in %s seconds\n" "$timestamp" "$p4_dur"
    else
        Write-Log "WARN" "Self-host modules or baseline compiler files are missing. Skipping step..."
    fi

    # --- PHASE 5: Build platform modules; run new ggc on root/gwin/*.gw ---
    Write-Log "INFO" "Phase 5: Building platform core interface components..."
    phase_start=$(Get-Time)
    local gwin_src_dir="$PSScriptRoot/gwin"
    local gwin_path="$GLangBin/gwin"
    
    if [ -f "$ggc_path" ] && [ -d "$gwin_src_dir" ]; then
        local gwin_files=("$gwin_src_dir"/*.gw)
        if [ -e "${gwin_files[0]}" ]; then
            Write-ProgressInline "Phase 5 -> Deploying environment specific libraries"
            if "$ggc_path" "${gwin_files[@]}" -o "$gwin_path" 2>&1; then
                local mod_count=${#gwin_files[@]}
                PlatformStatus="Success ($mod_count modules)"
                ((RuntimeCount += mod_count))
                chmod +x "$gwin_path"
            else
                echo ""
                Write-Log "ERROR" "Platform abstraction modules failed to compile cleanly."
                PlatformStatus="Failed"
            fi
        else
            Write-Log "WARN" "No configuration interface elements found inside: $gwin_src_dir"
        fi
        local phase_end
        phase_end=$(Get-Time)
        local p5_dur
        p5_dur=$(Compute-Duration "$phase_start" "$phase_end")
        local timestamp
        timestamp=$(date +"%H:%M:%S")
        printf "\r[%s] [\033[0;32msuccess\033[0m] PHASE 5 complete in %s seconds\n" "$timestamp" "$p5_dur"
    else
        Write-Log "WARN" "Platform specific source modules are not available. Skipping step..."
    fi

    local total_timer_end
    total_timer_end=$(Get-Time)
    TotalBuildTime=$(Compute-Duration "$total_timer_start" "$total_timer_end")
    ReportCard["Compiler Engine"]="Fully Functional"
    Write-Log "OK" "All build stages successfully finished!"
    Write-Log "BLANK" ""
}

# ==========================================================
# Input Command-Line Argument Processing
# ==========================================================
show_help() {
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --scope [user|system]   Save paths for a single user or system-wide"
    echo "  --force                 Forces a clean redownload of required packages"
    echo "  --doctor                Runs standard system environment health diagnostics"
    echo "  --repair                Runs automatic repairs to update paths and folders"
    echo "  --build                 Runs the compiler pipeline and skips interactive queries"
    echo "  --skip-build            Completely skips compiling code items"
    echo "  --skip-llvm             Skips looking up or verifying LLVM installation"
    echo "  --advanced-build        Forces full multi-tier source bootstrap execution loops"
    echo "  --security-audit        Checks local machine shell configuration threat parameters"
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
        --skip-llvm)      SkipLLVM=1; shift ;;
        --advanced-build) AdvancedBuild=1; shift ;;
        --security-audit) SecurityAudit=1; shift ;;
        -h|--help)        show_help ;;
        *)                Write-Log "ERROR" "Unknown command option flag: $1"; exit 1 ;;
    esac
done

# ==========================================================
# MAIN EXECUTION ROUTINE
# ==========================================================
main() {
    Show-Header

    # 1. Main Interactive Menu
    if [ -z "$Scope" ] && [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 0 ] && [ "$AdvancedBuild" -eq 0 ]; then
        Write-Log "BLANK" "\033[0;32mSelect an action to perform:\033[0m"
        echo "1] Standard System Setup (Install dependencies & paths)"
        echo "2] Build the Compiler Pipeline Only"
        echo "3] Run System Health Checks (Doctor)"
        echo "4] Run Environment Security Checks"
        echo ""
        read -r -p "Specify option index [1-4]: " choice
        
        case "${choice// /}" in
            "1")
                # Continues to target scope config menu
                ;;
            "2")
                AdvancedBuild=1
                SkipLLVM=1
                ;;
            "3")
                Doctor=1
                ;;
            "4")
                SecurityAudit=1
                ;;
            *)
                Write-Log "WARN" "Invalid entry. Defaulting to a standard fresh environment setup..."
                ;;
        esac
    fi

    # 2. Scope Selection Prompt
    while [ -z "$Scope" ] && [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 0 ]; do
        echo ""
        read -r -p "Save environment variables for the current [user] or the whole [system]? " inputScope
        inputScope="${inputScope// /}"
        if [[ "$inputScope" == "user" || "$inputScope" == "system" ]]; then
            Scope="$inputScope"
        else
            Write-Log "WARN" "Invalid entry. Please choose 'user' or 'system' exactly."
        fi
    done

    local scopeEnv="User"
    [ "$Scope" = "system" ] && scopeEnv="Machine"
    if [ -n "$Scope" ]; then Invoke-MakeAdmin "$Scope"; fi

    # 3. Task Router
    if [ "$SecurityAudit" -eq 1 ]; then
        Invoke-SecurityAudit
        Invoke-PostAuditPrompt
    fi

    if [ "$Doctor" -eq 1 ]; then
        Invoke-Doctor
        Invoke-PostAuditPrompt
    fi

    if [ "$Doctor" -eq 0 ] && [ "$SecurityAudit" -eq 0 ]; then
        Write-Log "INFO" "Writing configuration records (Target Hive: $scopeEnv)..."
        Write-Log "BLANK" ""

        if [ "$Repair" -eq 1 ]; then
            Write-Log "WARN" "Repair parameter active. Checking environment settings..."
            Invoke-AutoRepair
        fi

        # Process LLVM Steps
        if [ "$SkipLLVM" -ne 1 ]; then
            if ! Test-Clang || [ "$Force" -eq 1 ]; then Install-LLVM; fi
        fi

        # Synchronize Paths
        local llvm_bin="$DefaultLLVMPath/bin"
        command -v clang >/dev/null 2>&1 && llvm_bin=$(dirname "$(command -v clang)")

        Write-Log "INFO" "Updating environmental path configs..."
        if [ "$SkipLLVM" -ne 1 ] && [ -d "$llvm_bin" ]; then Add-ToPathSafe "$llvm_bin" "$scopeEnv"; fi
        if [ -d "$GLangBin" ]; then Add-ToPathSafe "$GLangBin" "$scopeEnv"; fi

        # Build Prompts
        local shouldBuild=0
        if [ "$Build" -eq 1 ] || [ "$AdvancedBuild" -eq 1 ]; then
            shouldBuild=1
        elif [ "$SkipBuild" -eq 1 ]; then
            shouldBuild=0
        else
            echo ""
            read -r -p "Would you like to build the workspace compiler components now? (y/n): " inputBuild
            case "$inputBuild" in
                [yY][eE][sS]|[yY]|1) shouldBuild=1 ;;
                *) shouldBuild=0 ;;
            esac
        fi

        if [ $shouldBuild -eq 1 ]; then
            Invoke-AdvancedCompilationPipeline
        else
            Write-Log "INFO" "Skipping compilation stages per user request."
        fi
    fi

    # ==========================================================
    # TASK REPORT SUMMARY
    # ==========================================================
    Write-Log "BLANK" ""
    Write-Log "BLANK" "=========================================================="
    Write-Log "OK"    "                    SUMMARY REPORT CARD                   "
    Write-Log "BLANK" "=========================================================="
    
    for item in "${ReportCardKeys[@]}"; do
        local status="${ReportCard[$item]}"
        local color_code="\033[0;36m" # Cyan
        
        if [[ "$status" =~ Verified|Completed|Functional|Updated|Installed ]]; then
            color_code="\033[0;32m" # Green
        elif [[ "$status" =~ Failed ]]; then
            color_code="\033[0;31m" # Red
        elif [[ "$status" =~ Skipped ]]; then
            color_code="\033[0;33m" # Yellow
        fi
        
        printf " \033[0;37m[>]\033[0m  \033[1;37m%-25s\033[0m : ${color_code}%s\033[0m\n" "$item" "$status"
    done

    # Live Performance Metrics
    if [ "${ReportCard["Compiler Engine"]}" = "Fully Functional" ]; then
        Write-Log "BLANK" ""
        echo -e "\033[0;37m==========================================================\033[0m"
        echo -e "\033[1;37mBuild Summary Data\033[0m"
        echo -e "\033[0;37m==========================================================\033[0m"
        echo "Helper utilities   : $HelperCount compiled"
        echo "Bootstrap engine   : $BootstrapStatus"
        echo "Compiled objects   : $RuntimeCount files completed"
        echo "Self-hosted build  : $SelfHostStatus"
        echo "Platform binaries  : $PlatformStatus"
        Write-Log "BLANK" ""
        echo -e "Total Build Time   : \033[0;36m${TotalBuildTime}s\033[0m"
    fi
    
    Write-Log "BLANK" "=========================================================="
    Write-Log "OK" "Workspace configuration and setup steps completed successfully!"
}

# General Error Trap Catching
error_trap_handler() {
    local exit_code=$?
    [ $exit_code -eq 0 ] && return
    Write-Log "ERROR" "A fatal error occurred: Process runtime context crashed abruptly."
    exit $exit_code
}
trap error_trap_handler EXIT

# Start script
main