#!/usr/bin/env python3
"""Reproduce the bounded upstream inventory; no network, npm or server execution.

Reads committed blobs, never working-tree content. Literal scanning is deliberately
not a reachability analysis: dynamic add(), mods, rules and invoked moves need audit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

REVISION = 'b354a81f11003a03f0dcd1dafd4edc641e6763bd'
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'test/fixtures/battle/upstream_inventory.json'
EMITTERS = [
    'sim/battle.ts', 'sim/pokemon.ts', 'sim/side.ts', 'sim/battle-actions.ts',
    'sim/field.ts', 'data/moves.ts', 'data/abilities.ts', 'data/items.ts',
    'data/conditions.ts',
]
FILES = ['sim/SIM-PROTOCOL.md', 'config/formats.ts',
         'data/random-battles/gen9/teams.ts', 'data/random-battles/gen9/sets.json',
         *EMITTERS]


def snapshot(repo):
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args])

    if git('rev-parse', 'HEAD').decode().strip() != REVISION:
        raise SystemExit(f'Expected upstream HEAD {REVISION}')
    blobs = {path: git('show', f'{REVISION}:{path}') for path in FILES}
    text = {path: blob.decode() for path, blob in blobs.items()}
    documented = sorted(set(re.findall(
        r'`\|(-?[a-z][a-z0-9]*)[|`]', text['sim/SIM-PROTOCOL.md'])))
    emitted = {}
    for path in EMITTERS:
        for number, line in enumerate(text[path].splitlines(), 1):
            for event in re.findall(
                r'\b(?:this|battle|this\.battle)\.add\(\s*[\'"]([^\'"]+)[\'"]', line
            ):
                if re.fullmatch(r'-?[a-z][a-z0-9:]*', event):
                    emitted.setdefault(event, []).append(f'{path}:{number}')
    sets = json.loads(text['data/random-battles/gen9/sets.json'])
    moves, abilities = set(), set()
    witnesses = {name: [] for name in [
        'Revival Blessing', 'Giga Impact', 'Outrage', 'Transform',
        'Sleep Talk', 'Illusion', 'Imposter',
    ]}
    for species, data in sets.items():
        for variant in data['sets']:
            moves.update(variant['movepool'])
            abilities.update(variant['abilities'])
            for name in witnesses:
                if name in variant['movepool'] or name in variant['abilities']:
                    if species not in witnesses[name]:
                        witnesses[name].append(species)
    return {
        'schemaVersion': 1,
        'revision': REVISION,
        'repository': 'https://github.com/smogon/pokemon-showdown',
        'scope': 'Documented protocol types plus literal add() calls in nine files; not an exhaustive Gen 9 reachability proof.',
        'sources': {p: {'sha256': hashlib.sha256(b).hexdigest(),
                        'url': f'https://github.com/smogon/pokemon-showdown/blob/{REVISION}/{p}'}
                    for p, b in blobs.items()},
        'documentedEvents': documented,
        'literalEmitters': dict(sorted(emitted.items())),
        'randomSetSummary': {
            'speciesEntries': len(sets), 'uniqueMoveNames': len(moves),
            'uniqueAbilityNames': len(abilities), 'witnesses': witnesses,
            'limitation': 'Candidate pools only; excludes generated items, conditional selection, called moves and transformations. Not a localization denominator.',
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('upstream', type=Path)
    parser.add_argument('--check', action='store_true', help='Compare without changing files')
    args = parser.parse_args()
    result = snapshot(args.upstream)
    if args.check:
        if result != json.loads(OUTPUT.read_text()):
            raise SystemExit('Upstream inventory differs; review before updating')
    else:
        OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Inventory verified: {len(result['documentedEvents'])} documented types, "
          f"{len(result['literalEmitters'])} literal emitted types; "
          f"{result['randomSetSummary']['speciesEntries']} set entries")


if __name__ == '__main__':
    main()
