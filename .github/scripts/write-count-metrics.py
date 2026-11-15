"""Write lines of code and the test count as metrics for the Statistics workflow."""

import json
from pathlib import Path
import re
import sys


def lines_of_code(scc_report):
    return sum(language["Code"] for language in scc_report)


def test_count(output):
    matches = re.findall(r"^PassingByTests: (\d+) tests passed \(all suites\)$", output, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("The test output has no summary line for all suites")
    return int(matches[0])


def write_metrics(scc_path, test_output_path, output_dir):
    metrics = {
        "loc": ("LOC", "loc", lines_of_code(json.loads(scc_path.read_text(encoding="utf-8")))),
        "tests": ("tests", "tests", test_count(test_output_path.read_text(encoding="utf-8"))),
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    for metric_id, (label, kind, value) in metrics.items():
        metric = {"id": metric_id, "label": label, "value": value, "kind": kind, "badge": True}
        (output_dir / f"{metric_id}.json").write_text(json.dumps(metric, indent=2) + "\n", encoding="utf-8")


def main(argv):
    if len(argv) != 4:
        print("Usage: write-count-metrics.py <scc.json> <test-output.txt> <output-dir>", file=sys.stderr)
        return 2
    write_metrics(Path(argv[1]), Path(argv[2]), Path(argv[3]))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as error:  # A crash is a technical failure, never a FAIL verdict.
        print(f"ERROR: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(2)
