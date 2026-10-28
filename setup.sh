#!/usr/bin/env bash
# EditStudio: prepara a máquina do Claude Code na web (Ubuntu 24.04, x86_64) para editar vídeos com o kit.
# Serve de script de preparação do ambiente (fica em cache) e corre também no arranque de cada sessão, onde salta o
# que já está feito. Só usa sites da lista "Trusted": GitHub, PyPI, npm, Ubuntu e storage.googleapis.com.
# Os modelos descarregados são confirmados pela soma SHA-256 antes de serem usados.
# Uso: bash editstudio-setup.sh [pasta com o package.json e o package-lock.json do kit]
# No fim escreve uma linha "FALTA ..." por cada peça que não ficou instalada (sai sempre com 0: um erro aqui não pode
# impedir a sessão de arrancar).
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
PKG="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE=/opt/editstudio
CACHE="$HOME/.cache/edicao-automatica"
VENV="$HOME/.venvs/edicao"
# Modelos de transcrição e de rosto: release pública do CoreBuildPt/editstudio-setup (modelos open-source, licença MIT).
# Se o download direto falhar, tenta pelo gh (no arranque da sessão passa pelo proxy do GitHub do Claude Code).
TAG=modelos-v1
REPO=CoreBuildPt/editstudio-setup
REL="${EDITSTUDIO_MODELOS_URL:-https://github.com/$REPO/releases/download/$TAG}"
FF=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n9.0-latest-linux64-gpl-9.0.tar.xz
RVM=https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx
PIP="faster-whisper==1.2.1 ctranslate2==4.8.3 av==19.0.2 numpy==2.5.4 onnxruntime==1.31.0 opencv-python-headless==4.14.0.94"
mkdir -p "$BASE" "$CACHE/whisper" "$CACHE/modelos"
log() { echo "[editstudio] $*"; }
tamanho() { stat -c %s "$1" 2>/dev/null || echo 0; }

confere() { echo "$2  $1" | sha256sum -c --status 2>/dev/null; }

# url destino sha256: descarrega só se faltar ou não bater certo
baixa() {
  confere "$2" "$3" && return 0
  curl -fsSL --retry 3 -o "$2.parcial" "$1" && confere "$2.parcial" "$3" && mv "$2.parcial" "$2" && return 0
  rm -f "$2.parcial"; return 1
}

# ficheiro-da-release destino sha256: do link público, se houver, senão da release privada do kit
obtem() {
  confere "$2" "$3" && return 0
  { [ -n "$REL" ] && baixa "$REL/$1" "$2" "$3"; } && return 0
  command -v gh >/dev/null || return 1
  rm -f "$2.parcial"
  gh release download "$TAG" --repo "$REPO" --pattern "$1" --output "$2.parcial" --clobber >/dev/null 2>&1 &&
    confere "$2.parcial" "$3" && mv "$2.parcial" "$2" && return 0
  rm -f "$2.parcial"; log "não consegui $1 (ou a assinatura não bate certo)"; return 1
}

ffmpeg_ok() { ffmpeg -hide_banner -version 2>/dev/null | head -1 | grep -Eq 'version n?9\.'; }
passo_ffmpeg() {
  ffmpeg_ok && return 0
  log "ffmpeg 9"
  local t; t=$(mktemp -d)
  curl -fsSL --retry 3 "$FF" | tar -xJ -C "$t" && install -m 755 "$t"/ffmpeg-*/bin/ffmpeg "$t"/ffmpeg-*/bin/ffprobe /usr/local/bin/
  rm -rf "$t"
}

LIBS="libgbm1 libnss3 libatk-bridge2.0-0t64 libdrm2 libxcomposite1 libxdamage1 libxrandr2 libcups2t64 libasound2t64 libpangocairo-1.0-0 libxshmfence1 libgtk-3-0t64 fonts-liberation fonts-noto-color-emoji fontconfig"
passo_libs() {
  # shellcheck disable=SC2086
  dpkg -s $LIBS >/dev/null 2>&1 && return 0
  log "bibliotecas do Chrome"
  # shellcheck disable=SC2086
  apt-get update -qq && apt-get install -y -qq --no-install-recommends $LIBS >/dev/null && fc-cache -f >/dev/null
}

