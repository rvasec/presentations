#!/usr/bin/env bash
# Regenerate README.md from presentation files in this directory.
# Filename format: fname_lname-title-words.ext  ->  "Fname Lname - Title Words"
# Name: _ becomes space. Title: - becomes space. Divider: first -.
set -euo pipefail

# Operate on current working directory, not script location.
readme="README.md"

# Derive year from current directory name (e.g. .../2012 -> 2012).
year="$(basename "$PWD")"

{
    echo "# RVAsec $year Slides"
    echo
    echo "Speaker slides from RVAsec $year."
    echo
    echo "## Presentations"
    echo

    for f in *; do
        # Skip dirs, markdown, and shell scripts
        [ -f "$f" ] || continue
        case "$f" in
            *.md|*.sh) continue ;;
        esac

        ext="${f##*.}"
        base="${f%.*}"

        if [[ "$base" == *-* ]]; then
            name="${base%%-*}"      # before first dash
            title="${base#*-}"      # after first dash
        else
            name="$base"            # only one field (e.g. just a name)
            title=""
        fi

        name="${name//_/ }"         # _ -> space in name
        title="${title//-/ }"       # - -> space in title

        if [ -n "$title" ]; then
            label="$name - $title"
        else
            label="$name"
        fi

        echo "- [$label](./$f)"
    done | sort

    echo
    echo "---"
    echo
    echo "Copyright in each presentation belongs to the original speaker. See the [main README](../README.md) for license and takedown policy."
} > "$readme"

echo "Wrote $readme"
