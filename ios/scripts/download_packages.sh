#!/usr/bin/env bash
# Fetch the lite iOS source archives into packages/ if they are missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGES="$ROOT/packages"
mkdir -p "$PACKAGES"

fetch() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "[have] $(basename "$dest")"
    return
  fi
  echo "[get]  $(basename "$dest")"
  curl -L --fail --retry 3 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

fetch "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" "$PACKAGES/zlib-1.3.1.tar.gz"
fetch "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz" "$PACKAGES/zstd-1.5.7.tar.gz"
fetch "https://github.com/google/brotli/archive/refs/tags/v1.0.9.tar.gz" "$PACKAGES/brotli-v1.0.9.tar.gz"
fetch "https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz" "$PACKAGES/fmt-12.1.0.tar.gz"
fetch "https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz" "$PACKAGES/eigen-3.4.0.tar.gz"
fetch "https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.50.tar.gz" "$PACKAGES/libpng-1.6.50.tar.gz"
fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/3.1.0.tar.gz" "$PACKAGES/libjpeg-turbo-3.1.0.tar.gz"
fetch "https://download.osgeo.org/libtiff/tiff-4.7.1.tar.gz" "$PACKAGES/tiff-4.7.1.tar.gz"
fetch "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.gz" "$PACKAGES/freetype-2.13.3.tar.gz"
fetch "https://github.com/AcademySoftwareFoundation/Imath/archive/v3.2.2.tar.gz" "$PACKAGES/imath-3.2.2.tar.gz"
fetch "https://github.com/AcademySoftwareFoundation/openexr/archive/v3.3.5.tar.gz" "$PACKAGES/openexr-3.3.5.tar.gz"
fetch "https://github.com/libexpat/libexpat/archive/R_2_7_1.tar.gz" "$PACKAGES/libexpat-R_2_7_1.tar.gz"
fetch "https://github.com/jbeder/yaml-cpp/archive/refs/tags/0.8.0.tar.gz" "$PACKAGES/yaml-cpp-0.8.0.tar.gz"
fetch "https://github.com/imageworks/pystring/archive/refs/tags/v1.1.3.tar.gz" "$PACKAGES/pystring-v1.1.3.tar.gz"
fetch "https://github.com/zlib-ng/minizip-ng/archive/4.0.10.tar.gz" "$PACKAGES/minizip-ng-4.0.10.tar.gz"
fetch "https://github.com/AcademySoftwareFoundation/OpenColorIO/archive/v2.4.2.tar.gz" "$PACKAGES/OpenColorIO-2.4.2.tar.gz"
fetch "https://github.com/uxlfoundation/oneTBB/archive/refs/tags/v2022.1.0.tar.gz" "$PACKAGES/oneTBB-v2022.1.0.tar.gz"
fetch "https://github.com/libsdl-org/SDL/releases/download/release-3.2.22/SDL3-3.2.22.tar.gz" "$PACKAGES/SDL3-3.2.22.tar.gz"
fetch "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.309.tar.gz" "$PACKAGES/Vulkan-Headers-1.4.309.tar.gz"
fetch "https://github.com/google/shaderc/archive/v2025.3.tar.gz" "$PACKAGES/shaderc-v2025.3.tar.gz"
fetch "https://github.com/AcademySoftwareFoundation/OpenImageIO/archive/refs/tags/v3.0.9.1.tar.gz" "$PACKAGES/OpenImageIO-v3.0.9.1.tar.gz"
fetch "https://www.python.org/ftp/python/3.13.7/Python-3.13.7.tar.xz" "$PACKAGES/Python-3.13.7.tar.xz"

echo "Packages ready in $PACKAGES"