python_ok() { "$VENV/bin/python" -c "import faster_whisper, cv2, onnxruntime, numpy" 2>/dev/null; }
passo_python() {
  python_ok && return 0
  log "Python (faster-whisper)"
  # shellcheck disable=SC2086
  if command -v uv >/dev/null; then
    uv venv -q "$VENV" --python python3 && uv pip install -q --python "$VENV/bin/python" $PIP
  else
    python3 -m venv "$VENV" && "$VENV/bin/pip" install -q $PIP
  fi
}

declare -A WHISPER=([small]=483546902 [medium]=1527906378)
declare -A WHISPER_SHA=([small]=0f29dec70296d97e4eeeb0b4295728b2973dc18429d880aad40025d581ade1dd [medium]=14e40f5d6fd1daf327bb0af1965041d2158e86321ab7ab3281c5e589fcb1077d)
passo_modelos() {
  for m in small medium; do
    [ "$(tamanho "$CACHE/whisper/$m/model.bin")" = "${WHISPER[$m]}" ] && continue
    log "modelo de transcrição $m"
    obtem "whisper-$m.tar" "$CACHE/whisper-$m.tar" "${WHISPER_SHA[$m]}" &&
      tar -xf "$CACHE/whisper-$m.tar" -C "$CACHE/whisper" && rm -f "$CACHE/whisper-$m.tar"
  done
  obtem face_detection_yunet_2023mar.onnx "$CACHE/modelos/face_detection_yunet_2023mar.onnx" 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
  baixa "$RVM" "$CACHE/modelos/rvm_mobilenetv3_fp32.onnx" 88d4531297118f595bf2fd60f6f566aec2e559393802d1f436c380f0cbbd2828
}

node_ok() { [ -f "$BASE/node_modules/.editstudio-ok" ] && cmp -s "$PKG/package-lock.json" "$BASE/package-lock.json"; }
passo_node() {
  if ! node_ok; then
    log "HyperFrames (npm)"
    cp "$PKG/package.json" "$PKG/package-lock.json" "$BASE/" && rm -f "$BASE/node_modules/.editstudio-ok" &&
      (cd "$BASE" && npm ci --no-audit --no-fund --loglevel=error) && touch "$BASE/node_modules/.editstudio-ok"
  fi
  # o Chrome que o HyperFrames usa para desenhar (vem de storage.googleapis.com)
  (cd "$BASE" && HYPERFRAMES_NO_TELEMETRY=1 HYPERFRAMES_NO_UPDATE_CHECK=1 npx --no-install hyperframes browser ensure >/dev/null 2>&1)
}

# as peças independentes correm ao mesmo tempo (o cache do ambiente só é guardado se tudo acabar em ~5 minutos)
passo_libs & L=$!
passo_python & P=$!
passo_modelos & M=$!
passo_node & N=$!
passo_ffmpeg
wait $L $P $M $N
# sem o ffmpeg 9 (GitHub em baixo), o do Ubuntu também serve
ffmpeg_ok || command -v ffmpeg >/dev/null || { log "ffmpeg do Ubuntu"; apt-get install -y -qq ffmpeg >/dev/null; }

command -v ffmpeg >/dev/null || echo "FALTA ffmpeg"
python_ok || echo "FALTA python"
for m in small medium; do [ "$(tamanho "$CACHE/whisper/$m/model.bin")" = "${WHISPER[$m]}" ] || echo "FALTA whisper-$m"; done
[ -f "$BASE/node_modules/.editstudio-ok" ] || echo "FALTA hyperframes"
(cd "$BASE" && npx --no-install hyperframes browser path >/dev/null 2>&1) || echo "FALTA chrome"
log "preparação terminada"
exit 0
