#!/bin/bash
# DESC: SDXL v1.0 + DMD2 LoRA — DreamShaper XL base with DMD2 4-step acceleration
#
# ComfyUI Provisioning Script — Lane 2: v1.0 Base + DMD2 LoRA
# Generated from Prompting Pixels, corrected filenames and paths
#
# Settings: CFG 0, 4 steps, LCM scheduler, DMD2 LoRA weight 0.7-1.0
# DMD2 LoRA for 4-step acceleration on non-turbo base
#

set -e

# ===== Configuration =====
COMFYUI_DIR=/workspace/ComfyUI
COMFYUI_VERSION="v0.18.2"

# Custom nodes
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/ltdrdata/comfyui-connection-helper"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/ltdrdata/ComfyUI-Inspire-Pack"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
    "https://github.com/ssitu/ComfyUI_UltimateSDUpscale"
    "https://github.com/traugdor/ComfyUI-UltimateSDUpscale-GGUF"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/ShmuelRonen/multi-lora-stack"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/ParmanBabra/ComfyUI-Malefish-Custom-Scripts"
    "https://github.com/fuselayer/comfyui-minimal-workflow-image"
    "https://github.com/ServiceStack/comfy-asset-downloader"
    "https://github.com/huchukato/ComfyUI-HuggingFace"
    "https://github.com/MoonGoblinDev/Civicomfy"
)

# Models — no DMD2 LoRA for Turbo
LORA_MODELS=(
    "https://huggingface.co/tianweiy/DMD2/resolve/main/dmd2_sdxl_4step_lora_fp16.safetensors|dmd2_sdxl_4step_lora_fp16.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl.vae.safetensors|sdxl.vae.safetensors"
)

VAE_APPROX_MODELS=(
    "https://huggingface.co/madebyollin/taesdxl/resolve/main/diffusion_pytorch_model.safetensors|taesdxl.safetensors"
)

CONTROLNET_MODELS=(
    "https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.fp16.safetensors|controlnet-depth-sdxl.safetensors"
    "https://huggingface.co/diffusers/controlnet-canny-sdxl-1.0/resolve/main/diffusion_pytorch_model.fp16.safetensors|controlnet-canny-sdxl.safetensors"
)

IPADAPTER_MODELS=(
    "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors|ip-adapter_sdxl_vit-h.safetensors"
)

CLIP_VISION_MODELS=(
    "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors|ip-adapter-clip-vit-h.safetensors"
)

UPSCALER_MODELS=(
    "https://huggingface.co/Phips/4xNomosUniDAT_otf/resolve/main/4xNomosUniDAT_otf.safetensors|4xNomosUniDAT_otf.safetensors"
)

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/126688|dreamshaperXL_alpha2Xl10.safetensors"
)

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

    # Skip if file already exists
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
echo "  Lane 2: DreamShaper XL v1.0 + DMD2"
echo "  CFG 0 | 4 steps | LCM scheduler | DMD2 LoRA"
echo "=============================================="
echo ""

setup_comfyui
install_custom_nodes

echo ""
echo "[models] Downloading models..."
download_models "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/vae_approx" "${VAE_APPROX_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/ipadapter" "${IPADAPTER_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/upscale_models" "${UPSCALER_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"

echo ""
echo "=============================================="
echo "  Lane 2 complete! v1.0 + DMD2 ready."
echo "=============================================="
