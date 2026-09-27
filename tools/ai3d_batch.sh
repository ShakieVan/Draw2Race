#!/usr/bin/env bash
# Umgebung wie run.sh der Ocean-3D-Werkstatt, dann Draw2Race-Stapeltreiber (tools/ai3d_batch.py).
set -euo pipefail
# Pfade der lokalen 3D-Werkstatt bzw. dieses Projekts (WSL-Sicht) über Umgebungsvariablen.
PROJECT=${AI3D_WORKSHOP:?AI3D_WORKSHOP setzen (Ordner der lokalen 3D-Werkstatt)}
BASE=/opt/ocean-ai3d
export OCEAN_PROJECT="$PROJECT"
export PYTHONPATH="$BASE/TRELLIS.2:$PROJECT/tools/ai3d"
export CUDA_HOME=/usr/local/cuda-12.4
export PATH="$BASE/venv/bin:$CUDA_HOME/bin:/usr/lib/wsl/lib:$PATH"
export LD_LIBRARY_PATH="/usr/lib/wsl/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
export HF_HOME="$BASE/cache/huggingface"
export TORCH_HOME="$BASE/cache/torch"
export XDG_CACHE_HOME="$BASE/cache"
export TRITON_CACHE_DIR="$BASE/cache/triton"
export TORCH_EXTENSIONS_DIR="$BASE/cache/extensions"
export CUDA_CACHE_PATH="$BASE/cache/cuda"
export FLEX_GEMM_AUTOTUNE_CACHE_PATH="$BASE/cache/flex-gemm/autotune_cache.json"
export GRADIO_TEMP_DIR="$BASE/cache/gradio"
export TMPDIR="$BASE/tmp"
export GRADIO_ANALYTICS_ENABLED=False
export HF_HUB_DISABLE_TELEMETRY=1
export DO_NOT_TRACK=1
export OPENCV_IO_ENABLE_OPENEXR=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export ATTN_BACKEND=flash_attn
export TORCH_CUDA_ARCH_LIST=8.6
export MAX_JOBS=4
export CUDA_VISIBLE_DEVICES=${OCEAN_GPU:-1}
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$HF_HOME" "$GRADIO_TEMP_DIR" "$TMPDIR"
cd "$BASE/TRELLIS.2"
exec python -u "$(dirname "$(readlink -f "$0")")/ai3d_batch.py" "$@"
