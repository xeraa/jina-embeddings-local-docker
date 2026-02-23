#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="./models"
REPO="jinaai/jina-embeddings-v5-text-nano-retrieval"

if [ $# -gt 0 ]; then
    QUANTS=("$@")
elif [ -f .env ]; then
    QUANTS=("$(sed -n 's/^QUANT=//p' .env || echo F16)")
else
    QUANTS=("F16")
fi

mkdir -p "$MODEL_DIR"

for QUANT in "${QUANTS[@]}"; do
    FILE="v5-nano-retrieval-${QUANT}.gguf"
    URL="https://huggingface.co/$REPO/resolve/main/$FILE"

    if [ -f "$MODEL_DIR/$FILE" ]; then
        echo "Already exists: $FILE — skipping."
        continue
    fi

    echo "Downloading $FILE ..."
    curl -L --progress-bar -C - "$URL" -o "$MODEL_DIR/$FILE.part"
    mv "$MODEL_DIR/$FILE.part" "$MODEL_DIR/$FILE"
    echo "Done: $MODEL_DIR/$FILE"
    echo ""
done

echo "Available quants: F16  Q8_0  Q6_K  Q5_K_M  Q5_K_S  Q4_K_M  Q3_K_M  Q2_K"
echo "Usage: $0 [QUANT...]   e.g. $0 Q4_K_M"
