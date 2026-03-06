#!/usr/bin/env bash

set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: ./compile.sh [options]

Build targets (default is demo executable):
  --lib             No-op (header-only library; no library artifact is built)
  --demo            Build msbg_demo executable (default)
  --all             Build default make target

General options:
  --debug           Build with debug flags
  --release         Build with release flags (default)
  --build-dir DIR   Build output directory (default: build)
  --arch ARCH       Target architecture: native|x86_64|arm64 (default: native)
  --jobs N          Parallel build jobs (default: auto)
  --clean           Remove previous build artifacts in build-dir before build
  --openmp          Require OpenMP support (error if unavailable)
  --no-openmp       Disable OpenMP
  --tbb-fallback    Force built-in sequential TBB fallback
  --no-png          Disable PNG support (BmpWritePNG returns MI_ENOTIMPL)
  --no-jpeg         Disable JPEG support (BmpSaveBitmapJPG returns MI_ENOTIMPL)
  -h, --help        Show this help

Environment overrides:
  CC, CXX, AR, SSE2NEON_HEADER
USAGE
}

normalize_arch() {
  case "$1" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "$1" ;;
  esac
}

detect_jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    local ncpu
    ncpu="$(sysctl -n hw.ncpu 2>/dev/null || true)"
    if [[ -n "$ncpu" ]]; then
      echo "$ncpu"
    else
      echo 4
    fi
  else
    echo 4
  fi
}

join_by_space() {
  local IFS=' '
  echo "$*"
}

BUILD_MODE="demo"
BUILD_TYPE="release"
BUILD_DIR="build"
TARGET_ARCH_INPUT="native"
TARGET_ARCH_EXPLICIT=0
CLEAN_BUILD=0
OPENMP_MODE="auto"
FORCE_TBB_FALLBACK=0
DISABLE_PNG=0
DISABLE_JPEG=0
JOBS="$(detect_jobs)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lib)
      BUILD_MODE="lib"
      ;;
    --demo)
      BUILD_MODE="demo"
      ;;
    --all)
      BUILD_MODE="all"
      ;;
    --debug)
      BUILD_TYPE="debug"
      ;;
    --release)
      BUILD_TYPE="release"
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift
      ;;
    --arch)
      TARGET_ARCH_INPUT="$2"
      TARGET_ARCH_EXPLICIT=1
      shift
      ;;
    --jobs)
      JOBS="$2"
      shift
      ;;
    --clean)
      CLEAN_BUILD=1
      ;;
    --openmp)
      OPENMP_MODE="on"
      ;;
    --no-openmp)
      OPENMP_MODE="off"
      ;;
    --tbb-fallback)
      FORCE_TBB_FALLBACK=1
      ;;
    --no-png)
      DISABLE_PNG=1
      ;;
    --no-jpeg)
      DISABLE_JPEG=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

# Header-only library mode does not require any architecture/toolchain probing.
if [[ "$BUILD_MODE" == "lib" ]]; then
  echo "[msbg] header-only mode: no libmsbg.a build is required."
  exit 0
fi

HOST_OS="$(uname -s)"
HOST_ARCH="$(normalize_arch "$(uname -m)")"
TARGET_ARCH="$(normalize_arch "$TARGET_ARCH_INPUT")"
if [[ "$TARGET_ARCH" == "native" ]]; then
  TARGET_ARCH="$HOST_ARCH"
fi

CC_BIN="${CC:-}"
CXX_BIN="${CXX:-}"
AR_BIN="${AR:-ar}"

if [[ -z "$CC_BIN" ]]; then
  if [[ "$HOST_OS" == "Darwin" ]]; then
    CC_BIN="clang"
  else
    CC_BIN="gcc"
  fi
fi
if [[ -z "$CXX_BIN" ]]; then
  if [[ "$HOST_OS" == "Darwin" ]]; then
    CXX_BIN="clang++"
  else
    CXX_BIN="g++"
  fi
fi

ARCH_CFLAGS=()
ARCH_LDFLAGS=()
EXTRA_INCLUDE_FLAGS=()
EXTRA_LIB_FLAGS=()
FEATURE_DEFS=()
FALLBACK_X86_ON_ARM=0

