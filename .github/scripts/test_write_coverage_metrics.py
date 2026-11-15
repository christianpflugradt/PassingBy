import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("coverage_metrics", ROOT / ".github/scripts/write-coverage-metrics.py")
coverage_metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage_metrics)


def export(covered, count):
    return json.dumps({"data": [{"totals": {"lines": {"covered": covered, "count": count}}}]})


class WriteCoverageMetricsTest(unittest.TestCase):
    def write(self, content):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "export.json").write_text(content, encoding="utf-8")
            coverage_metrics.write_metrics(root / "export.json", root / "out")
            return json.loads((root / "out" / "coverage.json").read_text())

    def test_writes_line_coverage_as_badge_metric(self):
        self.assertEqual(
            self.write(export(1263, 1332)),
            {"id": "coverage", "label": "coverage", "value": 94.82, "kind": "percent", "badge": True},
        )

    def test_value_is_null_without_measured_lines(self):
        self.assertIsNone(self.write(export(0, 0))["value"])

    def test_rejects_an_export_without_totals(self):
        with self.assertRaises(KeyError):
            self.write(json.dumps({"data": [{}]}))


if __name__ == "__main__":
    unittest.main()
