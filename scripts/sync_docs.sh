#!/bin/bash
# Copies the documentation of zenc-docs into the Zola site, the way the site expects it:
# the language tour (split from the reference), the standard library, the Rosetta Code
# examples, the Getting Started pages and the migration guides. The Pages workflow runs
# it before `zola build`; it also works for a local preview.
#
# Usage: scripts/sync_docs.sh ZENC_DOCS_DIR [SITE_DIR]
#   ZENC_DOCS_DIR  a checkout of zenc-lang-ce/zenc-docs
#   SITE_DIR       the Zola site (default: docs.zenc-lang.org)
# Splitting the reference needs Python with `unidecode` (pip install unidecode).
set -euo pipefail

DOCS=${1:?usage: scripts/sync_docs.sh ZENC_DOCS_DIR [SITE_DIR]}
SITE=${2:-docs.zenc-lang.org}
CONTENT="$SITE/content"

# The tour pages are generated from the README in raw/.
(cd "$DOCS" && python3 scripts/split_reference.py --force)

# Shortcodes (e.g. misra_table.html)
mkdir -p "$SITE/templates/shortcodes/"
rsync -a "$DOCS/site/templates/shortcodes/" "$SITE/templates/shortcodes/"

# Standard library (localized); its README files are the section indexes.
mkdir -p "$CONTENT/std/"
rsync -a --delete --exclude='_index*.md' "$DOCS/std/" "$CONTENT/std/"
find "$CONTENT/std/" -name "README*.md" | while read -r file; do
    mv "$file" "${file/README/_index}"
done

# Language tour
mkdir -p "$CONTENT/tour/"
rsync -a --delete --exclude='_index.md' "$DOCS/reference/" "$CONTENT/tour/"

# Getting Started pages (English only), shown as plain documents
for name in install changelog; do
    title=$(grep -m 1 "^# " "$DOCS/$name.md" | sed 's/^# //')
    { printf '+++\ntitle = "%s"\ntemplate = "plain.html"\n+++\n\n' "$title"; cat "$DOCS/$name.md"; } \
        > "$CONTENT/$name.md"
done

# Migration guides (English only): one page per release, shown as plain documents
mkdir -p "$CONTENT/migrations/"
rsync -a --delete --exclude='_index*.md' "$DOCS/migrations/" "$CONTENT/migrations/"
printf '+++\ntitle = "Migrations"\nsort_by = "title"\npage_template = "plain.html"\n+++\n' \
    > "$CONTENT/migrations/_index.md"

# Rosetta Code examples; their README files are the section indexes.
mkdir -p "$CONTENT/examples/rosetta/"
rsync -a --delete --exclude='_index*.md' "$DOCS/rosetta/" "$CONTENT/examples/rosetta/"
find "$CONTENT/examples/rosetta/" -name "README*.md" | while read -r file; do
    mv "$file" "${file/README/_index}"
done

# Every section needs an index in every language, or Zola fails to build.
LANGS="es pt it de ru zh-cn zh-tw"
find "$CONTENT/" -name "_index.md" | while read -r index_file; do
    dir=$(dirname "$index_file")
    for lang in $LANGS; do
        if [ ! -f "$dir/_index.$lang.md" ]; then
            cp "$index_file" "$dir/_index.$lang.md"
        fi
    done
done

# Remove the Rosetta Code wiki templates ({{trans|...}}) and give a front matter to the
# pages that have none, titled after their first heading.
find "$CONTENT/" -name "*.md" | while read -r file; do
    sed -i.bak 's/{{trans|.*}}//g' "$file" && rm -f "$file.bak"
    if ! head -n 1 "$file" | grep -q "^+++"; then
        title=$(grep -m 1 "^# " "$file" | sed 's/^# //; s/"/\\"/g' || true)
        tmp=$(mktemp)
        { printf '+++\ntitle = "%s"\n+++\n\n' "${title:-Documentation}"; cat "$file"; } > "$tmp"
        mv "$tmp" "$file"
    fi
done
