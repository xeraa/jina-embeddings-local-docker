# Jina Embeddings v5 Text Nano (Retrieval) — llama.cpp Docker Setup

Self-hosted embedding server for [jina-embeddings-v5-text-nano-retrieval](https://huggingface.co/jinaai/jina-embeddings-v5-text-nano-retrieval) using llama.cpp.

> **Why a custom build?** This model uses the EuroBERT architecture, which isn't in mainline llama.cpp yet. Both Dockerfiles clone and build from [Jina's fork](https://github.com/jina-ai/llama.cpp/tree/feat-jina-v5-text) that adds support for it.

## Project Structure

```
├── .env                    # QUANT and EMBED_DIMS configuration
├── Dockerfile              # CPU build on debian:bookworm-slim (default)
├── Dockerfile.cuda         # NVIDIA CUDA build on nvidia/cuda runtime
├── docker-compose.yml      # Base service definition (CPU)
├── docker-compose.cuda.yml # Compose override for GPU support
├── download-model.sh       # Downloads GGUF model from HuggingFace
└── models/                 # Model files (created by download script)
```

## Quick Start

```bash
# 1. Edit .env to choose quantization and embedding dimensions
vi .env

# 2. Download the model (reads QUANT from .env)
./download-model.sh

# 3. Build and start the server
docker compose up --build
```

The OpenAI-compatible embedding API will be available at `http://localhost:8080`.

## Configuration via `.env`

Both settings live in `.env`:

```bash
# Quantization (used by docker-compose + download-model.sh)
# Options: F16, Q8_0, Q6_K, Q5_K_M, Q4_K_M, Q3_K_M, Q2_K
QUANT=F16

# Matryoshka embedding dimensions (used when creating ES pipeline + index)
# Options: 32, 64, 128, 256, 512, 768
EMBED_DIMS=768
```

**`QUANT`** controls which GGUF model file the server loads. Changing it requires downloading the new model and restarting:

```bash
# Switch to Q4_K_M
sed -i '' 's/^QUANT=.*/QUANT=Q4_K_M/' .env
./download-model.sh
docker compose up -d
```

**`EMBED_DIMS`** controls the Matryoshka truncation dimension. The server always outputs full 768-dim vectors — truncation happens in the Elasticsearch ingest pipeline. Changing it requires recreating the ES pipeline and index (see Elasticsearch section below).

| Quantization | Model size | Embedding quality |
|-------------|-----------|-------------------|
| F16 | ~424 MB | Full precision |
| Q8_0 | ~215 MB | Near-lossless |
| Q6_K | ~170 MB | Near-lossless |
| Q4_K_M | ~130 MB | Good |

| Dimensions | Storage/doc | Search quality |
|-----------|------------|----------------|
| 768 | ~3 KB | Maximum |
| 256 | ~1 KB | Good tradeoff |
| 128 | ~512 B | Compact |
| 64 | ~256 B | Coarse |

## Usage

Generate embeddings via the `/v1/embeddings` endpoint:

```bash
curl -s http://localhost:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "input": [
      "Query: What is deep learning?",
      "Document: Deep learning is a subset of machine learning that uses neural networks with many layers."
    ]
  }' | jq .
```

**Important:** For the retrieval variant, prefix inputs with `Query: ` or `Document: ` to get proper asymmetric embeddings for search use cases.

## Elasticsearch Integration



Register the inference endpoint, then create a pipeline that prepends `Document: ` at index time and (optionally) truncates embeddings to `EMBED_DIMS`:

```
PUT _inference/text_embedding/jina-local
{
  "service": "openai",
  "service_settings": {
    "api_key": "unused",
    "model_id": "jina-embeddings-v5-text-nano-retrieval",
    "url": "http://host.docker.internal:8080/v1/embeddings",
    "dimensions": 768
  }
}
```

For 768 dims (no truncation needed):

```
PUT _ingest/pipeline/jina-embeddings
{
  "description": "Generate embeddings with jina-embeddings-v5-text-nano-retrieval",
  "processors": [
    {
      "script": {
        "source": "ctx._inference_input = 'Document: ' + ctx.content"
      }
    },
    {
      "inference": {
        "model_id": "jina-local",
        "input_output": {
          "input_field": "_inference_input",
          "output_field": "content_embedding"
        }
      }
    },
    {
      "remove": {
        "field": "_inference_input"
      }
    }
  ]
}
```

For Matryoshka truncation (e.g. 32 dims), add a script processor:

```
PUT _ingest/pipeline/jina-embeddings
{
  "description": "Generate embeddings with jina-embeddings-v5-text-nano-retrieval",
  "processors": [
    {
      "script": {
        "source": "ctx._inference_input = 'Document: ' + ctx.content"
      }
    },
    {
      "inference": {
        "model_id": "jina-local",
        "input_output": {
          "input_field": "_inference_input",
          "output_field": "content_embedding"
        }
      }
    },
    {
      "script": {
        "source": "def dims = 32; def result = []; for (int i = 0; i < dims; i++) { result.add(ctx.content_embedding[i]); } ctx.content_embedding = result;"
      }
    },
    {
      "remove": {
        "field": "_inference_input"
      }
    }
  ]
}
```

Create the index with matching dimensions:

```
PUT jina-demo
{
  "settings": {
    "default_pipeline": "jina-embeddings"
  },
  "mappings": {
    "properties": {
      "content": {
        "type": "text"
      },
      "content_embedding": {
        "type": "dense_vector",
        "dims": 32,
        "similarity": "cosine",
        "index": true
      }
    }
  }
}
```

Add example documents with the `_bulk` API:

```
POST jina-demo/_bulk
{"index":{}}
{"content":"To resolve an out-of-memory error in Kubernetes, increase the resource limits in your pod spec. Set resources.limits.memory to a higher value and redeploy. If the OOMKilled status persists, profile your application's heap usage to find the leak."}
{"index":{}}
{"content":"SSH connections timing out are usually caused by firewalls dropping idle connections. Add ServerAliveInterval 60 to your ~/.ssh/config to send keepalive packets. If using a jump host, ensure the ProxyJump directive is configured correctly."}
{"index":{}}
{"content":"PostgreSQL slow queries can often be fixed by adding appropriate indexes. Run EXPLAIN ANALYZE on the problematic query to identify sequential scans on large tables. Consider partial indexes if only a subset of rows is frequently queried."}
{"index":{}}
{"content":"When a Docker container exits immediately after starting, check the entrypoint and command. Run docker logs <container_id> to see stderr output. Common causes include missing environment variables, incorrect file permissions, or a crashing application process."}
{"index":{}}
{"content":"Rate limiting in API design protects backend services from abuse. Implement it using a token bucket or sliding window algorithm. Return HTTP 429 with a Retry-After header so clients know when to retry."}
{"index":{}}
{"content":"Git merge conflicts occur when two branches modify the same lines. Use git diff to inspect the conflict markers, then manually resolve by choosing the correct version. Run git add on the resolved files and complete the merge with git commit."}
{"index":{}}
{"content":"TLS certificate renewal with Let's Encrypt can be automated using certbot. Set up a cron job or systemd timer to run certbot renew twice daily. The command is idempotent and only renews certificates within 30 days of expiry."}
{"index":{}}
{"content":"To reduce cold start latency in AWS Lambda, minimize the deployment package size, use provisioned concurrency for critical functions, and avoid heavyweight frameworks that increase initialization time."}
{"index":{}}
{"content":"Cross-Origin Resource Sharing errors happen when a browser blocks requests to a different domain. Configure your server to return the Access-Control-Allow-Origin header. For APIs consumed by SPAs, you may also need to allow specific methods and headers via preflight responses."}
{"index":{}}
{"content":"Elasticsearch cluster health turns yellow when replica shards are unassigned. This commonly happens in single-node clusters where replicas have no node to be allocated to. Set number_of_replicas to 0 for development, or add more nodes for production."}
```

Retrieve a document with the embeddings to see the complete outcome:

```
GET jina-demo/_search
{
    "size": 1,
    "fields": [ "content_embedding" ]
}
```

Search with `Query: ` prefix:

```
# "my app keeps getting killed" → should find the Kubernetes OOM doc
POST jina-demo/_search
{
  "size": 2,
  "knn": {
    "field": "content_embedding",
    "query_vector_builder": {
      "text_embedding": {
        "model_id": "jina-local",
        "model_text": "Query: my app keeps getting killed in the cluster"
      }
    }
  }
}

# "database is slow" → should find the PostgreSQL indexing doc
POST jina-demo/_search
{
  "size": 1,
  "knn": {
    "field": "content_embedding",
    "query_vector_builder": {
      "text_embedding": {
        "model_id": "jina-local",
        "model_text": "Query: database queries taking forever"
      }
    }
  }
}

# "HTTPS cert expired" → should find the Let's Encrypt/certbot doc
POST jina-demo/_search
{
  "size": 1,
  "knn": {
    "field": "content_embedding",
    "query_vector_builder": {
      "text_embedding": {
        "model_id": "jina-local",
        "model_text": "Query: our HTTPS certificate expired and the site is down"
      }
    }
  }
}

# "frontend can't talk to the backend" → should find the CORS doc
POST jina-demo/_search
{
  "size": 1,
  "knn": {
    "field": "content_embedding",
    "query_vector_builder": {
      "text_embedding": {
        "model_id": "jina-local",
        "model_text": "Query: frontend app can't call the backend API from the browser"
      }
    }
  }
}

# "serverless function is slow to start" → should find the Lambda cold start doc
POST jina-demo/_search
{
  "size": 1,
  "knn": {
    "field": "content_embedding",
    "query_vector_builder": {
      "text_embedding": {
        "model_id": "jina-local",
        "model_text": "Query: serverless function takes ages on first request"
      }
    }
  }
}
```

## GPU Support (NVIDIA CUDA)

Layer the CUDA override on top of the base compose file:

```bash
docker compose -f docker-compose.yml -f docker-compose.cuda.yml up --build
```

**Prerequisites:** [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) must be installed on the host.

> **Note:** Docker on macOS runs inside a Linux VM with no GPU passthrough. GPU support requires a Linux host with NVIDIA hardware.

## Server Configuration

All llama-server options can be set via `LLAMA_ARG_*` environment variables in `docker-compose.yml`.

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_ARG_MODEL` | from `QUANT` in `.env` | Path to the GGUF model file |
| `LLAMA_ARG_EMBEDDINGS` | `1` | Enable embedding mode (required) |
| `LLAMA_ARG_POOLING` | `last` | Pooling strategy — this model uses last-token pooling |
| `LLAMA_ARG_CTX_SIZE` | `8192` | Max context length (model supports up to 8192) |
| `LLAMA_ARG_BATCH_SIZE` | `8192` | Batch size for prompt processing |
| `LLAMA_ARG_UBATCH_SIZE` | `8192` | Micro-batch size |
| `LLAMA_ARG_N_PARALLEL` | `4` | Number of concurrent request slots |
| `LLAMA_ARG_N_GPU_LAYERS` | `999` | Layers to offload to GPU (CUDA override only) |
| `LLAMA_ARG_PORT` | `8080` | Server port inside the container |

## License

The model is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). For commercial use, contact [sales@jina.ai](mailto:sales@jina.ai).
