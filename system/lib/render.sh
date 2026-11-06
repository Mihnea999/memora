#!/usr/bin/env bash
# Shared helpers: render {{key}} placeholders from a theme colors file.

# memora_render <colors-file> <template> <output>
memora_render() {
  local colors="$1" tpl="$2" out="$3" key val
  local -a expr=()
  while IFS='=' read -r key val; do
    [[ $key =~ ^[a-z0-9_]+$ ]] || continue
    val="${val%\"}"; val="${val#\"}"
    expr+=(-e "s|{{${key}}}|${val}|g")
  done < "$colors"
  mkdir -p "$(dirname "$out")"
  sed "${expr[@]}" "$tpl" > "$out.tmp" && mv "$out.tmp" "$out"
}
