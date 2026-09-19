#!/usr/bin/env python3
"""Run Godot checks and catch script errors even when Godot exits with status 0."""
import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default='godot')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
commands = [(['--editor', '--quit'], None),
            (['--script', 'tests/test_simulation.gd'], 'Simulation:'),
            (['--script', 'tests/test_ui.gd'], 'UI:')]
for flags, marker in commands:
    result = subprocess.run([args.godot, '--headless', '--path', str(root), *flags],
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    print(output, end='')
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
        sys.exit(1)
    if marker and (marker not in output or '0 failures' not in output):
        sys.exit('Test did not report successful completion')
print('All Godot checks passed.')
