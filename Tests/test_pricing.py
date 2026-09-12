"""The Python reference and Swift analyzer share independently calculated cases.

Each case uses 1M input (500K cached) and 100K output tokens.
"""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import codex_usage_analyzer_v3 as analyzer


class PricingTests(unittest.TestCase):
    def test_current_rates_aliases_and_unknown_models(self):
        cases = json.loads((ROOT / "Tests/CodexUsageAnalyzerTests/Fixtures/pricing-cases.json").read_text())
        for case in cases:
            with self.subTest(model=case["model"]):
                actual = analyzer.estimated_credits(case["model"], 1_000_000, 500_000, 100_000)
                if case["credits"] is None:
                    self.assertIsNone(actual)
                else:
                    self.assertAlmostEqual(actual, case["credits"])


if __name__ == "__main__":
    unittest.main()
