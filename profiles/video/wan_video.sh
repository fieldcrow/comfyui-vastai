#!/bin/bash
# DESC: Wan 2.1 Video — text-to-video and image-to-video, 14B fp16 model
#
# ComfyUI Provisioning Script — Wan 2.1 Video
# Requires: 24GB+ VRAM for fp16 14B, or use fp8 for tighter VRAM
#
# Settings: 20-30 steps, Euler, Normal scheduler
# Use fp16 weights (NOT bf16) for best quality
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
    "https://github.com/huchukato/ComfyUI-HuggingFace"
    "https://github.com/MoonGoblinDev/Civicomfy"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
)

# Wan 2.1 diffusion model — 14B fp16 for best quality
# For lower VRAM, swap to the fp8 variant:
#   "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_fp8_scaled.safetensors|wan2.1_t2v_14B_fp8.safetensors"
DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_fp16.safetensors|wan2.1_t2v_14B_fp16.safetensors"
)

# Wan uses its own text encoder and VAE
TEXT_ENCODER_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|umt5_xxl_fp8_e4m3fn.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors|wan_2.1_vae.safetensors"
)

# CLIP vision for image-to-video workflows
CLIP_VISION_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors|wan_clip_vision_h.safetensors"
)

UPSCALER_MODELS=(
    "https://huggingface.co/Phips/4xNomosUniDAT_otf/resolve/main/4xNomosUniDAT_otf.safetensors|4xNomosUniDAT_otf.safetensors"
)

# Not used for Wan
VAE_APPROX_MODELS=()
LORA_MODELS=()
CHECKPOINT_MODELS=()
CONTROLNET_MODELS=()
IPADAPTER_MODELS=()

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
    elif [[ -n $CIVITAI_TOKEN && $download_url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com ]]; then
        local civitai_url="$download_url"
        if [[ "$civitai_url" == *"?"* ]]; then
            civitai_url="${civitai_url}&token=$CIVITAI_TOKEN"
        else
            civitai_url="${civitai_url}?token=$CIVITAI_TOKEN"
        fi
        if [[ -n "$custom_filename" ]]; then
            curl -fL -o "$download_dir/$custom_filename" "$civitai_url"
        else
            (cd "$download_dir" && curl -fL -J -O "$civitai_url")
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
echo "  Wan 2.1 — 14B Video Generation"
echo "  20-30 steps | Euler | Normal scheduler"
echo "=============================================="
echo ""

setup_comfyui
install_custom_nodes

echo ""
echo "[models] Downloading models..."
download_models "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODER_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/upscale_models" "${UPSCALER_MODELS[@]}"

echo ""
echo "=============================================="
echo "  Wan 2.1 complete!"
echo "  Total download: ~30GB (14B fp16)"
echo "  Workflows: comfyanonymous.github.io/ComfyUI_examples/wan/"
echo "=============================================="
