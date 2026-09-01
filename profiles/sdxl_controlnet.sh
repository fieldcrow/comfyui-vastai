#!/bin/bash
# DESC: SDXL + ControlNet — DreamShaper XL, ControlNet models, IPAdapter
# 
# This script was generated from deploy.promptingpixels.com
# and customized for this setup. Replace the contents below
# with the "Full Script" output from Prompting Pixels for your
# SDXL workflow configuration.
#
# When generating your script in Prompting Pixels:
#   1. Select provider: Vast.ai
#   2. Add models: your SDXL checkpoint, ControlNets, LoRAs, etc.
#   3. Add custom nodes: ControlNet preprocessors, IPAdapter, etc.
#   4. Click "Full Script" and paste the contents here.
#
# ============================================================

# --- PASTE YOUR PROMPTING PIXELS "FULL SCRIPT" BELOW ---

# Example placeholder (replace with actual generated script):
echo "[sdxl_controlnet] This is a placeholder."
echo "[sdxl_controlnet] Replace this file's contents with your"
echo "[sdxl_controlnet] Prompting Pixels generated script."
echo ""
echo "[sdxl_controlnet] The script should handle:"
echo "  - ComfyUI installation/update"
echo "  - Model downloads to correct directories"
echo "  - Custom node installation"

# --- EXAMPLE of what the generated script roughly does ---
# (uncomment and modify when you have real URLs)

# COMFYUI_ROOT="/workspace/ComfyUI"
#
# # Models
# wget -c -O "$COMFYUI_ROOT/models/checkpoints/dreamshaperXL_v21TurboDPMSDE.safetensors" \
#   "https://civitai.com/api/download/models/351306?token=$CIVITAI_TOKEN"
#
# wget -c -O "$COMFYUI_ROOT/models/controlnet/diffusers_xl_depth_full.safetensors" \
#   "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/diffusers_xl_depth_full.safetensors"
#
# # Custom nodes
# cd "$COMFYUI_ROOT/custom_nodes"
# git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git 2>/dev/null || true
# git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git 2>/dev/null || true
