#!/bin/bash
# ============================================================
# ComfyUI Vast.ai — Runtime Workflow Selector
# 
# This script runs on instance boot. It presents a menu of
# workflow profiles, each of which corresponds to a Prompting
# Pixels-generated provisioning script plus pre-loaded workflow
# JSON files. Only selected profiles' models get downloaded.
#
# Usage:
#   - As on-start script in Vast.ai template
#   - Or manually via SSH: /workspace/selector.sh
#
# Environment variables (set in Vast.ai template):
#   HF_TOKEN        - HuggingFace read token (for fast hf_xet downloads)
#   CIVITAI_TOKEN   - CivitAI API token
#   AUTO_PROFILE    - (optional) skip menu, auto-select profile(s)
#                     comma-separated, e.g. "sdxl,flux"
#   REPO_URL        - (optional) your GitHub repo URL to clone fresh
# ============================================================

set -e

WORKSPACE="/workspace"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
REPO_DIR="$WORKSPACE/comfyui-setup"

# --- Colors for terminal output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "============================================================"
echo "  ComfyUI Vast.ai — Workflow Selector"
echo "============================================================"
echo -e "${NC}"

# --- Clone or update your setup repo ---
if [ -n "$REPO_URL" ]; then
    if [ -d "$REPO_DIR" ]; then
        echo -e "${YELLOW}[setup] Updating setup repo...${NC}"
        cd "$REPO_DIR" && git pull --ff-only 2>/dev/null || true
    else
        echo -e "${YELLOW}[setup] Cloning setup repo: $REPO_URL${NC}"
        git clone "$REPO_URL" "$REPO_DIR"
    fi
else
    # If no repo URL, expect files are already in place (baked into image)
    if [ ! -d "$REPO_DIR/profiles" ]; then
        echo -e "${RED}[error] No REPO_URL set and no profiles found at $REPO_DIR/profiles${NC}"
        echo -e "${RED}        Set REPO_URL in your Vast.ai template env vars.${NC}"
        echo -e "${RED}        Or place your profile scripts in $REPO_DIR/profiles/${NC}"
        exit 1
    fi
fi

# --- Export tokens for downstream scripts ---
export HF_TOKEN="${HF_TOKEN:-}"
export CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"

if [ -z "$HF_TOKEN" ]; then
    echo -e "${YELLOW}[warn] HF_TOKEN not set. HuggingFace downloads may be slow or fail.${NC}"
fi
if [ -z "$CIVITAI_TOKEN" ]; then
    echo -e "${YELLOW}[warn] CIVITAI_TOKEN not set. CivitAI gated models won't download.${NC}"
fi

# --- Install hf_xet for fast downloads if not present ---
if ! pip show hf_xet &>/dev/null; then
    echo -e "${YELLOW}[setup] Installing hf_xet for accelerated HuggingFace downloads...${NC}"
    pip install "huggingface_hub[hf_xet]" "huggingface_hub[cli]" --break-system-packages -q 2>/dev/null || \
    pip install "huggingface_hub[hf_xet]" "huggingface_hub[cli]" -q 2>/dev/null || true
fi

# --- Log in to HuggingFace if token is available ---
if [ -n "$HF_TOKEN" ]; then
    huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential 2>/dev/null || true
fi

# --- Discover available profiles ---
PROFILE_DIR="$REPO_DIR/profiles"
WORKFLOW_DIR="$REPO_DIR/workflows"

if [ ! -d "$PROFILE_DIR" ]; then
    echo -e "${RED}[error] No profiles directory found at $PROFILE_DIR${NC}"
    exit 1
fi

# Build array of available profiles
declare -A PROFILES
declare -A PROFILE_DESCRIPTIONS
i=1

