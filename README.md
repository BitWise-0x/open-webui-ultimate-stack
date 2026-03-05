<h1 align="center">
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Open_WebUI-000000?style=for-the-badge&logo=openai&logoColor=white" alt="Open WebUI"/>
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
  <img src="https://img.shields.io/badge/Redis-FF4438?style=for-the-badge&logo=redis&logoColor=white" alt="Redis"/>
  <br>
  <code>open-webui-ultimate-stack</code>
</h1>

<p align="center">
  <img src="https://img.shields.io/github/license/BitWise-0x/open-webui-ultimate-stack?style=flat-square&color=blue" alt="License"/>
  <img src="https://img.shields.io/github/last-commit/BitWise-0x/open-webui-ultimate-stack?style=flat-square&color=green" alt="Last Commit"/>
  <img src="https://img.shields.io/github/repo-size/BitWise-0x/open-webui-ultimate-stack?style=flat-square&color=orange" alt="Repo Size"/>
</p>

<p align="center">
  Production-grade Open WebUI deployment with RAG, private web search, OCR, local TTS, and MCP tool servers.<br>
  Ships as both a standalone <code>docker-compose.yml</code> and a production Docker Swarm <code>docker-stack-compose.yml</code>.<br>
  Comes pre-loaded with a curated library of tools, filters, and function pipes — automatically slipstreamed into Open WebUI on every deploy.
</p>

---

## Quick Start

```bash
git clone https://github.com/BitWise-0x/open-webui-ultimate-stack && cd open-webui-ultimate-stack && ./bootstrap.sh
```

The bootstrap script copies env examples, generates random secrets, prompts for optional keys, and starts the stack.
Open WebUI will be available at **http://localhost:3000** once all containers are healthy.

---

## Architecture

```mermaid
flowchart TD
    User(["User / Browser"])
    Traefik(["Traefik\nReverse Proxy"])

    subgraph Stack ["open-webui-ultimate-stack"]
        direction TB

        OW["<b>openwebui</b>\nghcr.io/open-webui/open-webui:main\n:8080"]
        DB["<b>db</b>\npgvector/pgvector:pg17\n:5432"]
        Redis["<b>redis</b>\nvalkey/valkey:8-alpine\n:6379"]
        SearXNG["<b>searxng</b>\nsearxng/searxng\n:8080"]
        Tika["<b>tika</b>\napache/tika:full\n:9998"]
        EdgeTTS["<b>edgetts</b>\nopenai-edge-tts\n:5050"]
        MCP["<b>mcposerver</b>\nghcr.io/open-webui/mcpo\n:8000"]
        ToolsInit["<b>tools-init</b>\npython:3.12-slim\none-shot"]

        OW --> DB
        OW --> Redis
        OW --> SearXNG
        OW --> Tika
        OW --> EdgeTTS
        OW --> MCP
        MCP --> DB
        SearXNG --> Redis
        ToolsInit -->|"push tools/filters/\nfunctions via API"| OW
    end

    User --> Traefik --> OW
    Traefik -.->|"/searxng subpath"| SearXNG
```

---

## Services

<table>
<tr>
<td width="50%" valign="top">

### Core
<img src="https://img.shields.io/badge/Open_WebUI-main-000000?style=flat-square&logo=openai&logoColor=white" alt="Open WebUI"/>
<img src="https://img.shields.io/badge/PostgreSQL-pgvector_pg17-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
<img src="https://img.shields.io/badge/Valkey-8--alpine-FF4438?style=flat-square&logo=redis&logoColor=white" alt="Valkey"/>

- **openwebui** — full-featured AI chat UI with RAG, tools, pipelines, and multi-model routing
- **db** — PostgreSQL 17 with pgvector for vector embeddings and semantic search
- **redis** — Valkey (Redis-compatible) for WebSocket session management and caching

</td>
<td width="50%" valign="top">

