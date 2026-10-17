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
>
> **Postgres MCP server:** `postgres-mcp` in restricted (read-only) mode. Admin-only by default.

<table>
<tr>
<td valign="top" width="50%">

#### GitHub MCP

- **Settings > Admin** > External Tools > + (Add Connection)
- Type: **MCP (Streamable HTTP)**
- URL: `https://api.githubcopilot.com/mcp/`
- Auth: **Bearer** + your GitHub PAT
- Save and verify connection (green checkmark)
- Optional: use URL variants like `/x/repos,issues` or `/readonly` to limit scope

</td>
<td valign="top" width="50%">

#### gitmcp.io

- **Settings > Admin** > External Tools > + (Add Connection)
- Type: **MCP (Streamable HTTP)**
- URL: `https://gitmcp.io/docs`
- Auth: None
- If connection fails, re-add to MCPO `config.json` as stdio fallback

</td>
</tr>
</table>

<br>

### Native Function Calling (Agentic Mode)

<img src="https://img.shields.io/badge/automated-native_by_default-4CAF50?style=flat-square" alt="Native by default"/>
<img src="https://img.shields.io/badge/manual-opt--out_to_Legacy-FF9800?style=flat-square" alt="Opt-out manual"/>

> **Automated:** Native tool calling is the default for every model.
>
> **Manual:** Switch a model to **Legacy** (prompt-based) only if it has no native tool support:

| Setting | Path |
|---------|------|
| Per-model (persistent) | Settings > Admin > **Models** > select model > **Advanced Parameters** > Function Calling = **"Legacy"** |
| Global default | Settings > Admin > Models > **Default model parameters** |
| Per-chat (session only) | Chat Controls (gear icon) > Advanced Params > Function Calling |

> Native mode enables built-in tools: web search, knowledge base queries, notes/memory, image gen, skills, tasks.
> `env/owui.env` also turns on sub-agents, Tool Search and context compaction (see *Agentic features* there).
> Works best with frontier models (Claude, GPT, Gemini) and recent tool-capable Ollama models.

<br>

### Anthropic (Claude) Connection

<img src="https://img.shields.io/badge/automated-env_seed_on_fresh_DB-4CAF50?style=flat-square" alt="Env seed on fresh DB"/>
<img src="https://img.shields.io/badge/manual-add_once_on_existing_installs-FF9800?style=flat-square" alt="Add once on existing installs"/>

> **Automated (fresh install):** `OPENAI_API_BASE_URLS` in `env/owui.env` lists OpenAI, OpenRouter and Anthropic, and `OPENAI_API_KEYS` holds the three keys in the same order. Open WebUI recognizes the `api.anthropic.com` URL: it lists Claude models natively and sends the key as `x-api-key`.
>
> **Manual (existing install):** with `ENABLE_PERSISTENT_CONFIG=true` those env vars only seed a fresh database, so add the connection once in the UI. It persists from then on.

1. **Settings > Admin > Connections > OpenAI API > +** (Add Connection)
2. URL: `https://api.anthropic.com/v1`, Auth: **Bearer**, Key: your `sk-ant-...` key from <https://console.anthropic.com/settings/keys>
3. Optional: a **Prefix ID** (e.g. `anthropic`) and a **Model IDs** allowlist; empty means every model the key can see
4. Save, then check that the Claude models appear in the model picker.
5. Optional: set **Settings > Admin > Interface > Task model for external models** to a small Claude model, so titles, tags and follow-ups for Claude chats stay cheap.

> **Cost guard:** `CHAT_RESPONSE_MAX_TOOL_CALL_ITERATIONS=20` in `env/owui.env` caps tool-call loops per response (upstream default is 256).

Open WebUI also *serves* an Anthropic-compatible Messages API at `/api/v1/messages` (plus `/api/v1/messages/count_tokens` and `/api/v1/models`), routed to any model it has. Create a key under **Settings > Account > API Keys** (`ENABLE_API_KEYS=true` is set in `env/owui.env`) and point a client at `http://<host>:3000/api`. If Open WebUI sits behind a browser-based forward-auth proxy (such as the commented Traefik `chain-oauth` labels), API clients cannot complete that login and need a route that skips it.

<br>

### Code Interpreter (Jupyter)

<img src="https://img.shields.io/badge/automated-jupyter_service_%2B_token-4CAF50?style=flat-square" alt="Jupyter automated"/>
<img src="https://img.shields.io/badge/manual-switch_engine_on_existing_installs-FF9800?style=flat-square" alt="Engine switch manual"/>

