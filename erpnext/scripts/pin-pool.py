#!/usr/bin/env python3
"""Insert required node affinity into the MariaDB StatefulSet.

frappe/erpnext 8.0.89 templates/statefulset-mariadb.yaml does not render
affinity, nodeSelector, or tolerations. All other documents pass through
unchanged.
"""

import re
import sys

AFFINITY = """      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: weown.dev/pool
                    operator: In
                    values:
                      - erpnext
      tolerations:
        - key: weown.dev/pool
          operator: Equal
          value: erpnext
          effect: NoSchedule
"""


POD_AFFINITY = """  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: weown.dev/pool
                operator: In
                values:
                  - erpnext
  tolerations:
    - key: weown.dev/pool
      operator: Equal
      value: erpnext
      effect: NoSchedule
"""


def pin_test_pod(doc):
    if "kind: Pod" not in doc or "test-connection" not in doc:
        return doc
    if "nodeAffinity" in doc and "weown.dev/pool" in doc:
        return doc
    spec_at = doc.find("\nspec:\n")
    if spec_at < 0:
        sys.stderr.write("pin-pool: test pod spec not found\n")
        sys.exit(1)
    insert_at = spec_at + len("\nspec:\n")
    return doc[:insert_at] + POD_AFFINITY + doc[insert_at:]


def pin_mariadb(doc):
    if "kind: StatefulSet" not in doc or "mariadb-sts" not in doc:
        return doc
    if "nodeAffinity" in doc and "weown.dev/pool" in doc:
        return doc
    template_at = doc.find("\n  template:\n")
    if template_at < 0:
        sys.stderr.write("pin-pool: MariaDB StatefulSet has no pod template\n")
        sys.exit(1)
    spec_at = doc.find("\n    spec:\n", template_at)
    if spec_at < 0:
        sys.stderr.write("pin-pool: MariaDB pod spec not found\n")
        sys.exit(1)
    insert_at = spec_at + len("\n    spec:\n")
    return doc[:insert_at] + AFFINITY + doc[insert_at:]


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        sys.stderr.write("pin-pool: empty render\n")
        sys.exit(1)
    parts = re.split(r"(?m)^---\s*$", raw)
    pinned = [pin_test_pod(pin_mariadb(part)) for part in parts]
    sys.stdout.write("---".join(pinned))
    if raw.endswith("\n") and not pinned[-1].endswith("\n"):
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
