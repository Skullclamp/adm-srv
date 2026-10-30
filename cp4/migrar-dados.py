#!/usr/bin/env python3
"""Copia inicial de CP4; repetições conservam o trabalho feito após a migração."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil


def manifesto(root):
    if not root.is_dir() or root.is_symlink():
        raise RuntimeError('A origem/destino deve ser uma pasta real.')
    result = {}
    for path in root.rglob('*'):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            raise RuntimeError('Foi encontrada uma ligação simbólica; rever a migração.')
        if path.is_dir():
            result[relative] = 'diretorio'
        elif path.is_file():
            with path.open('rb') as handle:
                result[relative] = hashlib.file_digest(handle, 'sha256').hexdigest()
        else:
            raise RuntimeError('Foi encontrado um ficheiro especial; rever a migração.')
    return result


def confirmar_identidade(marker, identity):
    if not identity or identity == '<no value>':
        raise RuntimeError('Não foi possível identificar o volume cp4_dados.')
    if marker.is_symlink():
        raise RuntimeError('Marcador de migração inesperado.')
    if marker.exists():
        data = json.loads(marker.read_text())
        if data.get('destino') != 'cp4_dados' or data.get('identidade') != identity:
            raise RuntimeError('O volume de destino mudou desde a migração. Recuperar a custódia antes de continuar.')
        return True
    return False


def migrar(source, target, marker, identity, adopt=False):
    if confirmar_identidade(marker, identity):
        print('Migração já concluída: dados atuais de cp4_dados conservados.')
        return
    if adopt:
        if not manifesto(target):
            raise RuntimeError('O volume a conservar está vazio; rever a recuperação da migração anterior.')
    else:
        before = manifesto(source)
        if any(target.iterdir()):
            if manifesto(target) != before:
                raise RuntimeError('Os volumes antigo e cp4_dados contêm dados diferentes. Ambos foram conservados; decidir a origem antes de retomar.')
        else:
            shutil.copytree(source, target, dirs_exist_ok=True)
        if manifesto(target) != before or manifesto(source) != before:
            raise RuntimeError('A verificação da cópia falhou ou a origem mudou; a origem foi conservada.')
    marker.parent.mkdir(parents=True, exist_ok=True)
    temporary = marker.with_name(marker.name + '.novo')
    if temporary.is_symlink():
        raise RuntimeError('Ficheiro temporário de migração inesperado.')
    temporary.write_text(json.dumps({'destino': 'cp4_dados', 'identidade': identity}, indent=2) + '\n')
    temporary.chmod(0o600)
    os.replace(temporary, marker)
    print('Migração registada; os dados originais foram conservados.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('modo', choices=('migrar', 'verificar'))
    parser.add_argument('--origem', type=Path, default=Path('/origem'))
    parser.add_argument('--destino', type=Path, default=Path('/destino'))
    parser.add_argument('--estado', type=Path, required=True)
    parser.add_argument('--identidade', required=True)
    parser.add_argument('--adotar-existente', action='store_true')
    args = parser.parse_args()
    try:
        if args.modo == 'verificar':
            if not confirmar_identidade(args.estado, args.identidade):
                raise RuntimeError('Falta o marcador da migração.')
        else:
            migrar(args.origem, args.destino, args.estado, args.identidade, args.adotar_existente)
    except (RuntimeError, OSError, ValueError) as exc:
        raise SystemExit('ERRO: ' + str(exc))


if __name__ == '__main__':
    main()
