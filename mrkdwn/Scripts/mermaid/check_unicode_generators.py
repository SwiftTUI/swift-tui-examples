#!/usr/bin/env python3
"""Exercise invalid-input contracts for the checked-in Unicode generators."""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent


class UnicodeBidiGeneratorTests(unittest.TestCase):
    def run_generator(self, source: str) -> tuple[subprocess.CompletedProcess[str], pathlib.Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name)
        source_path = directory / "DerivedBidiClass.txt"
        output_path = directory / "UnicodeBidiData.swift"
        source_path.write_text(source, encoding="utf-8")
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "generate_unicode_bidi.py"),
                str(source_path),
                str(output_path),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result, output_path

    def test_rejects_reversed_scalar_range(self) -> None:
        result, output = self.run_generator("0001..0000; R\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reversed scalar range", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_scalar_range_above_unicode_limit(self) -> None:
        result, output = self.run_generator("110000; R\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scalar range outside Unicode", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_malformed_property_record(self) -> None:
        sources = ("0000 R\n", "# @missing: 0000 R\n")

        for source in sources:
            with self.subTest(source=source):
                result, output = self.run_generator(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("malformed bidi property record", result.stderr)
                self.assertFalse(output.exists())

    def test_rejects_unknown_bidi_property(self) -> None:
        sources = (
            "0000; Definitely_Not_A_Bidi_Class\n",
            "# @missing: 0000; Definitely_Not_A_Bidi_Class\n",
        )

        for source in sources:
            with self.subTest(source=source):
                result, output = self.run_generator(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unknown bidi property", result.stderr)
                self.assertFalse(output.exists())


class UnicodeWidthGeneratorTests(unittest.TestCase):
    def run_generator(self, source: str) -> tuple[subprocess.CompletedProcess[str], pathlib.Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        output_path = pathlib.Path(temporary.name) / "UnicodeWidthData.swift"
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "generate_unicode_width.py"),
                str(output_path),
            ],
            check=False,
            capture_output=True,
            input=source,
            text=True,
            timeout=10,
        )
        return result, output_path

    def test_rejects_empty_run_stream(self) -> None:
        result, output = self.run_generator("")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width run stream is empty", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_unsupported_width_value(self) -> None:
        sources = ("0 10ffff 4 1\n", "0 10ffff 1 4\n")

        for source in sources:
            with self.subTest(source=source):
                result, output = self.run_generator(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsupported width value", result.stderr)
                self.assertFalse(output.exists())

    def test_rejects_run_outside_unicode_range(self) -> None:
        sources = ("-1 10ffff 1 1\n", "0 110000 1 1\n")

        for source in sources:
            with self.subTest(source=source):
                result, output = self.run_generator(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("width run outside Unicode", result.stderr)
                self.assertFalse(output.exists())

    def test_rejects_reversed_width_run(self) -> None:
        source = "0 0 1 1\n1 0 1 1\n1 10ffff 1 1\n"
        result, output = self.run_generator(source)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reversed width run", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_unsorted_runs(self) -> None:
        source = "0 0 1 1\n2 10ffff 1 1\n1 1 1 1\n"
        result, output = self.run_generator(source)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width runs are unsorted", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_overlapping_runs(self) -> None:
        result, output = self.run_generator("0 1 1 1\n1 10ffff 1 1\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width runs overlap", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_gapped_runs(self) -> None:
        result, output = self.run_generator("0 0 1 1\n2 10ffff 1 1\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width runs contain a gap", result.stderr)
        self.assertFalse(output.exists())

    def test_requires_coverage_from_first_unicode_scalar(self) -> None:
        result, output = self.run_generator("1 10ffff 1 1\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width runs must start at U+0000", result.stderr)
        self.assertFalse(output.exists())

    def test_requires_coverage_through_last_unicode_scalar(self) -> None:
        result, output = self.run_generator("0 10fffe 1 1\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("width runs must end at U+10FFFF", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
