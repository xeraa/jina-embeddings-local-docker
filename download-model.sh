#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="./models"
SIZE="${1:-nano}"

case "$SIZE" in
    nano)
        REPO="jinaai/jina-embeddings-v5-text-nano-retrieval"
        FILE="v5-nano-retrieval-F16.gguf"
        ;;
    small)
        REPO="jinaai/jina-embeddings-v5-text-small-retrieval"
        FILE="v5-small-retrieval-F16.gguf"
        ;;
    *)
        echo "Unknown model size: $SIZE"
        echo "Usage: $0 [nano|small]"
        exit 1
        ;;
esac

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/$FILE" ]; then
    echo "Model already exists at $MODEL_DIR/$FILE — skipping download."
    exit 0
fi

echo "Downloading $FILE from huggingface.co/$REPO ..."
curl -L --progress-bar -C - "https://huggingface.co/$REPO/resolve/main/$FILE" -o "$MODEL_DIR/$FILE.part"
mv "$MODEL_DIR/$FILE.part" "$MODEL_DIR/$FILE"
echo "Done. Model saved to $MODEL_DIR/$FILE"
