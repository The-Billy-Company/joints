"""Performance comparisons must reject semantic drift and incomplete coverage."""
import copy
import unittest

import rust_perf


class RuntimeComparison(unittest.TestCase):
    def reports(self):
        report = dict.fromkeys(('source_sha256', 'grammar_sha256', 'tree_sha256',
                                'lexical_sha256', 'query_sha256', 'effect_sha256'), 'digest')
        report.update(schema=1, grammar='json', source_bytes=10, nodes=5,
                      rows=[{'operation': 'parse', 'sample': i,
                             'elapsed_ns': 1000, 'iterations': 2} for i in range(3)])
        candidate = copy.deepcopy(report)
        for row in candidate['rows']:
            row['elapsed_ns'] = 100
        return [{'backend': 'baseline', 'report': report},
                {'backend': 'candidate', 'report': candidate}]

    def test_speedup_is_per_iteration_and_targets_are_explicit(self):
        result = rust_perf.compare(self.reports())
        row = result['operations'][0]
        self.assertEqual(row['baseline']['median_ns'], 500)
        self.assertEqual(row['candidate']['median_ns'], 50)
        self.assertEqual(row['median_speedup'], 10)
        self.assertTrue(row['meets_5x'])
        self.assertTrue(row['meets_10x'])

    def test_source_tree_lexer_and_query_drift_are_rejected(self):
        for key in ('source_sha256', 'grammar_sha256', 'tree_sha256',
                    'lexical_sha256', 'query_sha256', 'effect_sha256'):
            reports = self.reports()
            reports[1]['report'][key] = 'changed'
            with self.assertRaisesRegex(ValueError, 'differ'):
                rust_perf.compare(reports)

    def test_missing_or_duplicate_samples_are_rejected(self):
        for duplicate in (False, True):
            reports = self.reports()
            rows = reports[1]['report']['rows']
            if duplicate:
                rows.append(copy.deepcopy(rows[0]))
            else:
                rows.pop()
            with self.assertRaisesRegex(ValueError, 'sample'):
                rust_perf.compare(reports)

    def test_invalid_timing_and_missing_operations_are_rejected(self):
        for change in ('elapsed_ns', 'iterations', 'operation'):
            reports = self.reports()
            reports[1]['report']['rows'][0][change] = 'other' if change == 'operation' else 0
            with self.assertRaises(ValueError):
                rust_perf.compare(reports)


if __name__ == '__main__':
    unittest.main()
