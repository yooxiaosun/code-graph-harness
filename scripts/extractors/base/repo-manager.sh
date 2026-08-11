#!/usr/bin/env bash
set -euo pipefail

REPO_MGR_VERSION="1.0"

load_repo_config() {
    local config_file="${1:-repos.yaml}"
    if [ ! -f "$config_file" ]; then
        echo "[ERROR] repos.yaml not found at $config_file" >&2
        return 1
    fi
    echo "$config_file"
}

get_repo_count() {
    local config_file="$1"
    local count=0
    count=$(grep -cE "^\s+url:" "$config_file" 2>/dev/null || true)
    echo "${count:-0}"
}

get_repo_urls() {
    local config_file="$1"
    grep "url:" "$config_file" | sed 's/.*url:\s*"\(.*\)"/\1/' | sed "s/.*url:\s*'\\(.*\\)'/\\1/"
}

get_repo_branch() {
    local config_file="$1" repo_url="$2"
    awk -v url="$repo_url" '
        BEGIN { found=0 }
        /url:/ && $0 ~ url { found=1 }
        found && /branch:/ { print $2; found=0 }
    ' "$config_file" | tr -d '"'"'" | sed 's/,$//'
}

clone_or_update() {
    local repo_url="$1" branch="$2" work_dir="$3" depth="${4:-1}"

    local repo_name
    repo_name=$(basename "$repo_url" .git)
    local repo_path="$work_dir/$repo_name"

    if [ ! -d "$repo_path" ]; then
        echo "[CLONE] $repo_url ($branch)"
        mkdir -p "$work_dir"
        git clone --depth "$depth" --branch "$branch" "$repo_url" "$repo_path" 2>/dev/null || {
            echo "[WARN] shallow clone failed for $repo_url, trying full clone" >&2
            git clone --branch "$branch" "$repo_url" "$repo_path" || {
                echo "[ERROR] clone failed: $repo_url" >&2
                return 1
            }
        }
        echo > "$repo_path/.last_commit_hash"
        return 0
    fi

    echo "[FETCH] $repo_name"
    local old_hash
    old_hash=$(cat "$repo_path/.last_commit_hash" 2>/dev/null || echo "")
    git -C "$repo_path" fetch origin "$branch" --depth "$depth" 2>/dev/null || true
    git -C "$repo_path" checkout "$branch" 2>/dev/null || true
    git -C "$repo_path" reset --hard "origin/$branch" 2>/dev/null || true
    local new_hash
    new_hash=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || echo "")
    echo "$new_hash" > "$repo_path/.last_commit_hash"

    if [ "$old_hash" != "$new_hash" ] || [ -z "$old_hash" ]; then
        echo "  [CHANGED] $old_hash -> $new_hash"
    else
        echo "  [UNCHANGED] $new_hash"
    fi

    echo "$repo_path"
}

detect_changes() {
    local repo_path="$1"
    local old_hash
    old_hash=$(cat "$repo_path/.last_commit_hash" 2>/dev/null || echo "")
    local new_hash
    new_hash=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || echo "")
    if [ "$old_hash" != "$new_hash" ]; then
        return 0
    fi
    return 1
}

scan_maven_modules() {
    local repo_path="$1"
    find "$repo_path" -name "pom.xml" -not -path "*/.git/*" 2>/dev/null || true
}

get_service_name() {
    local repo_path="$1"
    if [ -f "$repo_path/pom.xml" ]; then
        grep -m1 "<artifactId>" "$repo_path/pom.xml" 2>/dev/null | head -1 | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' || basename "$repo_path"
    else
        basename "$repo_path"
    fi
}