### Search & Documents
<img src="https://img.shields.io/badge/SearXNG-2025.7.10-EF5350?style=flat-square" alt="SearXNG"/>
<img src="https://img.shields.io/badge/Apache_Tika-3.2.2.0--full-009688?style=flat-square" alt="Tika"/>

- **searxng** — private metasearch engine aggregating 70+ sources with no tracking
- **tika** — Apache Tika with Tesseract OCR for extracting text from PDFs, images, and Office docs

</td>
</tr>
<tr>
<td width="50%" valign="top">

### AI Integrations
<img src="https://img.shields.io/badge/edge--tts-OpenAI_compatible-4CAF50?style=flat-square" alt="EdgeTTS"/>
<img src="https://img.shields.io/badge/MCPO-MCP_proxy-7C3AED?style=flat-square" alt="MCPO"/>

- **edgetts** — local text-to-speech server (Microsoft Edge voices, OpenAI-compatible API)
- **mcposerver** — MCP to OpenAPI proxy; exposes MCP tool servers as REST endpoints consumable by Open WebUI

</td>
<td width="50%" valign="top">

### Automation
<img src="https://img.shields.io/badge/Python-3.12--slim-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python"/>

- **tools-init** — one-shot init container that waits for Open WebUI health, then automatically pushes the entire `conf/tools/` library — filters, tools, and function pipes — via the internal REST API with upsert support
- Re-runs on every deploy; new tools are added, existing ones are updated

</td>
</tr>
</table>

---

## Tools & Extensions

Every deploy automatically slipstreams a curated library of tools, pipeline filters, and function pipes directly into Open WebUI — no manual imports, no copy-paste. The `tools-init` container handles it all at startup via the internal API.

<table>
<tr>
<td width="50%" valign="top">

### Filters
Pipeline filters that run on every message — pre- or post-process input/output transparently.

- `clean_thinking_tags_filter` — strips `<think>` blocks from model responses
- `full_document_filter` — injects full document context into the prompt
- `prompt_enhancer_filter` — rewrites user prompts for sharper results
- `semantic_router_filter` — intelligently routes queries to the best model
- `doodle_paint_filter` — injects artistic style directives
- `openrouter_websearch_citations_filter` — formats and surfaces OpenRouter web search citations

</td>
<td width="50%" valign="top">

### Tools
Native tool-use extensions the model can call during a conversation.

- `arxiv_search_tool` — search and retrieve academic papers from arXiv
- `wiki_search_tool` — Wikipedia search and summary
- `searxng_image_search_tool` — image search via the local SearXNG instance
- `comfyui_text_to_image_tool` — text-to-image generation via ComfyUI
- `comfyui_image_to_image_tool` — image editing and transformation via ComfyUI
- `comfyui_ace_step_audio_tool` — AI audio generation via ComfyUI
- `comfyui_vibevoice_tts_tool` — expressive voice TTS via ComfyUI VibeVoice
- `text_to_video_comfyui_tool` — text-to-video via ComfyUI Wan2.1
- `youtube_search_tool` — YouTube search and metadata
- `pexels_image_search_tool` — Pexels royalty-free image search
- `openweathermap_forecast_tool` — live weather forecasts
- `native_image_gen` — built-in Open WebUI image generation
- `create_image_hf` — image generation via Hugging Face Inference API
- `create_image_cf` — image generation via Cloudflare Workers AI
- `philosopher_api_tool` — philosophical reasoning and quotes
- `rpg_tool_set` — RPG dice, character generation, and game utilities

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Function Pipes
Full pipeline functions that replace or augment the model's response loop.

- `planner` — multi-step task decomposition and planning
- `multi_model_conversation_v2` — run parallel conversations across multiple models simultaneously
- `research_pipe` — deep multi-source research pipeline
- `openrouter_image_pipe` — image generation routing via OpenRouter
- `flux_kontext_comfyui_pipe` — Flux Kontext image editing pipeline via ComfyUI
- `veo3_pipe` — video generation pipeline
- `resume` — resume analysis and career coaching pipeline