if [[ "$HOST_OS" == "Darwin" ]]; then
  if [[ "$TARGET_ARCH" != "x86_64" && "$TARGET_ARCH" != "arm64" ]]; then
    echo "Unsupported macOS target architecture: $TARGET_ARCH" >&2
    exit 1
  fi
fi

if [[ "$TARGET_ARCH" == "arm64" ]]; then
  SSE2NEON_HEADER_PATH=""
  if [[ -n "${SSE2NEON_HEADER:-}" && -f "${SSE2NEON_HEADER}" ]]; then
    SSE2NEON_HEADER_PATH="${SSE2NEON_HEADER}"
  elif [[ -f "/usr/local/include/sse2neon.h" ]]; then
    SSE2NEON_HEADER_PATH="/usr/local/include/sse2neon.h"
  elif [[ -f "/opt/homebrew/include/sse2neon.h" ]]; then
    SSE2NEON_HEADER_PATH="/opt/homebrew/include/sse2neon.h"
  fi

  if [[ -n "$SSE2NEON_HEADER_PATH" ]]; then
    FEATURE_DEFS+=("-DMSBG_USE_SSE2NEON" "-DINSTRSET=2" "-DMAX_VECTOR_SIZE=256")
    ARCH_CFLAGS+=("-include" "$SSE2NEON_HEADER_PATH")
  elif [[ "$HOST_OS" == "Darwin" && "$HOST_ARCH" == "arm64" && "$TARGET_ARCH_EXPLICIT" -eq 0 ]]; then
    # Automatic host fallback: build x86_64 binary on Apple Silicon when SSE2NEON is unavailable.
    TARGET_ARCH="x86_64"
    FALLBACK_X86_ON_ARM=1
    DISABLE_PNG=1
    DISABLE_JPEG=1
    OPENMP_MODE="off"
    echo "[msbg] sse2neon.h not found; falling back to x86_64 build on Apple Silicon." >&2
    echo "[msbg] PNG/JPEG fallbacks are enabled for portability in this mode." >&2
  else
    echo "ARM64 build requires sse2neon.h. Set SSE2NEON_HEADER or install it in /usr/local/include." >&2
    exit 1
  fi
fi

if [[ "$HOST_OS" == "Darwin" ]]; then
  ARCH_CFLAGS+=("-arch" "$TARGET_ARCH")
  ARCH_LDFLAGS+=("-arch" "$TARGET_ARCH")
else
  if [[ "$TARGET_ARCH" == "x86_64" ]]; then
    ARCH_CFLAGS+=("-m64")
    ARCH_LDFLAGS+=("-m64")
  fi
fi

if [[ "$TARGET_ARCH" == "x86_64" || "$TARGET_ARCH" == "arm64" ]]; then
  CFLAGS_BW_VALUE="-DMI_WITH_64BIT"
else
  CFLAGS_BW_VALUE=""
fi

if [[ "$BUILD_TYPE" == "debug" ]]; then
  CFLAGS_OPT_VALUE="-O0 -g"
else
  CFLAGS_OPT_VALUE="-O3 -DNDEBUG"
fi

if [[ "$HOST_OS" == "Darwin" && "$FORCE_TBB_FALLBACK" -eq 0 ]]; then
  if command -v brew >/dev/null 2>&1; then
    BREW_TBB_PREFIX="$(brew --prefix tbb 2>/dev/null || true)"
    if [[ -n "$BREW_TBB_PREFIX" && -d "$BREW_TBB_PREFIX/include/tbb" ]]; then
      if [[ "$TARGET_ARCH" == "$HOST_ARCH" ]]; then
        EXTRA_INCLUDE_FLAGS+=("-I$BREW_TBB_PREFIX/include")
        EXTRA_LIB_FLAGS+=("-L$BREW_TBB_PREFIX/lib")
        echo "[msbg] using Homebrew tbb from $BREW_TBB_PREFIX" >&2
      else
        echo "[msbg] Homebrew tbb found at $BREW_TBB_PREFIX but skipped for cross-arch target $TARGET_ARCH." >&2
      fi
    fi
  fi

  if [[ "$TARGET_ARCH" == "x86_64" && -d "/usr/local/opt/tbb/include/tbb" ]]; then
    EXTRA_INCLUDE_FLAGS+=("-I/usr/local/opt/tbb/include")
    EXTRA_LIB_FLAGS+=("-L/usr/local/opt/tbb/lib")
    echo "[msbg] probing x86_64 Homebrew tbb from /usr/local/opt/tbb" >&2
  fi
