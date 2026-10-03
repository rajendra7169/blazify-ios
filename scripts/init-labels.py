#!/usr/bin/env python3
"""Checks calls to our own types that declare their own init.

The Swift parser here cannot type-check, so an argument a type does not accept
sails through and fails on the cloud Mac ten minutes later. That has now cost a
build twice, both times the same way: a property added to a view whose init is
written by hand, so the new argument was never part of any initialiser.

Deliberately narrow. Only types that declare an `init(` of their own are
examined — for everything else Swift writes the memberwise initialiser and the
labels follow the properties. A call whose labels match no initialiser of the
type is reported; anything uncertain is left alone.
"""
import pathlib
import re
import sys

STRUCT = re.compile(r'^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?'
                    r'(?:final\s+)?(?:struct|class)\s+([A-Z]\w*)', re.M)


def labels_of(params: str) -> set[str]:
    out, depth, current = set(), 0, ''
    for ch in params:
        if ch in '([<{':
            depth += 1
        elif ch in ')]>}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.add(first_label(current))
            current = ''
        else:
            current += ch
    if current.strip():
        out.add(first_label(current))
    out.discard('')
    return out


def first_label(param: str) -> str:
    head = param.split(':')[0].strip()
    parts = head.split()
    return '' if not parts or parts[0] == '_' else parts[0]


def own_inits(text: str):
    """Each type's name and the initialisers written inside it — its own only.

    Brace-matched rather than split at the next declaration, and only what sits
    directly inside the type counts: a nested struct's memberwise initialiser is
    not its parent's, and the parent's is not the nested struct's. Reading it
    the loose way put a singleton's private init() on the struct declared above
    it and called three honest lines wrong.
    """
    for m in STRUCT.finditer(text):
        name = m.group(1)
        open_brace = text.find('{', m.end())
        if open_brace < 0:
            continue
        depth, i = 0, open_brace
        found = []
        while i < len(text):
            ch = text[i]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    break
            elif depth == 1 and text.startswith('init', i) and not text[i - 1].isalnum():
                params_open = text.find('(', i)
                params_close = text.find(')', params_open + 1) if params_open > 0 else -1
                if 0 < params_open < params_close and params_open - i < 8:
                    found.append(labels_of(text[params_open + 1:params_close]))
                    i = params_close
            i += 1
        if found:
            yield name, found


def stored_properties(text: str):
    """Each type's stored properties, in the order they are written.

    That order is the memberwise initialiser's argument order, which is the one
    thing about it nobody can see at the call site — and getting it wrong costs
    a whole build to discover. Computed properties are skipped: they have a
    brace where a stored one has a comma or a newline.

    A type with any private stored property has no memberwise initialiser worth
    checking from elsewhere, so it is passed over rather than guessed at.
    """
    prop = re.compile(
        r'^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*'      # @ObservedObject, @State(…)
        r'(?P<access>private |fileprivate )?'
        r'(?:var|let)[ \t]+(?P<name>\w+)[ \t]*'
        r'(?P<rest>:[^\n=]*)?$',
        re.M)
    for m in STRUCT.finditer(text):
        name = m.group(1)
        open_brace = text.find('{', m.end())
        if open_brace < 0:
            continue
        depth, i, body_start = 0, open_brace, open_brace + 1
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[body_start:i]
        # Only what sits directly inside the type: strip anything nested.
        flat, depth = [], 0
        for line in body.split('\n'):
            if depth == 0:
                flat.append(line)
            depth += line.count('{') - line.count('}')
        names, private = [], False
        for line in flat:
            hit = prop.match(line)
            if not hit or 'static' in line:
                continue
            if '{' in line:            # computed, or a stored one with an observer
                if '=' not in line.split(':')[-1]:
                    continue
            if hit.group('access'):
                private = True
            names.append(hit.group('name'))
        if names and not private:
            yield name, names


def main(paths):
    inits: dict[str, list[set[str]]] = {}
    files = []
    for root in paths:
        for path in sorted(pathlib.Path(root).rglob('*.swift')):
            text = path.read_text()
            files.append((path, text))
            for name, found in own_inits(text):
                inits.setdefault(name, []).extend(found)

    order: dict[str, list[str]] = {}
    for _, text in files:
        for name, names in stored_properties(text):
            order.setdefault(name, names)

    problems = []
    for path, text in files:
        for name, accepted in inits.items():
            for call in re.finditer(rf'(?<![\w.]){name}\s*\(([^()]*)\)', text):
                args = call.group(1)
                if not args.strip():
                    continue
                used = {m.group(1) for m in re.finditer(r'(?:^|,)\s*([a-z]\w*)\s*:(?!:)', args)}
                if not used:
                    continue
                if any(used <= labels for labels in accepted):
                    continue
                line = text[:call.start()].count('\n') + 1
                every = ' / '.join('(' + ', '.join(sorted(l)) + ')' for l in accepted)
                problems.append(f"{path}:{line}: {name}({', '.join(sorted(used))}) "
                                f"— its init takes {every}")

    # Memberwise initialisers: the labels must appear in the order the
    # properties are declared. Only an out-of-order call is reported — a label
    # this script cannot find is far more likely to be a gap in its reading than
    # a real mistake, and a linter that cries wolf is turned off.
    for path, text in files:
        for name, declared in order.items():
            if name in inits:
                continue
            for call in re.finditer(rf'(?<![\w.]){name}\s*\(([^()]*)\)', text):
                used = [m.group(1) for m in
                        re.finditer(r'(?:^|,)\s*([a-z]\w*)\s*:(?!:)', call.group(1))]
                if len(used) < 2 or not set(used) <= set(declared):
                    continue
                if used != sorted(used, key=declared.index):
                    line = text[:call.start()].count('\n') + 1
                    problems.append(
                        f"{path}:{line}: {name}({', '.join(used)}) is out of order "
                        f"— its memberwise init takes ({', '.join(declared)})")

    for problem in sorted(set(problems)):
        print(f"  {problem}")
    return 1 if problems else 0


sys.exit(main(sys.argv[1:]))