> **Automated:** the `jupyter` service runs `quay.io/jupyter/scipy-notebook`. `bootstrap.sh` generates `JUPYTER_TOKEN` in `env/jupyter.env` and copies it into `CODE_INTERPRETER_JUPYTER_AUTH_TOKEN` in `env/owui.env`. On a fresh install the code interpreter uses it immediately.
>
> **Manual (existing install):** set **Settings > Admin > Code Execution > Code Interpreter engine** to **Jupyter**, URL `http://jupyter:8888`, auth **Token**, and paste the value of `JUPYTER_TOKEN` from `env/jupyter.env`.

- One shared kernel with no per-user isolation. Give access to admins and trusted users only.
- The kernel has its own network: it cannot reach the database, Redis or the MCP proxy, and it has no published port. It does have outbound internet access (pip installs, fetching data).
- Files the model writes persist in the `jupyter_work` volume (standalone) or `${DATA_ROOT}/open-webui/jupyter` (Swarm).
- The **run** button on code blocks stays on Pyodide (sandboxed in the browser); only the model-driven interpreter uses Jupyter.

<br>
<br>

## Upgrading

<img src="https://img.shields.io/badge/automated-scale--to--0_on_tag_change_(Swarm)-4CAF50?style=flat-square" alt="Automated scale to 0"/>
<img src="https://img.shields.io/badge/manual-backup_%2B_bump_OWUI__TAG-FF9800?style=flat-square" alt="Backup manual"/>

The Open WebUI image is pinned with `OWUI_TAG` (default `0.12.3`, override in `.env`). Most releases carry database migrations, and upstream does **not** support rolling updates across them.

1. Read the release notes: <https://github.com/open-webui/open-webui/releases>
2. Back up Postgres:
   - Standalone: `docker compose exec db pg_dump -U postgres openwebui | gzip > owui-$(date +%F).sql.gz`
   - Swarm: `docker exec $(docker ps -qf name=open-webui_db) pg_dump -U postgres openwebui | gzip > owui-$(date +%F).sql.gz` (on the node running `db`)
3. Set `OWUI_TAG` in `.env`, then re-run `./bootstrap.sh` (or `./bootstrap.sh --swarm`). On Swarm, `deploy-swarm.sh` scales `openwebui` to 0 when the tag changes, so the new version migrates with no old replica attached. Expect a short outage.

### Upgrading from a pre-0.12 version of this stack

Pull the repository, then re-run `bootstrap.sh`. It handles these automatically:

- creates `env/jupyter.env`, generates the token, and adds `CODE_INTERPRETER_JUPYTER_AUTH_TOKEN` to your existing `env/owui.env`
- migrates `conf/mcposerver/config.json` from `postgres-mcp-server` to `postgres-mcp` (backup kept as `config.json.pre-postgres-mcp.bak`)
- stops if `.env` still pins Tika 3 (`TIKA_TAG=3.x`); change it to `4.1.0-1` or delete the line
- on Swarm: creates the `jupyter` overlay network, removes leftover Tika 3 and uWSGI config files from `DATA_ROOT`, and scales `openwebui` to 0 for the image change

Your existing `env/*.env` files are not overwritten. Compare them with the updated `env/*.env.example` files and merge new or renamed keys you want, in particular in `env/owui.env`: `ENABLE_API_KEYS` (was `ENABLE_API_KEY`), `ENABLE_LOCAL_WEB_FETCH` (was `ENABLE_RAG_LOCAL_WEB_FETCH`), `CHAT_RESPONSE_MAX_TOOL_CALL_ITERATIONS` (was `..._RETRIES`), `TIKA_SERVER_VERSION=4`, the `CODE_INTERPRETER_*` block, and the three-connection `OPENAI_API_*` block. In `env/searxng.env`, the `SEARXNG_UWSGI_*` settings no longer do anything (the image runs Granian).

`ENABLE_PERSISTENT_CONFIG=true` means env values only seed a fresh database. On an existing install, change these once in the UI:

