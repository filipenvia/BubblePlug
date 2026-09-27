import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


source = Path(__file__).resolve().parents[1] / "macos/ableton-export-worker.py"
spec = importlib.util.spec_from_file_location("ableton_export_worker", source)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class ExportDocumentTests(unittest.TestCase):
    def load(self, document):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "library.json"
            path.write_text(json.dumps(document))
            return worker.load_document(path)

    def test_rejects_duplicate_colors_and_names(self):
        base = {"schemaVersion": 2, "categories": [
            {"name": "Mix", "colorIndex": 2},
            {"name": "Voice", "colorIndex": 2},
        ]}
        with self.assertRaises(worker.ExportError):
            self.load(base)
        base["categories"][1] = {"name": " mix ", "colorIndex": 3}
        with self.assertRaises(worker.ExportError):
            self.load(base)

    def test_rejects_more_than_six_categories(self):
        document = {"schemaVersion": 2, "categories": [
            {"name": f"Category {index}", "colorIndex": index}
            for index in range(1, 8)
        ]}
        with self.assertRaises(worker.ExportError):
            self.load(document)

    def test_channel_variants_share_family(self):
        self.assertEqual(worker.family_base("Pro-Q 4 Stereo"), "Pro-Q 4")
        self.assertEqual(worker.family_base("Compressor 5.1"), "Compressor")
        self.assertEqual(worker.family_base("EchoBoy Jr"), "EchoBoy Jr")

    def test_non_vst3_favorite_is_rejected(self):
        document = {"categories": [], "favorites": [
            {"id": "local|plugin", "name": "Plugin", "format": "AU"}
        ], "labels": []}
        with self.assertRaises(worker.ExportError):
            worker.expected_families(document)


if __name__ == "__main__":
    unittest.main()
