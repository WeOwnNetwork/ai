#!/usr/bin/env python3
"""Exit 0 only when every pod requires weown.dev/pool=erpnext."""

import sys

import yaml

REQUIRED = {
    "key": "weown.dev/pool",
    "operator": "In",
    "values": ["erpnext"],
}


def pod_spec(doc):
    kind = doc.get("kind")
    spec = doc.get("spec") or {}
    if kind in ("Deployment", "StatefulSet", "DaemonSet", "Job"):
        return (spec.get("template") or {}).get("spec") or {}
    if kind == "CronJob":
        return (
            spec.get("jobTemplate", {})
            .get("spec", {})
            .get("template", {})
            .get("spec")
            or {}
        )
    if kind == "Pod":
        return spec
    return None


def pinned(spec):
    affinity = (spec or {}).get("affinity") or {}
    node_affinity = affinity.get("nodeAffinity") or {}
    required = node_affinity.get("requiredDuringSchedulingIgnoredDuringExecution") or {}
    for term in required.get("nodeSelectorTerms") or []:
        for expr in term.get("matchExpressions") or []:
            if expr == REQUIRED:
                return True
    selector = (spec or {}).get("nodeSelector") or {}
    return selector.get("weown.dev/pool") == "erpnext"


def main():
    raw = sys.stdin.read()
    start = raw.find("---")
    if start > 0:
        raw = raw[start:]
    for marker in ("\n-----", "\nFrappe/ERPNext Release", "\nNOTES:"):
        end = raw.find(marker)
        if end > 0:
            raw = raw[:end]
    failed = False
    seen = 0
    for doc in yaml.safe_load_all(raw):
        if not isinstance(doc, dict) or "apiVersion" not in doc:
            continue
        annotations = (doc.get("metadata") or {}).get("annotations") or {}
        if annotations.get("helm.sh/hook") == "test-success":
            continue
        spec = pod_spec(doc)
        if spec is None:
            continue
        seen += 1
        name = (doc.get("metadata") or {}).get("name")
        replicas = (doc.get("spec") or {}).get("replicas")
        ok = pinned(spec)
        mark = "PINNED" if ok else "UNPINNED"
        print(f"{mark} {doc.get('kind')}/{name} replicas={replicas}")
        if not ok:
            failed = True
    if seen == 0:
        sys.stderr.write("no pod templates in render\n")
        sys.exit(1)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
