import unittest
from collect_firebase_xml import results_root


class CollectionTests(unittest.TestCase):
    def test_managed_results_location(self):
        self.assertEqual(results_root('Raw results [https://console.developers.google.com/storage/browser/test-lab-abc/2026-10-29_11:00.123_AbCd/]'), 'gs://test-lab-abc/2026-10-29_11:00.123_AbCd')

    def test_missing_ambiguous_and_unmanaged_locations_fail(self):
        for text in ('', 'https://evil.example/storage/browser/test-lab-abc/path/', 'https://console.developers.google.com/storage/browser/custom/path/'):
            with self.assertRaises(ValueError):
                results_root(text)