| # | Setting | Where | Why |
|---|---------|-------|-----|
| 1 | Tika server version = **4.x** | Settings > Admin > Documents | The Tika image is now 4.1. A 3/4 mismatch fails every upload, so change this as soon as the new stack is up |
| 2 | Relevance threshold = **0** | Settings > Admin > Documents | Earlier examples set `RAG_RELEVANCE_THRESHOLD=1`, the maximum score, which filters out nearly all results |
| 3 | Hybrid search on, embedding batch size 16 (optional) | Settings > Admin > Documents | Match the current `env/owui.env.example` |
| 4 | postgres tool server: **enable**, Auth = **None** | Settings > Admin > External Tools | The old `TOOL_SERVER_CONNECTIONS` seed lacked `config.enable`, so 0.12 never loads it |
| 5 | Enable API Keys | Settings > Admin > Authentication | `ENABLE_API_KEY` was misnamed and is ignored |
| 6 | Code Interpreter engine = **Jupyter** | Settings > Admin > Code Execution | See [Code Interpreter (Jupyter)](#code-interpreter-jupyter) |
| 7 | Anthropic connection (optional) | Settings > Admin > Connections | See [Anthropic (Claude) Connection](#anthropic-claude-connection) |

Search results will change: SearXNG upstream removed reddit and searchcode, and disabled qwant, startpage and several image engines. Google is re-enabled in `conf/searxng/settings.yml`. The `veo3_pipe` function was removed from `conf/tools/`; its record stays in Open WebUI until you delete it under Settings > Admin > Functions.

<br>
<br>

## Environment Variables

<img src="https://img.shields.io/badge/automated-service_URLs-4CAF50?style=flat-square" alt="Service URLs automated"/>
<img src="https://img.shields.io/badge/manual-API_keys-FF9800?style=flat-square" alt="API keys manual"/>

> **Automated:** Service URLs (ComfyUI, Ollama, SearXNG, WebUI) are pre-set in `env/owui.env` and injected into the container at deploy time. Tools read these via `os.getenv()` in their Valve defaults.
>
> **Manual:** API keys for third-party services are commented out by default. Uncomment and populate them in `env/owui.env` before deploying, or set them after deploy and restart the stack. A Valve default only applies until that Valve is saved in the UI; after that the stored value wins.

### Service URLs

| Variable | Used By |
|----------|---------|
| `COMFYUI_API_URL` | All ComfyUI tools + Flux Kontext pipe |
| `OLLAMA_BASE_URL` | All tools with model unloading |
| `SEARXNG_IMAGE_SEARCH_URL` | SearXNG Image Search tool |
| `WEBUI_URL` | Native Image Gen tool (image links) |
| `OPENROUTER_API_KEY` | OpenRouter Image pipe |
| `OPENAI_API_KEYS` | OpenAI, OpenRouter and Anthropic connection keys (fresh-install seed) |

### API Keys (commented out — uncomment when needed)

| Variable | Tool | Where to Get It |
|----------|------|-----------------|
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

> **Automated:** All tool Python files are pushed via `tools-init` on every deploy. Tools that reference env vars (e.g. `COMFYUI_API_URL`, `OLLAMA_BASE_URL`) pick up their defaults from `env/owui.env`.
>
> **Manual:** Tools that depend on external services (Perplexica, image backends) need their Valves configured in the Admin Panel to point to the correct endpoints.

<table>
<tr>
<td valign="top" width="50%">

#### Perplexica Search Tool
- Same Perplexica instance as the pipe
- Set `BASE_URL`, `CHAT_MODEL`, `EMBEDDING_MODEL` in Valves

#### SearXNG Image Search
- SearXNG endpoint is set in the tool's Valve (default: `http://searxng:8080/search`)
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
<img src="https://img.shields.io/badge/manual-upstream_pull_%2B_host_patching-FF9800?style=flat-square" alt="Pull + patch manual"/>

> **Automated:** `tools-init` pushes whatever is in `conf/tools/` on every deploy — no manual upload needed after syncing files locally.
>
> **Manual:** Pulling from upstream and patching the hardcoded service hosts in Valve defaults must be done locally before deploying.

The tools are sourced from the [Haervwe/open-webui-tools](https://github.com/Haervwe/open-webui-tools) repository.

Upstream ships the ComfyUI and Ollama endpoints as **hardcoded host literals** in the
Valve defaults (e.g. `default="http://localhost:8188"`). After syncing (copying files
from upstream to `conf/tools/`), patch those defaults to read from the environment so a
single value in `env/owui.env` drives every tool:

```python
# upstream:
default="http://localhost:8188"
# patched:
default=os.getenv("COMFYUI_API_URL", "http://localhost:8188")
```

Do the same for API keys (`default=os.getenv("PEXELS_API_KEY", "")`) and add `import os`
where missing.

> **Env vars used in tool Valve defaults:**
> `COMFYUI_API_URL`, `COMFYUI_API_KEY`, `OLLAMA_BASE_URL`, `SEARXNG_IMAGE_SEARCH_URL`, `WEBUI_URL`,
> `OPENROUTER_API_KEY`, `YOUTUBE_API_KEY`, `PEXELS_API_KEY`, `HF_API_KEY`,
> `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `OPENWEATHERMAP_API_KEY`, `TAVILY_API_KEY`, `RAPIDAPI_KEY`

> **Open WebUI compatibility:** the bundled tools target **Open WebUI 0.12** (the pinned `OWUI_TAG`).
