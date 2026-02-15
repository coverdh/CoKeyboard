#!/bin/bash

# WhisperKit 模型下载脚本
# 用法: ./Scripts/download_whisper_model.sh [model_name]
# 默认模型: openai_whisper-tiny

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/App/Resources/Models"

# 模型名称
MODEL_NAME="${1:-openai_whisper-tiny}"

echo "================================================"
echo "WhisperKit 模型下载脚本"
echo "================================================"
echo "模型名称: $MODEL_NAME"
echo "目标目录: $MODELS_DIR"
echo ""

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# 使用 git 克隆（需要 git-lfs）
echo "检查 git-lfs..."
if ! command -v git-lfs &> /dev/null; then
    echo "正在安装 git-lfs..."
    brew install git-lfs
    git lfs install
fi

echo "正在下载模型（使用 git sparse-checkout）..."
cd "$TEMP_DIR"

# 初始化空仓库
git init -q
git remote add origin https://huggingface.co/argmaxinc/whisperkit-coreml

# 配置 sparse-checkout 只下载需要的模型
git sparse-checkout init
git sparse-checkout set "$MODEL_NAME"

# 拉取 LFS 文件
git lfs install
git pull origin main

# 复制到目标目录
mkdir -p "$MODELS_DIR"
rm -rf "$MODELS_DIR/$MODEL_NAME"
cp -r "$TEMP_DIR/$MODEL_NAME" "$MODELS_DIR/"

echo ""
echo "================================================"
echo "模型下载完成!"
echo "模型路径: $MODELS_DIR/$MODEL_NAME"
echo ""

# 下载 tokenizer 文件（从 OpenAI whisper 仓库）
echo "下载 tokenizer 文件..."
TOKENIZER_MODEL="${MODEL_NAME#openai_whisper-}"  # 提取模型名称，如 tiny
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/tokenizer.json" -o "$MODELS_DIR/$MODEL_NAME/tokenizer.json"
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/vocab.json" -o "$MODELS_DIR/$MODEL_NAME/vocab.json"
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/merges.txt" -o "$MODELS_DIR/$MODEL_NAME/merges.txt"
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/added_tokens.json" -o "$MODELS_DIR/$MODEL_NAME/added_tokens.json"
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/special_tokens_map.json" -o "$MODELS_DIR/$MODEL_NAME/special_tokens_map.json"
curl -sL "https://huggingface.co/openai/whisper-${TOKENIZER_MODEL}/resolve/main/normalizer.json" -o "$MODELS_DIR/$MODEL_NAME/normalizer.json"

# 修改 config.json 中的 _name_or_path 为本地路径，防止运行时下载
echo "修改 config.json 为本地模式..."
if command -v python3 &> /dev/null; then
    cd "$MODELS_DIR/$MODEL_NAME"
    python3 -c "import json; d=json.load(open('config.json')); d['_name_or_path']='./'; json.dump(d, open('config.json','w'))"
fi

echo "模型文件:"
ls -la "$MODELS_DIR/$MODEL_NAME"
echo ""
du -sh "$MODELS_DIR/$MODEL_NAME"
echo "================================================"
