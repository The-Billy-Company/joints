#!/usr/bin/env python3
"""Compare two optimized runtime benchmark executables with alternating order.

Build rust/benches/runtime.rs against each source revision first. This recorder
does not build or modify either candidate. Results are host diagnostics, not a
replacement for the migration's complete compatibility, safety and cost gates.
"""

import argparse
import hashlib
import json
import math
import statistics
import subprocess
import sys
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(reports):
    identity = ('schema', 'grammar', 'source_bytes', 'source_sha256',
                'grammar_sha256', 'tree_sha256', 'lexical_sha256', 'query_sha256',
                'effect_sha256', 'nodes')
    reference = {key: reports[0]['report'][key] for key in identity}
    groups = {}
    operation_sets = []
    sample_shapes = []
    for run in reports:
        report = run['report']
        if {key: report[key] for key in identity} != reference:
            raise ValueError('benchmark inputs or complete output trees differ')
        operations = set()
        shape = {}
        for row in report['rows']:
            elapsed, iterations = row['elapsed_ns'], row['iterations']
            if elapsed <= 0 or iterations <= 0:
                raise ValueError('invalid elapsed time or iteration count')
            name = row['operation']
            operations.add(name)
            key = (name, row['sample'])
            if key in shape:
                raise ValueError('duplicate operation sample')
            shape[key] = iterations
            groups.setdefault(name, {}).setdefault(run['backend'], []).append(elapsed / iterations)
        operation_sets.append(operations)
        sample_shapes.append(shape)
    if not operation_sets[0] or any(ops != operation_sets[0] for ops in operation_sets):
        raise ValueError('benchmark operation coverage differs')
    if any(shape != sample_shapes[0] for shape in sample_shapes):
        raise ValueError('benchmark sample or iteration coverage differs')
    result = []
    for name, backends in sorted(groups.items()):
        metrics = {}
        for backend in ('baseline', 'candidate'):
            values = sorted(backends[backend])
            metrics[backend] = {
                'samples': len(values), 'median_ns': statistics.median(values),
                'p95_ns': values[math.ceil(len(values) * .95) - 1],
            }
        speedup = metrics['baseline']['median_ns'] / metrics['candidate']['median_ns']
        result.append({'operation': name, **metrics, 'median_speedup': speedup,
                       'p95_speedup': metrics['baseline']['p95_ns'] / metrics['candidate']['p95_ns'],
                       'meets_5x': speedup >= 5, 'meets_10x': speedup >= 10})
    return {'identity': reference, 'operations': result,
            'all_meet_5x': all(row['meets_5x'] for row in result)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--samples', type=int, default=15)
    parser.add_argument('--iterations', type=int, default=1)
    parser.add_argument('--entries', type=int, default=4096)
    parser.add_argument('--grammar', type=Path)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--only')
    args = parser.parse_args()
    if min(args.rounds, args.samples, args.iterations, args.entries) <= 0:
        parser.error('rounds, samples, iterations and entries must be positive')
    binaries = {key: getattr(args, key).resolve(strict=True) for key in ('baseline', 'candidate')}
    paths = [*binaries.values(), Path(__file__).resolve()]
    paths += [path.resolve(strict=True) for path in (args.grammar, args.source) if path]
    before = {str(path): digest(path) for path in paths}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'inputs.json').write_text(json.dumps(before, indent=2) + '\n')
    common = ['--samples', str(args.samples), '--iterations', str(args.iterations),
              '--entries', str(args.entries)]
    for key in ('grammar', 'source', 'only'):
        value = getattr(args, key)
        if value is not None:
            common += ['--' + key, str(value.resolve() if isinstance(value, Path) else value)]
    reports = []
    for round_number in range(args.rounds):
        order = ('baseline', 'candidate') if round_number % 2 == 0 else ('candidate', 'baseline')
        for backend in order:
            command = [str(binaries[backend]), *common]
            run = subprocess.run(command, capture_output=True, text=True, timeout=300)
            stem = args.output / f'{round_number}-{backend}'
            stem.with_suffix('.stdout').write_text(run.stdout)
            stem.with_suffix('.stderr').write_text(run.stderr)
            if run.returncode:
                raise RuntimeError(f'{backend} exited {run.returncode}; see {stem}.stderr')
            report = json.loads(run.stdout)
            reports.append({'round': round_number, 'backend': backend,
                            'command': command, 'report': report})
            print(f'completed round {round_number + 1}: {backend}', file=sys.stderr, flush=True)
    after = {str(path): digest(path) for path in paths}
    (args.output / 'raw.json').write_text(json.dumps(reports, indent=2) + '\n')
    if before != after:
        raise ValueError('benchmark executables, recorder or input files changed during measurement')
    summary = {**compare(reports), 'inputs_stable': True, 'inputs': before,
               'scope': 'Alternating process order; one warm-up per operation; timings include drop. '
                        'Uncontrolled host contention; no RSS or allocation measurement; '
                        'no claim about unmeasured functions or release qualification.'}
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for row in summary['operations']:
        print(f"{row['operation']}: {row['median_speedup']:.3f}x median, {row['p95_speedup']:.3f}x p95")


if __name__ == '__main__':
    main()
