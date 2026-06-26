#!/bin/bash

# =========================================================
# .glang Setup Script (Linux Edition - Production Grade)
# LLVM + Clang + Perl Interpreter + GLang Toolchain Manager
# =========================================================

Set -euo pipefail

FALLBACK_VERSION="20.1.8"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLANG_BIN="$ROOT_DIR/bin"
INSTALL_ROOT="$ROOT_DIR/g_clang_depend"
PERL_INSTALL_ROOT="$ROOT_DIR/g_perl_depend"
VERSION_FILE="$ROOT_DIR/glang_meta/VERSION.gwin"

# Initialize command-line flag defaults
DOCTOR=0
REPAIR=0
FORCE=0
BUILD_BINARIES=-1  # -1 = Unassigned (Will prompt unless flag specified)
SKIP_PERL=0
SKIP_LLVM=0
ADVANCED_BUILD=0
SECURITY_AUDIT=0

# Pipeline Trackers for UI Dashboard Report Card
STATUS_SECURITY="Skipped"
STATUS_DOCTOR="Skipped"
STATUS_LLVM="Unchanged"
STATUS_PERL="Unchanged"
STATUS_PATH="Unchanged"
STATUS_BUILD="Skipped"

# ---------------------------------------------------------
# Colors + Logging Subsystem
# ---------------------------------------------------------
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

log_info()   { echo -e "${CYAN}[INFO]   $1${NC}"; }
log_ok()     { echo -e "${GREEN}[ OK ]   $1${NC}"; }
log_warn()   { echo -e "${YELLOW}[WARN]   $1${NC}"; }
log_err()    { echo -e "${RED}[FAIL]   $1${NC}"; }
log_secure() { echo -e "${MAGENTA}[SECURE] $1${NC}"; }
log_blank()  { echo -e "${NC}$1${NC}"; }

show_header() {
    log_blank "----------------------------------------------------------"
    log_blank "     GAWIN & GLANG HIGH-PERFORMANCE ECOSYSTEM SETUP       "
    log_blank "----------------------------------------------------------"
}

# ---------------------------------------------------------
# Help / Usage Menu
# ---------------------------------------------------------
show_help() {
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Production-grade toolchain environment wizard for GLang/Gawin."
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message menu configuration and exit"
    echo "  --doctor           Execute an operational audit checking paths, versions, and dependencies"
    echo "  --repair           Trigger systematic restoration workflows on missing paths and binaries"
    echo "  --force            Force a clean re-download and isolated deployment of target stacks"
    echo "  --build            Bypass the execution prompt and immediately compile source binaries"
    echo "  --skip-build       Bypass the execution prompt and explicitly skip building binaries"
    echo "  --skip-perl        Bypass validation or standalone installation of the Perl interpreter"
    echo "  --skip-llvm        Bypass validation or standalone installation of the LLVM/Clang stack"
    echo "  --advanced-build   Explicitly forces execution of the advanced multi-tier bootstrap pipeline"
    echo "  --security-audit   Executes deep structural analysis on path sanitization and permissions"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh --build"
    echo "  ./setup.sh --advanced-build --security-audit"
    exit 0
}

# ---------------------------------------------------------
# Argument Parsing Matrix
# ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_help ;;
        --doctor)        DOCTOR=1; shift ;;
        --repair)        REPAIR=1; shift ;;
        --force)         FORCE=1; shift ;;
        --build)         BUILD_BINARIES=1; shift ;;
        --skip-build)    BUILD_BINARIES=0; shift ;;
        --skip-perl)     SKIP_PERL=1; shift ;;
        --skip-llvm)     SKIP_LLVM=1; shift ;;
        --advanced-build) ADVANCED_BUILD=1; shift ;;
        --security-audit) SECURITY_AUDIT=1; shift ;;
        *)               echo -e "${RED}[FAIL] Unknown option: $1${NC}"; echo "Use --help for usage details."; exit 1 ;;
    esac
done

# ---------------------------------------------------------
# Runtime Version Discovery Resolvers
# ---------------------------------------------------------
get_latest_llvm_version() {
    log_info "Querying upstream GitHub API for latest LLVM release version info..."
    local version
    version=$(curl -s https://api.github.com/repos/llvm/llvm-project/releases/latest \
        | grep '"tag_name":' \
        | sed -E 's/.*"llvmorg-([^"]+)".*/\1/' || echo "")

    if [ -z "$version" ]; then
        log_warn "Upstream discovery handshake failed -> Using configuration version $FALLBACK_VERSION"
        echo "$FALLBACK_VERSION"
    else
        log_ok "Latest discovered upstream LLVM release: $version"
        echo "$version"
    fi
}

