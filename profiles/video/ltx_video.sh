#!/bin/bash
# DESC: LTX Video — ultra-fast video generation, 5-second clip in 2 seconds
#
# ComfyUI Provisioning Script — LTX Video
# Requires: 16GB+ VRAM
#
# Settings: 20 steps, Euler, Normal scheduler
# Great for rapid iteration before committing to slower Wan renders
#

set -e

# ===== Configuration =====
COMFYUI_DIR=/workspace/ComfyUI
COMFYUI_VERSION="v0.18.2"

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/ServiceStack/comfy-asset-downloader"
    "https://github.com/MoonGoblinDev/Civicomfy"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.safetensors|ltx-video-2b-v0.9.safetensors"
)

TEXT_ENCODER_MODELS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors|t5xxl_fp8_e4m3fn.safetensors"
)

# Not used — LTX uses its own internal VAE
VAE_MODELS=()
VAE_APPROX_MODELS=()
LORA_MODELS=()
CHECKPOINT_MODELS=()
CONTROLNET_MODELS=()
IPADAPTER_MODELS=()
CLIP_VISION_MODELS=()
UPSCALER_MODELS=()

# ===== Helper Functions =====

function setup_comfyui() {
    echo "[setup] Setting up ComfyUI..."
    if [[ -d "$COMFYUI_DIR" ]]; then
        echo "[setup] ComfyUI exists. Updating to $COMFYUI_VERSION..."
        cd "$COMFYUI_DIR"
        git config --global --add safe.directory "$COMFYUI_DIR" || true
        git fetch --all --tags || echo "Warning: Could not fetch updates"
        git checkout "$COMFYUI_VERSION" 2>/dev/null || echo "Warning: Could not checkout $COMFYUI_VERSION"
    else
        echo "[setup] Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
        cd "$COMFYUI_DIR"
        git checkout "$COMFYUI_VERSION" 2>/dev/null || true
    fi
    if [[ -f "requirements.txt" ]]; then
        pip install --no-cache-dir -r requirements.txt 2>/dev/null || \
        pip install --no-cache-dir --break-system-packages -r requirements.txt
    fi
}

function install_custom_nodes() {
    if [[ ${#NODES[@]} -eq 0 ]]; then return; fi
    echo "[nodes] Installing ${#NODES[@]} custom node(s)..."
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        if [[ -d $path ]]; then
            echo "[nodes] Updating: $dir"
            (cd "$path" && git pull) || true
        else
            echo "[nodes] Installing: $dir"
            git clone "$repo" "$path" --recursive || true
        fi
        if [[ -f "$path/requirements.txt" ]]; then
            pip install --no-cache-dir -r "$path/requirements.txt" 2>/dev/null || \
            pip install --no-cache-dir --break-system-packages -r "$path/requirements.txt" 2>/dev/null || true
        fi
    done
}

function download_file() {
    local url_input="$1"
    local download_dir="$2"
    local custom_filename=""
    local download_url=""

    if [[ "$url_input" == *"|"* ]]; then
        download_url="${url_input%|*}"
        custom_filename="${url_input#*|}"
        custom_filename="$(echo "$custom_filename" | sed 's/\//_/g')"
    else
        download_url="$url_input"
    fi

    if [[ $download_url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co.*\/blob\/ ]]; then
        download_url=$(echo "$download_url" | sed 's|/blob/|/resolve/|')
    fi

    mkdir -p "$download_dir"

    if [[ -n "$custom_filename" && -f "$download_dir/$custom_filename" ]]; then
        echo "[download] Already exists: $custom_filename"
        return
    fi

    if [[ -n $HF_TOKEN && $download_url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co ]]; then
        if [[ -n "$custom_filename" ]]; then
            wget --header="Authorization: Bearer $HF_TOKEN" -c --show-progress -O "$download_dir/$custom_filename" "$download_url"
        else
            wget --header="Authorization: Bearer $HF_TOKEN" -c --content-disposition --show-progress -P "$download_dir" "$download_url"
        fi
    else
        if [[ -n "$custom_filename" ]]; then
            wget -c --show-progress -O "$download_dir/$custom_filename" "$download_url"
        else
            wget -c --content-disposition --show-progress -P "$download_dir" "$download_url"
        fi
    fi
}

function download_models() {
    local dir="$1"
    shift
    local arr=("$@")
    if [[ ${#arr[@]} -eq 0 ]]; then return; fi
    echo "[models] Downloading ${#arr[@]} model(s) to $dir..."
    for url in "${arr[@]}"; do
        download_file "$url" "$dir"
    done
}

# ===== Main =====

echo ""
echo "=============================================="
echo "  LTX Video — Fast 2B Video Generation"
echo "  20 steps | Euler | Normal scheduler"
echo "=============================================="
echo ""

setup_comfyui
install_custom_nodes

echo ""
echo "[models] Downloading models..."
download_models "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODER_MODELS[@]}"

echo ""
echo "=============================================="
echo "  LTX Video complete!"
echo "  Total download: ~12GB"
echo "  Workflows: comfyanonymous.github.io/ComfyUI_examples/ltxv/"
echo "=============================================="
