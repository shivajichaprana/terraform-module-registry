#!/usr/bin/env python3
"""Generate the machine-readable module manifest (``registry.json``).

The manifest is the registry's index of published modules. Rather than hand-maintain
it, this tool derives each entry directly from the module sources so the index can
never drift from the code: it discovers every module under ``modules/``, parses the
Terraform configuration for its provider requirements, minimum Terraform version,
inputs (and which are required), outputs, and runnable examples, and computes a
content hash over the module's root ``*.tf`` files.

Curated, non-derivable fields — a module's one-line ``summary`` and its lifecycle
``status`` — are preserved from the existing manifest when present, so regenerating
is idempotent against a well-maintained file.

Usage
-----
    generate_manifest.py                 # print the manifest to stdout
    generate_manifest.py --write         # write modules/index into registry.json
    generate_manifest.py --check         # exit non-zero if registry.json is stale
    generate_manifest.py --write --set-version 1.2.0
                                         # stamp a release version while regenerating

The ``--check`` mode is intended for CI: it fails the build when the committed
manifest does not match what the sources would produce. ``--set-version`` is used
by the release automation to stamp the next semantic version during a release.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import logging
import re
import sys
from pathlib import Path
from typing import Optional

LOG = logging.getLogger("generate_manifest")

# Root .tf files that make up a module's public contract; examples and docs are
# deliberately excluded from the content hash so doc-only edits do not churn it.
MODULE_TF_FILES = ("main.tf", "variables.tf", "outputs.tf", "versions.tf")

REPO_ROOT = Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------- #
# HCL-lite scanning helpers
#
# These are intentionally small string/comment-aware scanners rather than a full
# HCL parser. They are sufficient for the well-formed module files in this repo
# and avoid a third-party dependency, keeping the generator stdlib-only.
# --------------------------------------------------------------------------- #
def _skip_string(text: str, i: int) -> int:
    """Return the index just past a double-quoted string starting at ``text[i]``."""
    i += 1  # consume opening quote
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        i += 1
    return i


def _skip_line(text: str, i: int) -> int:
    nl = text.find("\n", i)
    return len(text) if nl == -1 else nl + 1


def _skip_block_comment(text: str, i: int) -> int:
    end = text.find("*/", i + 2)
    return len(text) if end == -1 else end + 2


def _extract_braced(text: str, open_index: int) -> tuple[str, int]:
    """Given the index of an opening ``{``, return (inner_body, index_after_close).

    Brace matching skips over string literals and comments so braces inside them
    are not counted.
    """
    n = len(text)
    depth = 0
    i = open_index
    body_start = open_index + 1
    while i < n:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            continue
        if c == "#":
            i = _skip_line(text, i)
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i = _skip_line(text, i)
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i = _skip_block_comment(text, i)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[body_start:i], i + 1
        i += 1
    raise ValueError("unbalanced braces while scanning block")


def _named_blocks(text: str, keyword: str) -> list[tuple[str, str]]:
    """Return (label, body) for every ``keyword "label" { ... }`` block."""
    blocks: list[tuple[str, str]] = []
    pattern = re.compile(r'(?:^|\n)[ \t]*' + re.escape(keyword) + r'\s+"([^"]+)"\s*\{')
    for m in pattern.finditer(text):
        label = m.group(1)
        brace_index = text.index("{", m.end() - 1)
        body, _ = _extract_braced(text, brace_index)
        blocks.append((label, body))
    return blocks


def _has_top_level_attr(body: str, attr: str) -> bool:
    """True if ``attr =`` appears at brace/paren/bracket depth 0 within ``body``.

    Nested occurrences (inside ``validation`` blocks, ``object({...})`` types, or
    ``optional(type, default)`` calls) sit at depth > 0 and are correctly ignored.
    """
    n = len(body)
    depth = 0
    i = 0
    while i < n:
        c = body[i]
        if c == '"':
            i = _skip_string(body, i)
            continue
        if c == "#":
            i = _skip_line(body, i)
            continue
        if c == "/" and i + 1 < n and body[i + 1] == "/":
            i = _skip_line(body, i)
            continue
        if c == "/" and i + 1 < n and body[i + 1] == "*":
            i = _skip_block_comment(body, i)
            continue
        if c in "{[(":
            depth += 1
            i += 1
            continue
        if c in "}])":
            depth -= 1
            i += 1
            continue
        if (
            depth == 0
            and body.startswith(attr, i)
            and (i == 0 or not (body[i - 1].isalnum() or body[i - 1] == "_"))
        ):
            j = i + len(attr)
            after = body[j] if j < n else ""
            if not (after.isalnum() or after == "_"):
                k = j
                while k < n and body[k] in " \t":
                    k += 1
                if k < n and body[k] == "=" and (k + 1 >= n or body[k + 1] != "="):
                    return True
        i += 1
    return False


def _first_braced_after(text: str, keyword: str) -> Optional[str]:
    """Return the inner body of the first ``keyword { ... }`` block, if any."""
    m = re.search(r'(?:^|\n)[ \t]*' + re.escape(keyword) + r'\s*\{', text)
    if not m:
        return None
    brace_index = text.index("{", m.end() - 1)
    body, _ = _extract_braced(text, brace_index)
    return body


def _top_level_assign_keys(body: str) -> list[str]:
    """Return keys ``k`` for every ``k = { ... }`` assignment at depth 0 in ``body``."""
    keys: list[str] = []
    for m in re.finditer(r'(?:^|\n)[ \t]*([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*\{', body):
        # Confirm the match is at depth 0 by checking the text before it has balanced braces.
        prefix = body[: m.start()]
        if prefix.count("{") == prefix.count("}"):
            keys.append(m.group(1))
    return keys


# --------------------------------------------------------------------------- #
# Module introspection
# --------------------------------------------------------------------------- #
def _normalize_tf_version(constraint: str) -> str:
    """Turn a version constraint like ``>= 1.6`` into a padded ``1.6.0``."""
    m = re.search(r"(\d+(?:\.\d+)*)", constraint)
    if not m:
        return constraint.strip()
    parts = m.group(1).split(".")
    while len(parts) < 3:
        parts.append("0")
    return ".".join(parts[:3])


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _module_summary(module_dir: Path, fallback: str) -> str:
    """Derive a one-line summary from the module README's lead paragraph."""
    readme = module_dir / "README.md"
    if not readme.exists():
        return fallback
    lines = _read(readme).splitlines()
    paragraph: list[str] = []
    seen_heading = False
    for line in lines:
        stripped = line.strip()
        if not seen_heading:
            if stripped.startswith("#"):
                seen_heading = True
            continue
        if not stripped:
            if paragraph:
                break
            continue
        if stripped.startswith("#"):
            break
        paragraph.append(stripped)
    if not paragraph:
        return fallback
    text = " ".join(paragraph)
    text = re.sub(r"[*_`]", "", text)  # drop markdown emphasis/code ticks
    text = re.sub(r"\s+", " ", text).strip()
    return text or fallback


def _content_hash(module_dir: Path) -> str:
    digest = hashlib.sha256()
    for name in MODULE_TF_FILES:
        path = module_dir / name
        if not path.exists():
            continue
        digest.update(f"# {name}\n".encode("utf-8"))
        digest.update(path.read_bytes())
    return "sha256:" + digest.hexdigest()


def _examples(module_dir: Path) -> list[str]:
    examples_dir = module_dir / "examples"
    if not examples_dir.is_dir():
        return []
    found = []
    for child in sorted(examples_dir.iterdir()):
        if child.is_dir() and any(child.glob("*.tf")):
            found.append(child.name)
    return found


def introspect_module(module_dir: Path, prior: Optional[dict]) -> dict:
    """Build a manifest entry for a single module directory."""
    name = module_dir.name
    prior = prior or {}

    variables_text = _read(module_dir / "variables.tf") if (module_dir / "variables.tf").exists() else ""
    outputs_text = _read(module_dir / "outputs.tf") if (module_dir / "outputs.tf").exists() else ""
    versions_text = _read(module_dir / "versions.tf") if (module_dir / "versions.tf").exists() else ""

    variables = _named_blocks(variables_text, "variable")
    required = [n for n, body in variables if not _has_top_level_attr(body, "default")]
    outputs = [n for n, _ in _named_blocks(outputs_text, "output")]

    providers: list[str] = []
    rp_body = _first_braced_after(versions_text, "required_providers")
    if rp_body:
        providers = sorted(_top_level_assign_keys(rp_body))

    min_tf = "0.0.0"
    m = re.search(r'required_version\s*=\s*"([^"]+)"', versions_text)
    if m:
        min_tf = _normalize_tf_version(m.group(1))

    entry = {
        "name": name,
        "path": module_dir.relative_to(REPO_ROOT).as_posix(),
        # Curated summary wins when present; derive from the README for new modules.
        "summary": prior.get("summary") or _module_summary(module_dir, ""),
        "providers": providers or prior.get("providers", []),
        "min_terraform_version": min_tf,
        "inputs": {
            "count": len(variables),
            "required": sorted(required),
        },
        "outputs": {"count": len(outputs)},
        "examples": _examples(module_dir),
        "status": prior.get("status", "experimental"),
        "content_hash": _content_hash(module_dir),
    }
    LOG.debug(
        "module %s: %d inputs (%d required), %d outputs, providers=%s, min_tf=%s",
        name, entry["inputs"]["count"], len(required), entry["outputs"]["count"],
        entry["providers"], min_tf,
    )
    return entry


# --------------------------------------------------------------------------- #
# Manifest assembly
# --------------------------------------------------------------------------- #
def _ordered_module_dirs(modules_root: Path, prior_order: list[str]) -> list[Path]:
    """Discovered modules, ordered to match the prior manifest, new ones appended."""
    dirs = {p.name: p for p in modules_root.iterdir() if p.is_dir() and (p / "main.tf").exists()}
    ordered: list[Path] = [dirs[n] for n in prior_order if n in dirs]
    for name in sorted(dirs):
        if name not in prior_order:
            ordered.append(dirs[name])
    return ordered


def build_manifest(
    modules_root: Path, existing: dict, set_version: Optional[str] = None
) -> dict:
    prior_by_name = {m["name"]: m for m in existing.get("modules", [])}
    prior_order = [m["name"] for m in existing.get("modules", [])]

    manifest = dict(existing)  # preserve top-level metadata keys and their order
    if set_version:
        manifest["version"] = set_version
    manifest["modules"] = [
        introspect_module(module_dir, prior_by_name.get(module_dir.name))
        for module_dir in _ordered_module_dirs(modules_root, prior_order)
    ]
    return manifest


def _render(manifest: dict) -> str:
    return json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _load_existing(registry_path: Path) -> dict:
    if registry_path.exists():
        return json.loads(_read(registry_path))
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "registry": "terraform-module-registry",
        "description": "Private library of hardened, reusable Terraform modules.",
        "version": "0.0.0",
        "source_prefix": "github.com/<your-github-org>/terraform-module-registry//modules",
        "modules": [],
    }


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the module manifest (registry.json).")
    parser.add_argument("--modules-dir", default=str(REPO_ROOT / "modules"),
                        help="Directory containing the modules (default: ./modules).")
    parser.add_argument("--registry", default=str(REPO_ROOT / "registry.json"),
                        help="Path to the manifest file (default: ./registry.json).")
    parser.add_argument("--write", action="store_true", help="Write the manifest to disk.")
    parser.add_argument("--check", action="store_true",
                        help="Exit non-zero if the manifest on disk is out of date.")
    parser.add_argument("--set-version", default=None,
                        help="Stamp this version into the manifest (used by release automation).")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable debug logging.")
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    modules_root = Path(args.modules_dir).resolve()
    registry_path = Path(args.registry).resolve()
    if not modules_root.is_dir():
        LOG.error("modules directory not found: %s", modules_root)
        return 2

    existing = _load_existing(registry_path)
    manifest = build_manifest(modules_root, existing, set_version=args.set_version)
    rendered = _render(manifest)

    if args.check:
        current = _read(registry_path) if registry_path.exists() else ""
        if current == rendered:
            LOG.info("manifest is up to date (%d modules)", len(manifest["modules"]))
            return 0
        LOG.error("manifest is out of date; run with --write to regenerate")
        diff = difflib.unified_diff(
            current.splitlines(keepends=True),
            rendered.splitlines(keepends=True),
            fromfile="registry.json (on disk)",
            tofile="registry.json (expected)",
        )
        sys.stderr.writelines(diff)
        return 1

    if args.write:
        registry_path.write_text(rendered, encoding="utf-8")
        LOG.info("wrote %s (%d modules)", registry_path, len(manifest["modules"]))
        return 0

    sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
