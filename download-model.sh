#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="./models"
REPO="jinaai/jina-embeddings-v5-text-nano-retrieval"
FILE="v5-nano-retrieval-F16.gguf"
URL="https://huggingface.co/$REPO/resolve/main/$FILE"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/$FILE" ]; then
    echo "Model already exists at $MODEL_DIR/$FILE — skipping download."
    exit 0
fi

echo "Downloading $FILE from huggingface.co/$REPO ..."
curl -L --progress-bar -C - "$URL" -o "$MODEL_DIR/$FILE.part"
mv "$MODEL_DIR/$FILE.part" "$MODEL_DIR/$FILE"
echo "Done. Model saved to $MODEL_DIR/$FILE"
