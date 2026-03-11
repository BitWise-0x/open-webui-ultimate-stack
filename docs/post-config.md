# Post-Configuration Guide

<p>
  <img src="https://img.shields.io/badge/scope-post--deploy-4CAF50?style=flat-square" alt="Post-deploy"/>
  <img src="https://img.shields.io/badge/admin-manual_steps-EF5350?style=flat-square" alt="Manual steps"/>
</p>

Steps that require manual configuration **after** deployment. Everything below assumes the stack is running and healthy.

Tooling sourced from [Haervwe/open-webui-tools](https://github.com/Haervwe/open-webui-tools).
Local path: `conf/tools/` (tools, functions, filters, extras subdirectories).

<br>

## Manual Admin UI Steps

### MCP Connections (Native Streamable HTTP)

<img src="https://img.shields.io/badge/automated-MCPO_%2B_TOOL__SERVER__CONNECTIONS-4CAF50?style=flat-square" alt="MCPO automated"/>
<img src="https://img.shields.io/badge/manual-native_Streamable_HTTP-FF9800?style=flat-square" alt="Streamable HTTP manual"/>

> **Automated:** The MCPO proxy service and its PostgreSQL MCP connection are deployed automatically via `docker-stack-compose.yml` + `config.json`. The `TOOL_SERVER_CONNECTIONS` env var in `owui.env` registers the MCPO endpoint with Open WebUI on startup.
>
> **Manual:** Native Streamable HTTP connections (GitHub, gitmcp.io) must be added through the Admin UI — Open WebUI does not support pre-configuring these via env vars or API.

<table>
<tr>
<td valign="top" width="50%">

#### GitHub MCP

- **Admin Panel** > Settings > External Tools > + (Add Connection)
- Type: **MCP (Streamable HTTP)**
- URL: `https://api.githubcopilot.com/mcp/`
- Auth: **Bearer** + your GitHub PAT
- Save and verify connection (green checkmark)
- Optional: use URL variants like `/x/repos,issues` or `/readonly` to limit scope

</td>
<td valign="top" width="50%">

#### gitmcp.io

- **Admin Panel** > Settings > External Tools > + (Add Connection)
- Type: **MCP (Streamable HTTP)**
- URL: `https://gitmcp.io/docs`
- Auth: None
- If connection fails, re-add to MCPO `config.json` as stdio fallback

</td>
</tr>
</table>

<br>

### Native Function Calling (Agentic Mode)

<img src="https://img.shields.io/badge/automated-ENABLE__PERSISTENT__CONFIG-4CAF50?style=flat-square" alt="Persistent config automated"/>
<img src="https://img.shields.io/badge/manual-per--model_toggle-FF9800?style=flat-square" alt="Per-model toggle manual"/>

> **Automated:** `ENABLE_PERSISTENT_CONFIG=true` is set in `env/owui.env`, which enables the DB-backed storage mechanism so settings persist across restarts.
>
> **Manual:** The actual per-model `Function Calling = "Native"` toggle must be set in the Admin UI for each model individually. There is no env var or API to pre-configure this.

Per-model setting — no global toggle. Only needs to be done once per model (persists to DB).

| Setting | Path |
|---------|------|
| Per-model (persistent) | Admin Panel > Settings > **Models** > select model > **Advanced Parameters** > Function Calling = **"Native"** |
| Per-chat (session only) | Chat Controls (gear icon) > Advanced Params > Function Calling = **"Native"** |

> Enables built-in tools: web search, knowledge base queries, notes/memory, image gen.
> Works best with frontier models (GPT-4.1+, Claude 4+, Gemini 2.5+).

<br>
<br>

## Environment Variables

<img src="https://img.shields.io/badge/automated-service_URLs-4CAF50?style=flat-square" alt="Service URLs automated"/>
<img src="https://img.shields.io/badge/manual-API_keys-FF9800?style=flat-square" alt="API keys manual"/>

> **Automated:** Service URLs (ComfyUI, Ollama, SearXNG, WebUI) are pre-set in `env/owui.env` and injected into the container at deploy time. Tools read these via `os.getenv()` in their Valve defaults.
>
> **Manual:** API keys for third-party services are commented out by default. Uncomment and populate them in `env/owui.env` before deploying, or set them after deploy and restart the stack.

### Service URLs

| Variable | Used By |
|----------|---------|
| `COMFYUI_API_URL` | All ComfyUI tools + Flux Kontext pipe |
| `OLLAMA_BASE_URL` | All tools with model unloading |
| `SEARXNG_IMAGE_SEARCH_URL` | SearXNG Image Search tool |
| `WEBUI_URL` | Native Image Gen tool |
| `OPENROUTER_API_KEY` | OpenRouter Image pipe |

### API Keys (commented out — uncomment when needed)

| Variable | Tool | Where to Get It |
|----------|------|-----------------|
| `GOOGLE_API_KEY` | Veo3 video generation pipe | [Google AI Studio](https://aistudio.google.com/) |
| `YOUTUBE_API_KEY` | YouTube Search tool, Mopidy controller | [Google Cloud Console](https://console.cloud.google.com/apis/credentials) — enable YouTube Data API v3 |
| `PEXELS_API_KEY` | Pexels Image/Video Search tool | [Pexels API](https://www.pexels.com/api/) (free) |
| `HF_API_KEY` | HuggingFace Image Generator tool | [HuggingFace Settings](https://huggingface.co/settings/tokens) |
| `CLOUDFLARE_API_TOKEN` | Cloudflare Image Generator tool | Cloudflare dashboard |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Image Generator tool | Cloudflare dashboard |
| `OPENWEATHERMAP_API_KEY` | OpenWeatherMap Forecast tool | [OpenWeatherMap](https://openweathermap.org/api) (free tier available) |
| `TAVILY_API_KEY` | arXiv Research MCTS pipe | [tavily.com](https://tavily.com) |
| `RAPIDAPI_KEY` | Resume Analyzer pipe (job search) | [RapidAPI](https://rapidapi.com/) (optional) |
| `COMFYUI_API_KEY` | All ComfyUI tools (bearer token auth) | Your ComfyUI instance (if auth enabled) |

<br>
<br>

## Filter Activation

<img src="https://img.shields.io/badge/automated-install_via_tools--init-4CAF50?style=flat-square" alt="Install automated"/>
<img src="https://img.shields.io/badge/manual-enable_per--model_%2B_valves-FF9800?style=flat-square" alt="Enable manual"/>
<img src="https://img.shields.io/badge/count-7-555?style=flat-square" alt="7"/>

> **Automated:** All filter Python files are pushed to Open WebUI via the `tools-init` sidecar on every deploy. They are installed and available immediately.
>
> **Manual:** Filters are disabled by default. Each filter must be toggled on per-model in **Workspace > Models**. Some filters also require Valve configuration (e.g. `router_model_id` for the semantic router).

Filters must be enabled per-model:

1. Go to **Workspace > Models**
2. Select a model
3. Open the **Filters** tab
4. Toggle on the desired filters

| Filter | Notes |
|--------|-------|
| `semantic_router_filter` | Routes prompts to the best model. Requires model descriptions to be set in Workspace > Models for each model you want routable. Set `router_model_id` valve to a capable model. |
| `full_document_filter` | **Required** by the Resume Analyzer pipe. Enable it on whatever model you use with that pipe. |
| `prompt_enhancer_filter` | Rewrites user prompts for better results. Set the enhancer model in its Valves. |
| `openrouter_websearch_citations_filter` | Adds web search + citations to OpenRouter models. Configure search engine in Valves. |
| `clean_thinking_tags_filter` | Cleans up incomplete `<think>` tags. Useful for reasoning models. |
| `doodle_paint_filter` | Adds a paint canvas UI for hand-drawn sketches. |
| `glm_v_box_token_filter` | Strips GLM vision model box tokens. Only needed if using GLM V models. |

<br>
<br>

## ComfyUI Setup

<img src="https://img.shields.io/badge/automated-env_vars_%2B_tool_install-4CAF50?style=flat-square" alt="Env + install automated"/>
<img src="https://img.shields.io/badge/manual-models%2C_nodes%2C_workflows-FF9800?style=flat-square" alt="Models manual"/>
<img src="https://img.shields.io/badge/ComfyUI-external-FF9800?style=flat-square" alt="External"/>

> **Automated:** `COMFYUI_API_URL` and `COMFYUI_API_KEY` are set in `env/owui.env`. The ComfyUI tool Python files are pushed via `tools-init` on every deploy.
>
> **Manual:** ComfyUI itself is external to this stack. Models must be downloaded, custom nodes installed, and workflows imported into ComfyUI manually. Valve node IDs may need adjustment if you modify the bundled workflows.

### Prerequisites

1. ComfyUI running and accessible at the URL set in `COMFYUI_API_URL`
2. If using auth: set `COMFYUI_API_KEY` in `env/owui.env`

### Per-Tool Setup

Each ComfyUI tool requires specific models and workflows loaded in ComfyUI.

<table>
<tr>
<td valign="top" width="50%">

#### Image-to-Image (Qwen Edit 2509)
- **Models**: Qwen Image Edit 2509, Qwen CLIP, VAE
- **Custom Nodes**: `ETN_LoadImageBase64`
- **Workflow**: `conf/tools/extras/image_qwen_image_edit_2509_api_owui.json`
- **Alt Mode**: Flux Kontext (set `workflow_type` valve to `Flux_Kontext`)

#### Text-to-Image (Qwen)
- **Models**: Qwen model
- **Workflow**: `conf/tools/extras/image_qwen_image.json`

#### ACE Step Audio (Legacy)
- **Models**: `ACE_STEP/ace_step_v1_3.5b.safetensors`
- **Workflow**: `conf/tools/extras/ace_step_api.json`
- Configure node IDs in Valves if you modified the workflow

#### ACE Step 1.5 Audio
- **Models**: `ace_step_1.5_turbo_aio.safetensors`
- **Custom Nodes**: `ComfyUI-Unload-Model` (optional, for VRAM cleanup)
- **Workflow**: `conf/tools/extras/audio_ace_step_1_5_API.json` or `ace_step_1_5_select_encoders_api.json`
- **User Valves**: Users can set steps, seed, and audio codes per-session

</td>
<td valign="top" width="50%">

#### VibeVoice TTS
- **Models**: Pre-loaded voice files in ComfyUI
- **Workflows**: `conf/tools/extras/Vibe-Voice-Single-Speaker.json` and/or `Vibe-voice-Multiple-Speaker.json`
- Configure text/seed node IDs in Valves

#### Text-to-Video (WAN 2.2)
- **Models**: WAN 2.2 14B
- **Workflow**: `conf/tools/extras/video_wan2_2_14B_t2v.json`
- Default prompt node ID is `"89"`

#### Flux Kontext Pipe (Function)
- **Models**: Flux Dev, Flux Kontext LoRA
- **Workflow**: `conf/tools/extras/flux_context_owui_api_v1.json`
- **Setup**: Type `/setup` in chat as admin for interactive configuration
- Default node IDs: prompt=`"6"`, image=`"196"`, sampler=`"194"`

</td>
</tr>
</table>

### Workflow Import Steps

1. Open ComfyUI web UI
2. Import the JSON workflow from `conf/tools/extras/`
3. If any nodes show as missing: install the required custom node package
4. Verify the workflow runs manually before using from Open WebUI
5. In Open WebUI, configure the tool's Valves (admin panel) — node IDs should match defaults unless you modified the workflow

### VRAM Management

Several tools support `unload_ollama_models` (default: off). When enabled, tools will call Ollama's API to unload all loaded models before running ComfyUI, freeing GPU VRAM. Useful when Ollama and ComfyUI share the same GPU.

<br>
<br>

## Function Pipes

<img src="https://img.shields.io/badge/automated-install_via_tools--init-4CAF50?style=flat-square" alt="Install automated"/>
<img src="https://img.shields.io/badge/manual-valves_%28model_IDs%2C_temps%2C_URLs%29-FF9800?style=flat-square" alt="Valves manual"/>

> **Automated:** All function pipe Python files are pushed to Open WebUI via `tools-init` on every deploy. Pipes that use env vars (e.g. `GOOGLE_API_KEY`, `TAVILY_API_KEY`) pick them up automatically if set in `env/owui.env`.
>
> **Manual:** Each pipe's Valves must be configured in the Admin Panel — model IDs, temperature settings, external service URLs, and API keys that aren't covered by env vars.

<table>
<tr>
<td valign="top" width="50%">

#### Planner Agent v2
- Set `MODEL`, `ACTION_MODEL`, `WRITER_MODEL`, `CODER_MODEL` in Valves
- Temperature controls for each role (planning, action, writing, coding, analysis)
- Automatically discovers and uses all available Open WebUI tools

#### arXiv Research MCTS
- Requires `TAVILY_API_KEY` for web search
- Configure `tree_breadth`, `tree_depth`, `exploration_weight` for search intensity

#### Multi Model Conversations v2
- Per-user configuration via User Valves (gear icon in chat)
- Set up to 5 participants with different models and personas
- v2.6.0 adds: tool calling, live execution streaming, speaker color indicators

#### Perplexica Pipe
- Requires a self-hosted [Perplexica](https://github.com/ItzCrazyKns/Perplexica) instance
- Set `BASE_URL` valve (default: `http://host.docker.internal:3001`)
- Configure `CHAT_MODEL` and `EMBEDDING_MODEL` to match your Perplexica setup

</td>
<td valign="top" width="50%">

#### Veo3 Pipe (Google Video Generation)
- Requires `GOOGLE_API_KEY` with Gemini API access
- Supports text-to-video and image-to-video (single image only)
- Optional: vision model prompt enhancement

#### Mopidy Music Controller
- Requires [Mopidy](https://mopidy.com/) + [Mopidy-Iris](https://github.com/jaedb/Iris) running
- Set `mopidy_url` valve (default: `http://localhost:6680/mopidy/rpc`)
- Optional: `YOUTUBE_API_KEY` for YouTube playback

#### Resume Analyzer
- **Requires** `full_document_filter` enabled on the model
- Dataset at `conf/tools/extras/UpdatedResumeDataSet.csv`
- Optional: `RAPIDAPI_KEY` for job search integration

</td>
</tr>
</table>

<br>
<br>

## Tools

<img src="https://img.shields.io/badge/automated-install_%2B_env_var_defaults-4CAF50?style=flat-square" alt="Install + env automated"/>
<img src="https://img.shields.io/badge/manual-external_service_valves-FF9800?style=flat-square" alt="External valves manual"/>

> **Automated:** All tool Python files are pushed via `tools-init` on every deploy. Tools that reference env vars (e.g. `SEARXNG_IMAGE_SEARCH_URL`, `OLLAMA_BASE_URL`) pick up their defaults from `env/owui.env`.
>
> **Manual:** Tools that depend on external services (Perplexica, image backends) need their Valves configured in the Admin Panel to point to the correct endpoints.

<table>
<tr>
<td valign="top" width="50%">

#### Perplexica Search Tool
- Same Perplexica instance as the pipe
- Set `BASE_URL`, `CHAT_MODEL`, `EMBEDDING_MODEL` in Valves

#### SearXNG Image Search
- Uses `SEARXNG_IMAGE_SEARCH_URL` env var (default: `http://searxng:8080/search`)
- SearXNG must be running (already part of this stack)

</td>
<td valign="top" width="50%">

#### Native Image Generator
- Uses whatever image backend is configured in Open WebUI admin (Settings > Images)
- Works with AUTOMATIC1111, ComfyUI, or OpenAI backends
- Optional Ollama model unloading for VRAM

</td>
</tr>
</table>

<br>
<br>

## Syncing with Upstream

<img src="https://img.shields.io/badge/automated-deploy_push_via_tools--init-4CAF50?style=flat-square" alt="Deploy push automated"/>
<img src="https://img.shields.io/badge/manual-upstream_pull_%2B_env_patching-FF9800?style=flat-square" alt="Pull + patch manual"/>

> **Automated:** `tools-init` pushes whatever is in `conf/tools/` on every deploy — no manual upload needed after syncing files locally.
>
> **Manual:** Pulling from upstream and re-patching `os.getenv()` calls in Valve defaults must be done locally before deploying.

The tools are sourced from the [Haervwe/open-webui-tools](https://github.com/Haervwe/open-webui-tools) repository.

After syncing (copying files from upstream to `conf/tools/`), the `os.getenv()` calls
in Valve defaults will be overwritten with hardcoded values. These must be re-patched
to restore environment variable integration.

> **Env vars used in tool Valve defaults:**
> `COMFYUI_API_URL`, `COMFYUI_API_KEY`, `OLLAMA_BASE_URL`, `SEARXNG_IMAGE_SEARCH_URL`, `WEBUI_URL`,
> `OPENROUTER_API_KEY`, `GOOGLE_API_KEY`, `YOUTUBE_API_KEY`, `PEXELS_API_KEY`, `HF_API_KEY`,
> `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `OPENWEATHERMAP_API_KEY`, `TAVILY_API_KEY`, `RAPIDAPI_KEY`