for script in "$PROFILE_DIR"/*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script" .sh)
    
    # Try to read description from first comment line of the script
    desc=$(head -5 "$script" | grep "^# DESC:" | sed 's/^# DESC: //' | head -1)
    [ -z "$desc" ] && desc="$name"
    
    PROFILES[$i]="$name"
    PROFILE_DESCRIPTIONS[$i]="$desc"
    i=$((i + 1))
done

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo -e "${RED}[error] No profile scripts found in $PROFILE_DIR/${NC}"
    echo -e "${RED}        Add .sh files generated from Prompting Pixels.${NC}"
    exit 1
fi

# --- Profile Selection ---
SELECTED_PROFILES=()

if [ -n "$AUTO_PROFILE" ]; then
    # Auto-select from env var (comma-separated profile names)
    echo -e "${GREEN}[auto] AUTO_PROFILE set: $AUTO_PROFILE${NC}"
    IFS=',' read -ra AUTO_LIST <<< "$AUTO_PROFILE"
    for auto_name in "${AUTO_LIST[@]}"; do
        auto_name=$(echo "$auto_name" | xargs)  # trim whitespace
        if [ -f "$PROFILE_DIR/${auto_name}.sh" ]; then
            SELECTED_PROFILES+=("$auto_name")
            echo -e "${GREEN}  ✓ $auto_name${NC}"
        else
            echo -e "${YELLOW}  ✗ '$auto_name' not found, skipping${NC}"
        fi
    done
else
    # Interactive menu
    echo -e "${CYAN}Available workflow profiles:${NC}"
    echo ""
    for key in $(echo "${!PROFILES[@]}" | tr ' ' '\n' | sort -n); do
        echo -e "  ${GREEN}[$key]${NC} ${PROFILES[$key]} — ${PROFILE_DESCRIPTIONS[$key]}"
    done
    echo ""
    echo -e "  ${GREEN}[a]${NC} All profiles"
    echo -e "  ${GREEN}[0]${NC} None (just start ComfyUI with existing models)"
    echo ""
    echo -e "${CYAN}Enter your choice (comma-separated for multiple, e.g. 1,3):${NC}"
    
    # Wait for input with a timeout for non-interactive sessions
    read -t 120 -p "> " CHOICE || CHOICE="0"
    
    if [ "$CHOICE" = "a" ] || [ "$CHOICE" = "A" ]; then
        for key in $(echo "${!PROFILES[@]}" | tr ' ' '\n' | sort -n); do
            SELECTED_PROFILES+=("${PROFILES[$key]}")
        done
    elif [ "$CHOICE" != "0" ]; then
        IFS=',' read -ra CHOICES <<< "$CHOICE"
        for c in "${CHOICES[@]}"; do
            c=$(echo "$c" | xargs)  # trim
            if [ -n "${PROFILES[$c]}" ]; then
                SELECTED_PROFILES+=("${PROFILES[$c]}")
            else
                echo -e "${YELLOW}  Invalid choice: $c${NC}"
            fi
        done
    fi
fi

# --- Run selected profile scripts ---
if [ ${#SELECTED_PROFILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}[info] No profiles selected. Skipping model downloads.${NC}"
else
    echo ""
    echo -e "${CYAN}Selected profiles: ${SELECTED_PROFILES[*]}${NC}"
    echo ""
    
    for profile in "${SELECTED_PROFILES[@]}"; do
        script="$PROFILE_DIR/${profile}.sh"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  Running profile: $profile${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        chmod +x "$script"
        bash "$script"
        
        echo -e "${GREEN}  ✓ Profile '$profile' complete.${NC}"
        echo ""
    done
fi

# --- Copy workflow JSON files for selected profiles ---
if [ -d "$WORKFLOW_DIR" ]; then
    # Ensure ComfyUI user workflows directory exists
    COMFY_WORKFLOWS="$COMFYUI_DIR/user/default/workflows"
    mkdir -p "$COMFY_WORKFLOWS"
    
    for profile in "${SELECTED_PROFILES[@]}"; do
        if [ -d "$WORKFLOW_DIR/$profile" ]; then
            echo -e "${YELLOW}[workflows] Copying workflows for: $profile${NC}"
            cp -v "$WORKFLOW_DIR/$profile/"*.json "$COMFY_WORKFLOWS/" 2>/dev/null || true
        fi
    done
    
    # Also copy any shared/common workflows
    if [ -d "$WORKFLOW_DIR/common" ]; then
        echo -e "${YELLOW}[workflows] Copying common workflows${NC}"
        cp -v "$WORKFLOW_DIR/common/"*.json "$COMFY_WORKFLOWS/" 2>/dev/null || true
    fi
fi

# --- Install server-side download nodes (always, for ad-hoc use) ---
echo -e "${YELLOW}[nodes] Installing server-side download nodes...${NC}"
NODES_DIR="$COMFYUI_DIR/custom_nodes"

if [ ! -d "$NODES_DIR/comfy-asset-downloader" ]; then
    git clone https://github.com/ServiceStack/comfy-asset-downloader.git \
        "$NODES_DIR/comfy-asset-downloader" 2>/dev/null || true
fi

if [ ! -d "$NODES_DIR/Civicomfy" ]; then
    git clone https://github.com/MoonGoblinDev/Civicomfy.git \
        "$NODES_DIR/Civicomfy" 2>/dev/null || true
fi

# Install their requirements
for node_dir in comfy-asset-downloader Civicomfy; do
    req="$NODES_DIR/$node_dir/requirements.txt"
    if [ -f "$req" ]; then
        pip install -r "$req" --break-system-packages -q 2>/dev/null || \
        pip install -r "$req" -q 2>/dev/null || true
    fi
done

echo -e "${GREEN}  ✓ Server-side download nodes ready.${NC}"

# --- Done ---
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Setup complete!${NC}"
echo -e "${CYAN}  ${NC}"
echo -e "${CYAN}  Profiles installed: ${SELECTED_PROFILES[*]:-none}${NC}"
echo -e "${CYAN}  ${NC}"
echo -e "${CYAN}  Ad-hoc model downloads during session:${NC}"
echo -e "${CYAN}    • comfy-asset-downloader — add download nodes to workflows${NC}"
echo -e "${CYAN}    • Civicomfy — search/download from CivitAI in the UI${NC}"
echo -e "${CYAN}  ${NC}"
echo -e "${CYAN}  Restart ComfyUI to pick up new nodes/models.${NC}"
echo -e "${CYAN}============================================================${NC}"