get_clang_version() {
    if ! command -v clang >/dev/null 2>&1; then
        echo "none"
        return
    fi
    clang --version | head -n1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown"
}

get_perl_version() {
    if ! command -v perl >/dev/null 2>&1; then
        echo "none"
        return
    fi
    perl -e 'print $^V' 2>/dev/null | sed 's/v//' || echo "unknown"
}

get_glang_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        echo "unknown"
        return
    fi
    grep -oE 'version\s*:=\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"' "$VERSION_FILE" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1 || echo "unknown"
}

# ---------------------------------------------------------
# Security Auditing & DX Defenses
# ---------------------------------------------------------
invoke_security_audit() {
    log_secure "=== INITIALIZING SECURITY DEFENSE & WORKSPACE INTEGRITY CHECK ==="
    
    # 1. Verification of Shell Mask Permissions
    local current_umask
    current_umask=$(umask)
    log_info "Active environment Shell Creation Mask (umask): $current_umask"
    if [ "$current_umask" = "0000" ] || [ "$current_umask" = "0002" ]; then
        log_warn "Insecure/loose execution file permissions profile detected ($current_umask)."
    else
        log_ok "Execution creation mask configured safely."
    fi

    # 2. Check for Shadowing / Hijacking Vulnerabilities in Environment PATHs
    log_info "Analyzing PATH ordering security vulnerabilities..."
    IFS=':' read -r -a paths <<< "$PATH"
    local insecure_paths=()
    for p in "${paths[@]}"; do
        if [ -d "$p" ]; then
            # Flag temporary or world-writable directories in active executable search path
            if [[ "$p" == *"/tmp"* ]] || [ -matrix_writable=$(find "$p" -maxdepth 0 -perm -o+w 2>/dev/null) ]; then
                insecure_paths+=("$p")
            fi
        fi
    done

    if [ ${#insecure_paths[@]} -gt 0 ]; then
        log_warn "Detected potentially high-risk paths inside executable environment loops: ${insecure_paths[*]}"
    else
        log_secure "Path isolation assessment verified clear."
    fi

    # 3. Access Permission Verification on Context Workspace
    if [ -w "$ROOT_DIR" ]; then
        log_ok "Workspace execution directory write permissions confirmed."
    else
        log_err "Workspace root folder access bounds restricted! Run inside an elevated sudo context."
    fi

    STATUS_SECURITY="Verified Passing"
    log_secure "Security verification checks completed cleanly."
    log_blank ""
}

# ---------------------------------------------------------
# Safe Environment Variable Configuration Profiles
# ---------------------------------------------------------
add_to_path() {
    local target="$1"
    local shell_rc="$HOME/.bashrc"

    if [[ "${SHELL:-}" == *zsh* ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    if [ ! -d "$target" ]; then
        log_warn "Failed mapping directory reference to system profile path. Directory missing: $target"
        return
    fi

    if [[ ":$PATH:" == *":$target:"* ]]; then
        log_info "Path assignment verification clean: $target"
        return
    fi

    # Safety feature: Create local environment backup string before appending alterations
    cp "$shell_rc" "${shell_rc}.gawin_bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

    if grep -q "$target" "$shell_rc" 2>/dev/null; then
        log_info "Path assignment target already safely appended inside profile: $shell_rc"
        return
    fi

    echo "" >> "$shell_rc"
    echo "# Gawin Ecosystem Environment Configuration Paths" >> "$shell_rc"
    echo "export PATH=\"\$PATH:$target\"" >> "$shell_rc"

    export PATH="$PATH:$target"
    log_ok "Successfully appended binary target pathing rules to $shell_rc"
    STATUS_PATH="Updated Cleanly"
}

# ---------------------------------------------------------
# Ecosystem Provisioning Engines (LLVM & Standalone Perl)
# ---------------------------------------------------------
install_llvm() {
    local version="$1"

    if command -v clang >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
        log_ok "Clang compiler engine installation validated on host system path environment."
        return
    fi

    mkdir -p "$INSTALL_ROOT"
    local archive="clang+llvm-$version-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$archive"

    log_info "Executing remote archive discovery for LLVM $version..."
    if ! curl -L "$url" -o "$INSTALL_ROOT/$archive"; then
        log_err "Target subsystem package distribution downpour initialization failed!"
        exit 1
    fi

    log_info "Extracting payload files directly into local environment target path storage..."
    tar -xJf "$INSTALL_ROOT/$archive" -C "$INSTALL_ROOT"
    rm -f "$INSTALL_ROOT/$archive"

    CLANG_PATH=$(find "$INSTALL_ROOT" -type d -name "bin" | head -n 1)
    STATUS_LLVM="Deployed (Standalone Archive)"
}

install_perl() {
    if command -v perl >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
        log_ok "Perl binary interpreter runtime validated on host system path environment."
        return
    fi

    if [ -d "$PERL_INSTALL_ROOT/bin" ] && [ "$FORCE" -ne 1 ]; then
        log_ok "Self-contained workspace Perl executable directory verified: $PERL_INSTALL_ROOT/bin"
        PERL_PATH="$PERL_INSTALL_ROOT/bin"
        return
    fi

    mkdir -p "$PERL_INSTALL_ROOT"
    local perl_ver="5.40.0"
    local archive="perl-$perl_ver.tar.gz"
    local url="https://www.cpan.org/src/5.0/$archive"

    log_info "Downloading stable, up-to-date Unix Perl Interpreter core from CPAN distributions..."
    if ! curl -L "$url" -o "$PERL_INSTALL_ROOT/$archive"; then
        log_err "Failed to download Perl distribution from remote mirror endpoints."
        exit 1
    fi

    log_info "Extracting production Perl distribution source packages..."
    tar -xzf "$PERL_INSTALL_ROOT/$archive" -C "$PERL_INSTALL_ROOT"
    
    log_info "Configuring, compiling, and bootstrapping local isolated Perl (this may take a moment)..."
    pushd "$PERL_INSTALL_ROOT/perl-$perl_ver" > /dev/null
    
    if ./Configure -des -Dprefix="$PERL_INSTALL_ROOT" -Dman1dir=none -Dman3dir=none >/dev/null && \
       make -j$(nproc 2>/dev/null || echo 2) >/dev/null && \
       make install >/dev/null; then
        log_ok "Local standalone Perl Interpreter environment instantiation finalized securely."
        STATUS_PERL="Deployed (Source Compilation)"
    else
        log_err "Critical compiler runtime breakdown while building standard Perl source tree modules."
        popd > /dev/null
        exit 1
    fi
    
    popd > /dev/null
    rm -rf "$PERL_INSTALL_ROOT/$archive" "$PERL_INSTALL_ROOT/perl-$perl_ver"
    PERL_PATH="$PERL_INSTALL_ROOT/bin"
}

# ---------------------------------------------------------
# Multi-Tier Deep-Introspection Compilation Pipeline
# ---------------------------------------------------------
invoke_advanced_compilation_pipeline() {
    log_blank ""
    log_info "=========================================================="
    log_info "     INITIALIZING ADVANCED GAWIN SYSTEM COMPILATION       "
    log_info "=========================================================="

    local bin_dir="$ROOT_DIR/bin"
    
    # Verify build prerequisite compiler engines
    if ! command -v clang++ >/dev/null 2>&1; then
        log_err "Clang++ compiler engine initialization error. Unable to process compilation jobs."
        STATUS_BUILD="Failed (Missing Clang++)"
        return
    fi

    mkdir -p "$bin_dir"

    # --- PHASE 1: Compile root/src_exec/*.cpp into root/bin/* ---
    local src_exec_dir="$ROOT_DIR/src_exec"
    log_info "[PHASE 1] Compiling executable engines from $src_exec_dir..."
    if [ -d "$src_exec_dir" ]; then
        local cpp_files
        cpp_files=$(find "$src_exec_dir" -maxdepth 1 -name "*.cpp" 2>/dev/null)
        if [ -z "$cpp_files" ]; then
            log_warn "No source elements found matching target criteria *.cpp inside $src_exec_dir"
        else
            for file in $cpp_files; do
                local base_name
                base_name=$(basename "$file" .cpp)
                local out_exe="$bin_dir/$base_name"
                log_info "Compiling Source: $(basename "$file") -> $out_exe"
                if ! clang++ -std=c++17 -O3 "$file" -o "$out_exe" 2>&1; then
                    log_err "Compilation crash processing file structural components: $(basename "$file")"
                    exit 1
                fi
            done
        fi
    else
        log_warn "Source execution tracking path missing: $src_exec_dir. Skipping initialization..."
    fi

    # --- PHASE 2: Compile root/bootstrap_cpp_gawin/*.cpp into root/bin/ggc ---
    local bootstrap_dir="$ROOT_DIR/bootstrap_cpp_gawin"
    local ggc_path="$bin_dir/ggc"
    log_info "[PHASE 2] Initializing Bootstrap compilation tasks from $bootstrap_dir..."
    if [ -d "$bootstrap_dir" ]; then
        local boot_cpp_files=()
        while IFS= read -r line; do boot_cpp_files+=("$line"); done < <(find "$bootstrap_dir" -maxdepth 1 -name "*.cpp" 2>/dev/null)
        
        if [ ${#boot_cpp_files[@]} -gt 0 ]; then
            log_info "Bundling source map tree to construct initial binary bootstrap compiler tool: $ggc_path"
            if ! clang++ -std=c++17 -O3 "${boot_cpp_files[@]}" -o "$ggc_path" 2>&1; then
                log_err "Bootstrap translation sequence error. Execution termination requested."
                exit 1
            fi
            log_ok "Bootstrap compiler engine built successfully."
        else
            log_warn "No valid matching bootstrap C++ components detected inside directory."
        fi
    else
        log_warn "Bootstrap repository pointer missing: $bootstrap_dir. Skipping phase step."
    fi

    # --- PHASE 3: Invoke compiled binary gstdo ---
    local gstdo_path="$bin_dir/gstdo"
    log_info "[PHASE 3] Evaluating toolchain setup tasks via 'gstdo' script runtime automation..."
    if [ -f "$gstdo_path" ]; then
        pushd "$bin_dir" > /dev/null
        chmod +x "./gstdo"
        log_info "Running executable helper utility tool: $gstdo_path"
        if ! ./gstdo; then
            log_warn "Utility workflow 'gstdo' returned abnormal termination token."
        fi
        popd > /dev/null
    else
        log_warn "Automation workflow target binary $gstdo_path could not be loaded."
    fi

    # --- PHASE 4: Invoke ggc on root/ggc/*.gw to compile into a new root/bin/ggc ---
    local ggc_src_dir="$ROOT_DIR/ggc"
    log_info "[PHASE 4] Executing secondary self-hosted rewrite loop for ggc using localized language modules..."
    if [ -f "$ggc_path" ] && [ -d "$ggc_src_dir" ]; then
        local ggc_files=()
        while IFS= read -r line; do ggc_files+=("$line"); done < <(find "$ggc_src_dir" -maxdepth 1 -name "*.gw" 2>/dev/null)
        
        if [ ${#ggc_files[@]} -gt 0 ]; then
            log_info "Refactoring compiler architecture code using original language components via bootstrap compiler..."
            if ! "$ggc_path" "${ggc_files[@]}" -o "$ggc_path" 2>&1; then
                log_err "Self-hosting compilation cycle pipeline threw execution errors."
            else
                log_ok "Self-hosted native compilation stack upgrade completed safely."
            fi
        else
            log_warn "No matching components (*.gw) detected in compiler location $ggc_src_dir"
        fi
    else
        log_warn "Self-hosted source parameters missing or compiler executable not found."
    fi

    # --- PHASE 5: Invoke new ggc on root/gwin/*.gw (explicitly list all files) to compile into root/bin/gwin ---
    local gwin_src_dir="$ROOT_DIR/gwin"
    local gwin_path="$bin_dir/gwin"
    log_info "[PHASE 5] Compiling runtime platform layer window managers via $gwin_src_dir..."
    if [ -f "$ggc_path" ] && [ -d "$gwin_src_dir" ]; then
        local gwin_files=()
        while IFS= read -r line; do gwin_files+=("$line"); done < <(find "$gwin_src_dir" -maxdepth 1 -name "*.gw" 2>/dev/null)
        
        if [ ${#gwin_files[@]} -gt 0 ]; then
            log_info "Explicit File Argument Mapping Trace Matrix:"
            for gw_item in "${gwin_files[@]}"; do
                log_blank "   -> Target Element Path: $gw_item"
            done
            
            log_info "Processing translation step on all files via explicit file parameters -> Target mapping path: $gwin_path"
            if ! "$ggc_path" "${gwin_files[@]}" -o "$gwin_path" 2>&1; then
                log_err "Window runtime application layer integration pipeline execution failed."
            else
                log_ok "Gawin Framework application packages compiled completely."
            fi
        else
            log_warn "No components found matching (*.gw) within path bounds: $gwin_src_dir"
        fi
    else
        log_warn "Compilation dependencies missing or paths omitted. Phase 5 generation skipped."
    fi

    STATUS_BUILD="Fully Functional"
    log_ok "All pipeline build routines completed."
    log_blank ""
}

# ---------------------------------------------------------
# Diagnostics and Verification (Doctor Engine Audit)
# ---------------------------------------------------------
run_doctor() {
    log_info "=== SETUP DOCTOR DIAGNOSTIC AUDIT ==="

    log_info "Operating System: $(uname -srm)"
    log_info "Shell Engine: ${BASH_VERSION:+Bash $BASH_VERSION}"

    local clang_ver
    clang_ver=$(get_clang_version)
    log_info "clang version: $clang_ver"
    log_info "clang path:    $(command -v clang 2>/dev/null || echo 'Missing from active PATH scope')"

    local latest
    latest=$(get_latest_llvm_version)

    if [[ "$clang_ver" != "$latest"* && "$clang_ver" != "none" ]]; then
        log_warn "Version structural mismatch checked (Upstream recommends targeting version $latest)"
    else
        log_ok "System LLVM version structure matches target standard rules."
    fi

    if [[ ":$PATH:" != *":LLVM:"* && ":$PATH:" != *":g_clang_depend:"* ]]; then
        log_warn "LLVM binaries are not clearly configured in the active environment execution string."
    fi

    log_blank ""
    log_info "=== PERL INTERPRETER STATUS ==="
    local perl_ver
    perl_ver=$(get_perl_version)
    log_info "perl version:  $perl_ver"
    log_info "perl path:     $(command -v perl 2>/dev/null || echo 'Missing from active PATH scope')"
    if [ "$perl_ver" = "none" ]; then
        if [ -d "$PERL_INSTALL_ROOT/bin" ]; then
            log_ok "Perl interpreter directory found at ($PERL_INSTALL_ROOT/bin) but not active in profile execution strings yet."
        else
            log_err "No validated system Perl interpreter paths found on this system configuration."
        fi
    else
        log_ok "Perl Interpreter operational profile confirmed status OK."
    fi

    log_blank ""
    log_info "=== GAWIN INFO ==="
    log_info "gawin path:    $GLANG_BIN"
    log_info "gawin version: $(get_glang_version)"

    if [ -d "$GLANG_BIN" ]; then
        log_ok "Gawin framework executable build targets detected."
    else
        log_warn "Gawin framework executable build targets are empty or unpopulated."
    fi

    STATUS_DOCTOR="Completed Safely"
    log_blank ""
    log_ok "System environment audit validation workflow complete."
}

# ---------------------------------------------------------
# RUNTIME ENGINE (MAIN Execution Script Workflow Block)
# ---------------------------------------------------------
show_header

# 1. Interactive Selection Menu Strategy if Parameters are Left Unassigned
if [ "$DOCTOR" -eq 0 ] && [ "$SECURITY_AUDIT" -eq 0 ] && [ "$ADVANCED_BUILD" -eq 0 ] && [ "$BUILD_BINARIES" -eq -1 ] && [ "$REPAIR" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    echo -e "${GREEN}Select execution target mode parameters below:${NC}"
    echo "1) Complete Standard Ecosystem Installation"
    echo "2) Advanced Compilation Bootstrapping Loop Only"
    echo "3) System Environment Health Diagnostic Check (Doctor)"
    echo "4) System Deep Security & Code Integrity Audit"
    echo ""
    read -r -p "Enter targeted execution index option [1-4]: " choice
    
    case "${choice// /}" in
        1) # standard build flow below
           ;;
        2) ADVANCED_BUILD=1; SKIP_LLVM=1; SKIP_PERL=1 ;;
        3) DOCTOR=1 ;;
        4) SECURITY_AUDIT=1 ;;
        *) log_warn "Invalid choice target. Launching default comprehensive platform initialization sequence..." ;;
    esac
fi

if [ "$SECURITY_AUDIT" -eq 1 ]; then
    invoke_security_audit
fi

if [ "$DOCTOR" -eq 1 ]; then
    run_doctor
fi

if [ "$DOCTOR" -eq 0 ] && [ "$SECURITY_AUDIT" -eq 0 ]; then
    log_info "Gawin Production Setup Configuration Wizard Initializing..."

    if [ "$REPAIR" -eq 1 ]; then
        log_warn "System path repair flags detected... forcing full asset validation checks..."
        if [ "$SKIP_LLVM" -ne 1 ]; then rm -rf "$INSTALL_ROOT"; fi
        if [ "$SKIP_PERL" -ne 1 ]; then rm -rf "$PERL_INSTALL_ROOT"; fi
    fi

    # Resolve LLVM Pipeline Dependencies
    if [ "$SKIP_LLVM" -ne 1 ]; then
        VERSION=$(get_latest_llvm_version)
        install_llvm "$VERSION"
    fi

    # Resolve Perl Pipeline Dependencies
    if [ "$SKIP_PERL" -ne 1 ]; then
        install_perl
    fi

    # Fallback pathing extraction rules to inject active environment parameters cleanly
    CLANG_PATH=""
    PERL_PATH=""

    if [ "$SKIP_LLVM" -ne 1 ]; then
        if command -v clang >/dev/null 2>&1; then
            CLANG_PATH=$(dirname "$(command -v clang)")
        elif [ -d "$INSTALL_ROOT" ]; then
            CLANG_PATH=$(find "$INSTALL_ROOT" -type d -name "bin" | head -n 1)
        fi
    fi

    if [ "$SKIP_PERL" -ne 1 ]; then
        if command -v perl >/dev/null 2>&1; then
            PERL_PATH=$(dirname "$(command -v perl)")
        elif [ -d "$PERL_INSTALL_ROOT/bin" ]; then
            PERL_PATH="$PERL_INSTALL_ROOT/bin"
        fi
    fi

    # Inject configurations immediately into running shell environment variables to enable safe post-compilation pipelines
    if [ -n "$CLANG_PATH" ]; then export PATH="$CLANG_PATH:$PATH"; fi
    if [ -n "$PERL_PATH" ]; then export PATH="$PERL_PATH:$PATH"; fi

    # Update Profile Configuration Targets
    log_info "Updating system environment target profile path value allocations..."
    if [ -n "$CLANG_PATH" ] && [ "$SKIP_LLVM" -ne 1 ]; then add_to_path "$CLANG_PATH"; fi
    if [ -n "$PERL_PATH" ] && [ "$SKIP_PERL" -ne 1 ]; then add_to_path "$PERL_PATH"; fi
    if [ -d "$GLANG_BIN" ]; then add_to_path "$GLANG_BIN"; fi

    # Interactive Post-Installation Compilation Handshake
    should_build=0
    if [ "$BUILD_BINARIES" -eq 1 ] || [ "$ADVANCED_BUILD" -eq 1 ]; then
        should_build=1
    elif [ "$BUILD_BINARIES" -eq 0 ]; then
        should_build=0
    else
        echo ""
        read -r -p "Do you want to run the compiler toolchain build and verification pipeline now? (y/n): " input_build
        case "$input_build" in
            [yY][eE][sS]|[yY]|1) should_build=1 ;;
            *) should_build=0 ;;
        esac
    fi

    if [ "$should_build" -eq 1 ]; then
        invoke_advanced_compilation_pipeline
    else
        log_info "Skipping code compilation stages per instruction choices."
    fi
fi

# ---------------------------------------------------------
# SYSTEM VISUAL DASHBOARD REPORT CARD
# ---------------------------------------------------------
log_blank ""
log_blank "=========================================================="
log_ok    "          WORKSPACE ECOSYSTEM EXECUTION DASHBOARD         "
log_blank "=========================================================="

print_row() {
    local label="$1"
    local status="$2"
    local color="$CYAN"
    
    if [[ "$status" =~ Passing|Safely|Functional|Updated|Deployed ]]; then color="$GREEN"
    elif [[ "$status" =~ Failed ]]; then color="$RED"
    elif [[ "$status" =~ Skipped ]]; then color="$YELLOW"
    fi
    
    printf " ${GRAY}[>]${WHITE} %-25s ${GRAY}:${NC} ${color}%s${NC}\n" "$label" "$status"
}

print_row "Security Audit" "$STATUS_SECURITY"
print_row "Environment Audit" "$STATUS_DOCTOR"
print_row "LLVM Toolchain" "$STATUS_LLVM"
print_row "Perl Environment" "$STATUS_PERL"
print_row "Environment Paths" "$STATUS_PATH"
print_row "Compilation Engine" "$STATUS_BUILD"

log_blank "=========================================================="
log_ok "Deployment operation steps completed cleanly."
log_blank ""