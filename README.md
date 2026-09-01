# ComfyUI on Vast.ai — No Persistent Disk, Runtime Workflow Selector

Zero-persistence ComfyUI setup for Vast.ai. Pick your workflow profiles at boot, download only the models you need, and use server-side download nodes for anything extra during your session.

## How It Works

```
Boot instance → selector.sh runs → pick profiles → models download → ComfyUI ready
```

1. **selector.sh** presents a menu of workflow profiles (or auto-selects via env var)
2. Each profile is a Prompting Pixels-generated bash script that downloads specific models + custom nodes
3. Matching workflow JSON files get copied into ComfyUI's workflow directory
4. Two server-side download nodes get installed for ad-hoc model grabs during your session

## Repo Structure

```
comfyui-vastai/
├── selector.sh                       # Runtime workflow picker (on-start script)
├── profiles/                         # One .sh per workflow profile
│   ├── sdxl_controlnet.sh           # Generated from Prompting Pixels
│   ├── flux.sh                      # Generated from Prompting Pixels
│   └── wan_video.sh                 # Generated from Prompting Pixels
└── workflows/                        # Workflow JSONs, organized by profile
    ├── common/                       # Shared across all profiles
    │   └── my_upscale_workflow.json
    ├── sdxl_controlnet/
    │   ├── basic_sdxl.json
    │   └── controlnet_depth.json
    ├── flux/
    │   └── flux_dev_basic.json
    └── wan_video/
        └── wan_t2v.json
```

## Setup Guide

### 1. Generate Profile Scripts with Prompting Pixels

For each workflow you want available:

1. Go to [deploy.promptingpixels.com](https://deploy.promptingpixels.com)
2. Select **Vast.ai** as provider
3. Add models for that workflow (checkpoints, LoRAs, VAEs, ControlNets, etc.)
4. Add custom nodes needed by the workflow
5. Click **"Full Script"** to see the raw bash
6. Copy the full script contents into a new file in `profiles/` (e.g., `profiles/sdxl_controlnet.sh`)
7. Add a description comment at the top: `# DESC: Your description here`

The description comment is what appears in the boot menu.

### 2. Add Your Workflow JSONs

Export your workflows from ComfyUI (Menu → Save or Ctrl+S) and place them in the matching `workflows/<profile_name>/` directory. Workflows in `workflows/common/` get copied for every profile.

**Tip:** If you're using comfy-asset-downloader nodes in your workflows, those nodes can have `$HF_TOKEN` and `$CIVITAI_TOKEN` references that resolve from environment variables on the server. This means the workflow itself can trigger server-side downloads for any models the provisioning script missed.

### 3. Push to GitHub

```bash
cd comfyui-vastai
git init
git add .
git commit -m "Initial setup"
git remote add origin https://github.com/youruser/comfyui-vastai.git
git push -u origin main
```

### 4. Configure Vast.ai Template

1. Go to [cloud.vast.ai/templates](https://cloud.vast.ai/templates/)
2. Search for and select the **official ComfyUI template** as your base
3. Click **Edit** to customize
4. Set these **Environment Variables**:

| Key | Value | Notes |
|-----|-------|-------|
| `HF_TOKEN` | `hf_yourTokenHere` | HuggingFace read token |
| `CIVITAI_TOKEN` | `your_civitai_token` | CivitAI API token |
| `REPO_URL` | `https://github.com/youruser/comfyui-vastai.git` | Your setup repo |
| `AUTO_PROFILE` | *(optional)* `sdxl_controlnet` | Skip menu, auto-run this profile |

5. In the **On-start Script** section, add:

```bash
#!/bin/bash
env >> /etc/environment

# Clone setup repo and run selector
git clone $REPO_URL /workspace/comfyui-setup 2>/dev/null || \
    (cd /workspace/comfyui-setup && git pull --ff-only)

chmod +x /workspace/comfyui-setup/selector.sh
/workspace/comfyui-setup/selector.sh
```

6. Save the template

### 5. Usage

#### Interactive mode (SSH in first)

If you **don't** set `AUTO_PROFILE`, the selector waits for your input. SSH into the instance and you'll see:

```
============================================================
  ComfyUI Vast.ai — Workflow Selector
============================================================

Available workflow profiles:

  [1] sdxl_controlnet — SDXL + ControlNet, DreamShaper XL, IPAdapter
  [2] flux — Flux Dev, T5 encoder, Flux LoRAs
  [3] wan_video — Wan 2.1 Video, T5 encoder, video nodes

  [a] All profiles
  [0] None (just start ComfyUI with existing models)

Enter your choice (comma-separated for multiple, e.g. 1,3):
> 
```

Pick what you need. Only those models download.

#### Auto mode (headless)

Set `AUTO_PROFILE=sdxl_controlnet,flux` in your template env vars. The selector skips the menu and runs those profiles automatically. Good for when you know what you want and don't want to SSH in.

### 6. During a Session — Ad-Hoc Downloads

Two custom nodes are always installed regardless of profile selection:

**comfy-asset-downloader** — Add a download node to any workflow. Set the URL to a HF or CivitAI model, set the save path, and use `$HF_TOKEN` or `$CIVITAI_TOKEN` for auth. The download happens on the server, not your browser.

**Civicomfy** — Opens a CivitAI browser panel inside ComfyUI. Search, browse, download directly to the server. Set your CivitAI token in the Civicomfy settings panel (or it picks up `CIVITAI_API_KEY` from the environment — you can add `export CIVITAI_API_KEY=$CIVITAI_TOKEN` to your on-start script).

Both solve the "clicking download sends it to my local machine" problem — downloads go to the server's `/workspace/ComfyUI/models/` directories.

After downloading new models, press **R** in ComfyUI to refresh the model lists.

## Tips

- **Bandwidth costs money on Vast.ai.** Hover the price on GPU listings to see $/TB. If you're downloading 20GB+ of models per boot, pick hosts with cheap bandwidth.
- **Profile scripts are idempotent.** Most use `wget -c` (continue) or `git clone ... 2>/dev/null || true`, so re-running on a stopped-and-restarted (not destroyed) instance skips already-downloaded files.
- **Share models across profiles.** If SDXL and ControlNet both need the same VAE, put the download in both scripts — `wget -c` will skip it the second time.
- **Test locally first.** Prompting Pixels supports local machine paths. Generate a script pointed at your local ComfyUI install to verify the workflow works before burning cloud credits.
