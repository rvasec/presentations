#!/usr/bin/env bash
# Audit Git LFS coverage across the repo.
#
# Two checks:
#   1. Any file >= threshold that is NOT routed through LFS (a rename or a new
#      file slipped past .gitattributes -> it would push as a fat blob).
#   2. Stale .gitattributes LFS entries pointing at paths that no longer exist
#      (left behind when a tracked file was renamed).
#
# Default is warn-only (exit 1 if issues found, so it can gate a commit hook).
# Pass --fix to update .gitattributes and renormalize tracked files in place.
#
# Threshold defaults to 50 MiB (GitHub's per-file warning). Override with
#   LFS_THRESHOLD_BYTES=<n> ./lfs_check.sh
set -euo pipefail

threshold="${LFS_THRESHOLD_BYTES:-52428800}"   # 50 MiB
fix=0
[ "${1:-}" = "--fix" ] && fix=1

root="$(git rev-parse --show-toplevel)"
cd "$root"
attr=".gitattributes"
[ -f "$attr" ] || : > "$attr"

issues=0

fsize() {  # portable file size in bytes
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null
}

lfs_suffix='filter=lfs diff=lfs merge=lfs -text'
# In .gitattributes the pattern ends at the first space, so a path containing
# spaces must be wrapped in double quotes.
lfs_line() {
    case "$1" in
        *" "*) printf '"%s" %s\n' "$1" "$lfs_suffix" ;;
        *)     printf '%s %s\n'   "$1" "$lfs_suffix" ;;
    esac
}

# ---- Check 1: big files not covered by LFS --------------------------------
# All tracked + untracked-but-not-ignored files.
{ git ls-files; git ls-files --others --exclude-standard; } | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || continue
    size="$(fsize "$f")"
    [ "${size:-0}" -ge "$threshold" ] || continue

    if [ "$(git check-attr filter -- "$f" | sed 's/.*: //')" = "lfs" ]; then
        continue   # already routed through LFS
    fi

    mib=$(( size / 1048576 ))
    echo "BIG-NOT-LFS  ${f}  (${mib} MiB)"
    issues=$((issues + 1))

    if [ "$fix" = 1 ]; then
        lfs_line "$f" >> "$attr"
        # Re-run clean filter so an already-tracked blob becomes a pointer.
        git add -- "$attr"
        git rm --cached -q -- "$f" 2>/dev/null || true
        git add -- "$f"
        echo "  fixed: added LFS rule + restaged $f"
    fi
    # Propagate count out of the subshell via a temp marker.
    echo x >> "$root/.lfs_check_issues"
done

# ---- Check 2: stale LFS entries (path gone) -------------------------------
# Read existing filter=lfs lines, first whitespace-delimited field = path.
while IFS= read -r line; do
    case "$line" in
        \#*|"") continue ;;
    esac
    case "$line" in
        *filter=lfs*) ;;
        *) continue ;;
    esac
    # Pattern = line minus the trailing attribute suffix; strip any quotes.
    pattern="${line% $lfs_suffix}"
    path="$pattern"
    case "$pattern" in
        \"*\") path="${pattern%\"}"; path="${path#\"}" ;;
    esac
    [ -e "$path" ] && continue

    echo "STALE-ENTRY  ${path}  (no such file)"
    echo x >> "$root/.lfs_check_issues"

    if [ "$fix" = 1 ]; then
        grep -vF -- "$line" "$attr" > "$attr.tmp" && mv "$attr.tmp" "$attr"
        git add -- "$attr" 2>/dev/null || true
        echo "  fixed: removed stale rule for $path"
    fi
done < "$attr"

# Tally issues recorded by the subshell.
if [ -f "$root/.lfs_check_issues" ]; then
    issues=$(wc -l < "$root/.lfs_check_issues" | tr -d ' ')
    rm -f "$root/.lfs_check_issues"
fi

if [ "$issues" -gt 0 ]; then
    if [ "$fix" = 1 ]; then
        echo
        echo "Applied $issues fix(es). Review 'git status' and commit .gitattributes + files together."
    else
        echo
        echo "$issues issue(s). Re-run with --fix to update .gitattributes, or fix by hand."
    fi
    exit 1
fi

echo "LFS OK: no oversized blobs, no stale entries."