fi

if [[ "$FALLBACK_X86_ON_ARM" -eq 0 ]]; then
  for prefix in /opt/homebrew /usr/local; do
    if [[ -d "$prefix/include" ]]; then
      EXTRA_INCLUDE_FLAGS+=("-I$prefix/include")
    fi
    if [[ -d "$prefix/lib" ]]; then
      EXTRA_LIB_FLAGS+=("-L$prefix/lib")
    fi
  done
fi

if [[ "$FORCE_TBB_FALLBACK" -eq 0 ]]; then
  TMP_TBB_CPP="$(mktemp /tmp/msbg_tbb_test.XXXXXX.cpp)"
  TMP_TBB_BIN="$(mktemp /tmp/msbg_tbb_bin.XXXXXX)"
  cat > "$TMP_TBB_CPP" <<'TBBC'
#include <tbb/tbb.h>
int main() { return tbb::this_task_arena::max_concurrency() > 0 ? 0 : 1; }
TBBC

  if ! "$CXX_BIN" "${ARCH_CFLAGS[@]}" "${EXTRA_INCLUDE_FLAGS[@]}" "$TMP_TBB_CPP" "${EXTRA_LIB_FLAGS[@]}" -ltbb -o "$TMP_TBB_BIN" >/dev/null 2>&1; then
    FORCE_TBB_FALLBACK=1
    echo "[msbg] oneTBB not linkable for target ${TARGET_ARCH}; using internal fallback." >&2
  fi
  rm -f "$TMP_TBB_CPP" "$TMP_TBB_BIN"
fi

if [[ "$FORCE_TBB_FALLBACK" -eq 1 ]]; then
  FEATURE_DEFS+=("-DMSBG_TBB_FORCE_FALLBACK")
fi
if [[ "$DISABLE_PNG" -eq 1 ]]; then
  FEATURE_DEFS+=("-DMSBG_DISABLE_PNG")
fi
if [[ "$DISABLE_JPEG" -eq 1 ]]; then
  FEATURE_DEFS+=("-DMSBG_DISABLE_JPEG")
fi

OMP_CFLAGS_VALUE=""
OMP_LIB_VALUE=""
if [[ "$OPENMP_MODE" != "off" ]]; then
  TMP_C_FILE="$(mktemp /tmp/msbg_omp_test.XXXXXX.c)"
  TMP_BIN_FILE="$(mktemp /tmp/msbg_omp_bin.XXXXXX)"
  cat > "$TMP_C_FILE" <<'OMPC'
#include <omp.h>
int main(void) { return omp_get_max_threads() > 0 ? 0 : 1; }
OMPC

  if "$CC_BIN" "${ARCH_CFLAGS[@]}" -fopenmp "$TMP_C_FILE" -o "$TMP_BIN_FILE" >/dev/null 2>&1; then
    OMP_CFLAGS_VALUE="-fopenmp"
    OMP_LIB_VALUE="-fopenmp"
  elif [[ "$HOST_OS" == "Darwin" ]]; then
    OMP_PREFIXES=()
    if command -v brew >/dev/null 2>&1; then
      BREW_OMP_PREFIX="$(brew --prefix libomp 2>/dev/null || true)"
      if [[ -n "$BREW_OMP_PREFIX" ]]; then
        OMP_PREFIXES+=("$BREW_OMP_PREFIX")
      fi
    fi
    OMP_PREFIXES+=("/opt/homebrew" "/usr/local")

    for omp_prefix in "${OMP_PREFIXES[@]}"; do
      if [[ -f "$omp_prefix/include/omp.h" ]]; then
        if "$CC_BIN" "${ARCH_CFLAGS[@]}" -Xpreprocessor -fopenmp \
             -I"$omp_prefix/include" "$TMP_C_FILE" \
             -L"$omp_prefix/lib" -lomp -o "$TMP_BIN_FILE" >/dev/null 2>&1; then
          OMP_CFLAGS_VALUE="-Xpreprocessor -fopenmp -I$omp_prefix/include"
          OMP_LIB_VALUE="-L$omp_prefix/lib -lomp"
          break
        fi
      fi
    done
  fi

  rm -f "$TMP_C_FILE" "$TMP_BIN_FILE"

  if [[ -z "$OMP_CFLAGS_VALUE" && "$OPENMP_MODE" == "on" ]]; then
    echo "OpenMP was explicitly requested but no supported OpenMP toolchain was detected." >&2
    exit 1
  fi