</td>
<td width="50%" valign="top">

### ComfyUI Workflows (`extras/`)
Pre-built ComfyUI API workflow JSONs ready to drop into your ComfyUI instance for use with the bundled tools.

- Flux Kontext image editing
- ACE Step audio generation (v1 + v1.5)
- Vibe Voice TTS (single speaker + multi-speaker)
- Wan2.1 14B text-to-video
- Qwen image editing (standard + 2509 API)

</td>
</tr>
</table>

---

## Repository Structure

```
open-webui-ultimate-stack/
├── docker-compose.yml           Standalone — local / single-host
├── docker-stack-compose.yml     Docker Swarm — production
├── .env.example                 Top-level swarm variables (copy → .env)
├── .gitignore
├── bootstrap.sh                 Interactive local startup wizard
├── scripts/
│   ├── deploy-swarm.sh          Swarm deploy helper
│   └── install-tools.sh         Init container: auto-push tools via API
├── conf/
│   ├── searxng/                 settings.yml, uwsgi.ini, limiter.toml
│   ├── tika/                    tika-config.xml + OCR properties
│   ├── mcposerver/              config.json (MCP server definitions)
│   ├── postgres/init/           Custom entrypoint + pgvector init
│   └── tools/
│       ├── filters/             Python pipeline filters (auto-deployed)
│       ├── tools/               Python tool definitions (auto-deployed)
│       ├── functions/           Python pipes and functions (auto-deployed)
│       └── extras/              ComfyUI API workflow JSONs
├── env/                         Per-service env.example files
│   ├── owui.env.example
│   ├── db.env.example
│   ├── redis.env.example
│   ├── edgetts.env.example
│   ├── mcp.env.example
│   ├── searxng.env.example
│   ├── tika.env.example
│   └── tools-init.env.example
└── README.md
```

---

## Configuration

All sensitive values live in `env/` files that are git-ignored. The `.example` variants are tracked and serve as templates.

```bash
# Initial setup (done automatically by bootstrap.sh)
for f in env/*.env.example; do cp "$f" "${f%.example}"; done
```

| File | Purpose |
|------|---------|
| `env/owui.env` | Open WebUI — LLM keys, RAG, websocket, TTS, image gen, permissions |
| `env/db.env` | PostgreSQL credentials |
| `env/redis.env` | Valkey notes (no required vars) |
| `env/searxng.env` | SearXNG secret, workers, base URL mode |
| `env/tika.env` | Tika version tag |
| `env/edgetts.env` | Default voice, speed, format |
| `env/mcp.env` | Reference DATABASE_URL for mcpo |
| `env/tools-init.env` | OWUI API key and URL for tool push |

**Secrets to generate before starting:**

```bash
# WEBUI_SECRET_KEY and SEARXNG_SECRET
openssl rand -hex 32

# POSTGRES_PASSWORD
openssl rand -base64 24
```

---

## Deployment

### Standalone (local / single host)

```bash
./bootstrap.sh
```

Or manually:

```bash
for f in env/*.env.example; do cp "$f" "${f%.example}"; done
# edit env/owui.env — set WEBUI_SECRET_KEY, OPENAI_API_KEY, etc.
docker compose up -d
```

Access:
- Open WebUI → http://localhost:3000
- SearXNG → http://localhost:8888

### Docker Swarm (production)

**Prerequisites:** Traefik deployed with `traefik-public` overlay network and `chain-oauth@file` middleware.

```bash
cp .env.example .env
# edit .env — set ROUTER_NAME, ROOT_DOMAIN, DATA_ROOT, DB_NODE_HOSTNAME
for f in env/*.env.example; do cp "$f" "${f%.example}"; done
# edit env/owui.env, env/db.env, etc. — fill real values

./scripts/deploy-swarm.sh
```

Monitor:

```bash
docker stack ps open-webui
docker service logs -f open-webui_openwebui
```

Remove stack:

```bash
docker stack rm open-webui
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
