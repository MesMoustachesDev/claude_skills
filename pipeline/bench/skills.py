#!/usr/bin/env python3
"""Les skills du frontmatter d'un agent, préchargés pour le banc comme Claude Code les précharge pour un
sous-agent (ADR 0008), et le contrôle qu'il les a bien reçus.

    pipeline/bench/skills.py feature-implementer          # ce que l'agent recevrait, et d'où
    pipeline/bench/skills.py fix-reproducer --show        # le texte complet des blocs

Ce que reçoit un vrai sous-agent lancé par l'outil Agent (relevé dans ses transcripts,
`projects/*/*/subagents/*.jsonl`) : son prompt, puis un message par skill de `skills:`, fait de deux
blocs de texte :

    <command-message>N</command-message>\\n<command-name>N</command-name>\\n<skill-format>true</skill-format>
    Base directory for this skill: <dossier>\\n\\n<corps>      (skill : SKILL.md)
    <corps>                                                   (commande : commands/N.md)

Le corps est le fichier sans son frontmatter, `$ARGUMENTS` remplacé par rien. `claude -p --agent` ne
fait pas ce préchargement : le banc pose ces blocs lui-même, à la suite du prompt, dans le même message
utilisateur (`--input-format stream-json`). L'API fusionne les messages utilisateur qui se suivent :
le modèle reçoit les mêmes blocs, dans le même ordre, qu'un sous-agent.

Le contrôle : une phrase propre à chaque skill (sa première ligne d'au moins 40 caractères absente du
prompt de l'agent, du prompt de la tâche et des autres skills) doit figurer exactement une fois dans
le texte des messages utilisateur du transcript. Absente : le skill n'est pas arrivé. Deux fois : un
Claude Code qui se mettrait à précharger lui aussi, et le banc mesurerait un agent qui lit tout en double.
"""

import argparse
import glob
import json
import re
import sys
from pathlib import Path

MIN_MARKER = 40


def agent_file(name: str, root: Path) -> Path:
    return root / 'agents' / f'{name}.md'


def split_frontmatter(text: str) -> tuple[str, str]:
    """(frontmatter, corps). Le corps comme Claude Code l'injecte : sans les sauts de ligne de tête."""
    if text.startswith('---\n'):
        end = text.find('\n---\n', 4)
        if end != -1:
            return text[4:end], text[end + 5:].lstrip('\n')
        if text.endswith('\n---'):
            return text[4:-4], ''
    return '', text.lstrip('\n')


def frontmatter_skills(front: str) -> list[str]:
    """Le champ `skills:` d'un frontmatter : liste en tirets ou en ligne (`[a, b]`)."""
    lines = front.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'skills:\s*(.*)$', line)
        if not m:
            continue
        inline = m.group(1).strip()
        if inline:
            return [s.strip().strip('\'"') for s in inline.strip('[]').split(',') if s.strip()]
        out = []
        for item in lines[i + 1:]:
            if re.match(r'\s+-\s+', item):
                out.append(re.sub(r'^\s+-\s+', '', item).strip().strip('\'"'))
            elif item.strip() and not item.startswith((' ', '\t')):
                break
        return out
    return []


def agent_skills(name: str, root: Path) -> list[str]:
    front, _ = split_frontmatter(agent_file(name, root).read_text())
    return frontmatter_skills(front)


def plugin_roots(home: Path) -> list[Path]:
    """Où vivent les plugins : ceux de Claude Code (cache, synced) et ceux que l'app gère (rpm)."""
    roots = [home / '.claude' / 'plugins' / d for d in ('cache', 'synced', 'marketplaces')]
    roots += [Path(p) for p in glob.glob(str(home / 'Library' / 'Application Support' / 'Claude' /
                                             'local-agent-mode-sessions' / '*' / '*' / 'rpm'))]
    return [r for r in roots if r.is_dir()]


def plugin_file(plugin: str, skill: str, home: Path) -> tuple[Path, bool] | None:
    """Le SKILL.md (ou la commande) `skill` du plugin `plugin` ; la copie la plus récente s'il y en a
    plusieurs (cache, synced, rpm de l'app : la même version, posée à des endroits différents)."""
    found = []
    for root in plugin_roots(home):
        for depth in range(0, 5):
            stars = ('*',) * depth
            for kind, pattern in ((True, ('skills', skill, 'SKILL.md')), (False, ('commands', f'{skill}.md'))):
                for p in glob.glob(str(root.joinpath(*stars, *pattern))):
                    path = Path(p)
                    if '/.trash/' in p:
                        continue
                    base = path.parent.parent.parent if kind else path.parent.parent
                    manifest = base / '.claude-plugin' / 'plugin.json'
                    try:
                        if json.loads(manifest.read_text()).get('name') != plugin:
                            continue
                    except (OSError, json.JSONDecodeError):
                        continue
                    found.append((path.stat().st_mtime, kind, path))
    if not found:
        return None
    _, kind, path = max(found, key=lambda f: (f[1], f[0]))   # un skill avant une commande, puis le plus récent
    return path, kind


def resolve(name: str, root: Path, home: Path) -> tuple[Path, bool]:
    """(fichier, est_un_skill) d'un nom de `skills:`. Skill personnel, puis commande, puis plugin."""
    if ':' in name:
        plugin, skill = name.split(':', 1)
        hit = plugin_file(plugin, skill, home)
        if hit:
            return hit
    else:
        skill = root / 'skills' / name / 'SKILL.md'
        if skill.exists():
            return skill, True
        command = root / 'commands' / f'{name}.md'
        if command.exists():
            return command, False
    raise LookupError(f'skill « {name} » introuvable (skills/, commands/, plugins)')


