#!/bin/sh

patch_minecraft() {
	local dir="$1"
	local minecraft_cfg="$dir/patches/net.minecraft.json"
	if [ -z "$LWJGL_BUILD_VERSION" ]; then
		echo "LWJGL build version not set." > /dev/stderr
		exit 1
	fi
	if [ ! -f "$minecraft_cfg" ]; then
		echo "$dir: Minecraft configuration not found." > /dev/stderr
		return 1
	fi
	"$PATCH_SCRIPT_DIR/patch_minecraft_config.py" \
		version="$LWJGL_BUILD_VERSION" \
		< "$minecraft_cfg" \
		> "$minecraft_cfg.patched" \
		|| return 1
	mv "$minecraft_cfg.patched" "$minecraft_cfg" || return 1
}

patch_lwjgl() {
	local dir="$1"
	local lwjgl_cfg="$dir/patches/org.lwjgl3.json"
	if [ -z "$LWJGL_BUILD_VERSION" ]; then
		echo "LWJGL build version not set." > /dev/stderr
		exit 1
	fi
	if [ -z "$LWJGL_URL_PREFIX" ]; then
		echo "LWJGL URL prefix not set." > /dev/stderr
		exit 1
	fi
	if [ -z "$LWJGL_LINUX_ARCH" ]; then
		echo "LWJGL Linux architecture not set." > /dev/stderr
		exit 1
	fi
	if [ -z "$LWJGL_BUILD_TYPE" ]; then
		echo "LWJGL build type not set." > /dev/stderr
		exit 1
	fi
	if [ ! -f "$lwjgl_cfg" ]; then
		echo "$dir: LWJGL configuration not found." > /dev/stderr
		return 1
	fi
	"$PATCH_SCRIPT_DIR/patch_minecraft_lwjgl_config.py" \
		natives=linux \
		urls \
		url-prefix="$LWJGL_URL_PREFIX" \
		linux-arch=ppc64le \
		version="$LWJGL_BUILD_VERSION" \
		build-type="$LWJGL_BUILD_TYPE" \
		< "$lwjgl_cfg" \
		> "$lwjgl_cfg.patched" \
		|| return 1
	mv "$lwjgl_cfg.patched" "$lwjgl_cfg" || return 1
}

patch_subdir() {
	local dir="$1"
	patch_minecraft "$dir" || return 1
	patch_lwjgl "$dir" || return 1
}

get_lwjgl_version() {
	if [ -z "$LWJGL_URL_PREFIX" ]; then
		echo "LWJGL URL prefix not set." > /dev/stderr
		return 1
	fi
	local build_desc_url="$LWJGL_URL_PREFIX/build.txt"
	local tmpfile="$1"
	if ! wget -O "$tmpfile" "$build_desc_url"; then
		echo "Error getting build description file." > /dev/stderr
		return 1
	fi
	LWJGL_BUILD_VERSION="$(lwjgl_build_version "$(head -n 1 "$tmpfile")")" \
		|| return 1
}

patch_instance() {
	unzip -d "$TMPDIR/" "$INFILE" || return 1
	local dir
	if ! local version_tmpfile=$(mktemp); then
		echo "Error creating temporary file." > /dev/stderr
		exit 1
	fi
	get_lwjgl_version "$version_tmpfile" || return 1
	local status=$?
	rm -f "$version_tmpfile"
	[ $status -eq 0 ] || return 1
	for dir in "$TMPDIR"/*; do
		patch_subdir "$dir" || return 1
	done
	local outfile_realpath=$(realpath "$OUTFILE")
	pushd "$TMPDIR" > /dev/null || return 1
	zip -r "$outfile_realpath" * || return 1
	popd > /dev/null || return 1
}

if [ $# -ne 3 ]; then
	echo "Syntax: $0 <INFILE> <PATCH> <OUTFILE>" > /dev/stderr
	exit 1
fi

SCRIPT_BASEDIR="$(dirname "$(which $0)")"
PATCH_SCRIPT_DIR="$SCRIPT_BASEDIR/patch_minecraft_lwjgl_config"
INFILE=$1
PATCH=$2
OUTFILE=$3

if [ ! -f "$INFILE" ]; then
	echo "Not a file: $INFILE" > /dev/stderr
	exit 1
fi
if [ ! -f "$PATCH" ]; then
	echo "Not a file: $PATCH" > /dev/stderr
	exit 1
fi

if ! source $PATCH; then
	echo "Error reading patch data." > /dev/stderr
	exit 1
fi

if ! TMPDIR="$(mktemp -d)"; then
	echo "Error creating temporary directory." > /dev/stderr
	exit 1
fi
patch_instance
STATUS=$?
rm -r "$TMPDIR"

exit $STATUS