fi

CFLAGS_EXT_VALUE="$(join_by_space "${ARCH_CFLAGS[@]}" "${EXTRA_INCLUDE_FLAGS[@]}" "${FEATURE_DEFS[@]}")"
LDFLAGS_VALUE="$(join_by_space "${ARCH_LDFLAGS[@]}" "${EXTRA_LIB_FLAGS[@]}")"

DEMO_LIBS=("-lz" "-lm")
if [[ "$DISABLE_PNG" -eq 0 ]]; then
  DEMO_LIBS=("-lpng" "${DEMO_LIBS[@]}")
fi
if [[ "$DISABLE_JPEG" -eq 0 ]]; then
  DEMO_LIBS=("-ljpeg" "${DEMO_LIBS[@]}")
fi
if [[ "$FORCE_TBB_FALLBACK" -eq 0 ]]; then
  DEMO_LIBS=("-ltbbmalloc" "-ltbb" "-ltbbmalloc_proxy" "${DEMO_LIBS[@]}")
fi
DEMO_LIBS_VALUE="$(join_by_space "${DEMO_LIBS[@]}")"

case "$BUILD_MODE" in
  lib)
    MAKE_TARGET="libmsbg.a"
    ;;
  demo)
    MAKE_TARGET="msbg_demo"
    ;;
  all)
    MAKE_TARGET="all"
    ;;
  *)
    echo "Invalid build mode: $BUILD_MODE" >&2
    exit 1
    ;;
esac

BUILD_PATH="$ROOT_DIR/$BUILD_DIR"
mkdir -p "$BUILD_PATH"

if [[ "$CLEAN_BUILD" -eq 1 ]]; then
  rm -f "$BUILD_PATH"/*.o "$BUILD_PATH"/*.a "$BUILD_PATH"/*.so "$BUILD_PATH"/msbg_demo "$BUILD_PATH"/msbg_demo.exe
fi

pushd "$BUILD_PATH" >/dev/null

echo "[msbg] host=${HOST_OS}/${HOST_ARCH} target=${TARGET_ARCH} mode=${BUILD_MODE} type=${BUILD_TYPE}"
echo "[msbg] CC=${CC_BIN} CXX=${CXX_BIN} jobs=${JOBS}"

make -f ../makefile \
  OBJE=o \
  CPP_FLAGS="-std=gnu++17" \
  CFLAGS_OPT="$CFLAGS_OPT_VALUE" \
  CFLAGS_PROF= \
  CFLAGS_OMP="$OMP_CFLAGS_VALUE" \
  CFLAGS_TBB="" \
  LIB_OMP="$OMP_LIB_VALUE" \
  CC="$CC_BIN" \
  LD="$CXX_BIN" \
  LDFLAGS_BW= \
  AR="$AR_BIN" \
  CFLAGS_BW="$CFLAGS_BW_VALUE" \
  CFLAGS_EXT="$CFLAGS_EXT_VALUE" \
  LDFLAGS="$LDFLAGS_VALUE" \
  LD_LIBS_FOR_MSBG_DEMO="$DEMO_LIBS_VALUE" \
  -j"$JOBS" \
  "$MAKE_TARGET"

popd >/dev/null

if [[ "$BUILD_MODE" == "lib" || "$BUILD_MODE" == "all" ]]; then
  if [[ -f "$BUILD_PATH/libmsbg.a" ]]; then
    echo "[msbg] built: $BUILD_PATH/libmsbg.a"
  fi
fi
if [[ "$BUILD_MODE" == "demo" || "$BUILD_MODE" == "all" ]]; then
  if [[ -f "$BUILD_PATH/msbg_demo" || -f "$BUILD_PATH/msbg_demo.exe" ]]; then
    echo "[msbg] built demo in: $BUILD_PATH"
  fi
fi