def skill_blocks(name: str, root: Path, home: Path) -> dict:
    path, is_skill = resolve(name, root, home)
    _, body = split_frontmatter(path.read_text())
    body = body.replace('$ARGUMENTS', '')
    header = (f'<command-message>{name}</command-message>\n<command-name>{name}</command-name>\n'
              '<skill-format>true</skill-format>')
    # Le dossier tel que Claude Code l'écrit : celui du lien (skills/doctrine-*), pas sa cible.
    text = f'Base directory for this skill: {path.parent}\n\n{body}' if is_skill else body
    return {'name': name, 'source': str(path), 'header': header, 'text': text, 'body': body}


def marker(body: str, others: list[str]) -> str:
    """La phrase propre à un skill : sa première ligne assez longue qu'on ne trouve nulle part ailleurs."""
    for line in body.splitlines():
        line = line.strip()
        if len(line) >= MIN_MARKER and not any(line in o for o in others):
            return line
    raise ValueError('aucune ligne propre au skill')


def preload(agent: str, task_prompt: str, root: Path, home: Path, system: str | None = None) -> dict:
    """Le message utilisateur d'une passe (prompt puis blocs des skills) et la phrase propre de chaque
    skill. `system` : le prompt de l'agent, si le banc ne le prend pas dans `agents/<nom>.md`."""
    if system is None:
        _, system = split_frontmatter(agent_file(agent, root).read_text())
    skills = [skill_blocks(n, root, home) for n in agent_skills(agent, root)]
    for s in skills:
        others = [system, task_prompt] + [o['body'] for o in skills if o is not s]
        s['marker'] = marker(s['body'], others)
    content = [{'type': 'text', 'text': task_prompt}]
    for s in skills:
        content += [{'type': 'text', 'text': s['header']}, {'type': 'text', 'text': s['text']}]
    return {'content': content, 'skills': skills}


def stdin_line(content: list[dict]) -> str:
    """La ligne `--input-format stream-json` qui porte ce message."""
    return json.dumps({'type': 'user', 'message': {'role': 'user', 'content': content}}, ensure_ascii=False) + '\n'


def user_texts(messages) -> list[str]:
    """Le texte reçu par le modèle comme message utilisateur : blocs `text`, hors résultats d'outils
    (un agent qui ouvre lui-même le fichier d'un skill ne prouve pas son préchargement)."""
    out = []
    for m in messages:
        if m.get('type') != 'user':
            continue
        content = (m.get('message') or {}).get('content')
        if isinstance(content, str):
            out.append(content)
        elif isinstance(content, list):
            out += [b.get('text') or '' for b in content if isinstance(b, dict) and b.get('type') == 'text']
    return out


def transcript(session: str, home: Path) -> Path | None:
    hits = glob.glob(str(home / '.claude' / 'projects' / '*' / f'{session}.jsonl'))
    return Path(hits[0]) if hits else None


def check(skills: list[dict], texts: list[str]) -> dict:
    """{skill: 'reçu' | 'absent' | 'reçu N fois'} d'après sa phrase propre."""
    out = {}
    for s in skills:
        n = sum(t.count(s['marker']) for t in texts)
        out[s['name']] = 'reçu' if n == 1 else 'absent' if n == 0 else f'reçu {n} fois'
    return out


def check_transcript(skills: list[dict], session: str, home: Path) -> dict:
    path = transcript(session, home)
    if not skills:
        return {}
    if path is None:
        return {s['name']: 'absent (pas de transcript)' for s in skills}
    messages = []
    for line in path.read_text().splitlines():
        try:
            messages.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return check(skills, user_texts(messages))


def broken(status: dict) -> str:
    """'' si chaque skill est arrivé une fois, sinon le détail d'une passe cassée."""
    bad = [f'{k} {v}' for k, v in status.items() if v != 'reçu']
    return f"passe cassée : skills préchargés {', '.join(bad)}" if bad else ''


def describe(pre: dict) -> str:
    lines = []
    for s in pre['skills']:
        lines.append(f"  {s['name']} ← {s['source']} ({len(s['text']):,} car.) · phrase : « {s['marker'][:70]} »")
    return '\n'.join(lines) or '  (aucun skill dans le frontmatter)'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('agent')
    parser.add_argument('--root', type=Path, default=Path.home() / '.claude', help='dossier des agents et skills')
    parser.add_argument('--home', type=Path, default=Path.home(), help='HOME (plugins, transcripts)')
    parser.add_argument('--prompt', default='(prompt de la tâche)')
    parser.add_argument('--show', action='store_true', help='affiche les blocs en entier')
    args = parser.parse_args()
    try:
        pre = preload(args.agent, args.prompt, args.root, args.home)
    except (LookupError, ValueError, OSError) as e:
        print(f'{args.agent} : {e}')
        return 1
    status = check(pre['skills'], [b['text'] for b in pre['content']])
    print(f"{args.agent} : {len(pre['skills'])} skill(s)")
    print(describe(pre))
    if args.show:
        for b in pre['content']:
            print('\n───── bloc ─────\n' + b['text'])
    problem = broken(status)
    print(problem or 'prompt construit : chaque skill présent une fois')
    return 1 if problem else 0


if __name__ == '__main__':
    sys.exit(main())
