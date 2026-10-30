"""Contratos de nomes/caminhos e conservação de dados na preparação comum."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'preparar-posto.sh').read_text(encoding='utf-8')


class CommonEnvironmentTests(unittest.TestCase):
    def test_student_yaml_and_installed_yaml_are_identical(self):
        guide=(ROOT/'PREPARAR_CP4.md').read_text(encoding='utf-8')
        expected=re.search(r'```yaml\n(.*?)\n```', guide, re.S).group(1)
        self.assertEqual((ROOT/'cp4/compose.yaml').read_text(encoding='utf-8').strip(), expected.strip())

    def test_native_installer_bash_syntax(self):
        bash=os.environ.get('BASH_FOR_TESTS') or shutil.which('bash')
        if not bash:
            self.skipTest('Bash não disponível')
        result=subprocess.run([bash,'-n',str(ROOT/'preparar-posto.sh')],capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_parameter_paths_follow_the_same_rules_for_every_post(self):
        code=re.search(r"<<'PY_PARAMS'\n(.*?)\nPY_PARAMS",SOURCE,re.S).group(1)
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            base=Path(task_dir).resolve()
            self.assertTrue(base.is_relative_to(Path(__file__).parent.resolve()))
            results={}
            for posto in ('p1','p2','formador'):
                destination=base/(posto+'.sh')
                args=[str(ROOT/'formador/parametros.exemplo.sh'),str(destination),posto,
                      '192.0.2.10','192.0.2.0/24','192.0.2.200','/home/ubuntu/cp4',
                      '/var/lib/docker/volumes/cp4_dados/_data']
                result=subprocess.run([sys.executable,'-',*args],input=code,
                                      capture_output=True,encoding='utf-8',timeout=30)
                self.assertEqual(result.returncode,0,result.stderr)
                text=destination.read_text(encoding='utf-8')
                values={}
                for line in text.splitlines():
                    if re.match(r'^[A-Z][A-Z0-9_]*=',line):
                        key,value=line.split('=',1)
                        words=shlex.split(value,comments=True)
                        values[key]=words[0] if words else ''
                results[posto]=values
                self.assertEqual(values['WEB_ROOT'],'/var/www/'+posto)
                self.assertEqual(values['NGINX_INCLUDE'],'/etc/nginx/conf.d/'+posto+'.conf')
                self.assertEqual(values['REPO'],'/srv/backup/'+posto)
                self.assertEqual(values['NOME_LOGICO_DO_POSTO'],'srv-'+posto)
            for key in ('COMPOSE_CP4','VOLUME_CP4','VOLUME_CP4_PATH','AMOSTRA_ORIGEM',
                        'CA_CERT','DIR_TLS','PONTO_REPO','PSK_FILE','PORTA_HTTP','PORTA_HTTPS','PORTA_BACKEND'):
                self.assertEqual(len({r[key] for r in results.values()}),1,key)

    def migrate(self, source, target):
        code=re.search(r"python:3\.13-slim python -c '\n(.*?)'\n    fi",SOURCE,re.S).group(1)
        code=code.replace('Path("/origem"), Path("/destino")',
                          f'Path({str(source)!r}), Path({str(target)!r})')
        return subprocess.run([sys.executable,'-'],input=code,capture_output=True,
                              encoding='utf-8',timeout=30)

    def test_cp4_migration_copies_binary_and_nested_files_and_can_repeat(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            base=Path(task_dir).resolve()
            self.assertTrue(base.is_relative_to(Path(__file__).parent.resolve()))
            source,target=base/'source',base/'target'
            (source/'subpasta').mkdir(parents=True);target.mkdir()
            (source/'subpasta/dados.bin').write_bytes(b'\x00\xffdados\n')
            (source/'dados.txt').write_text('trabalho anterior',encoding='utf-8')
            for _ in range(2):
                result=self.migrate(source,target)
                self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual((target/'subpasta/dados.bin').read_bytes(),b'\x00\xffdados\n')
            self.assertEqual((target/'dados.txt').read_bytes(),(source/'dados.txt').read_bytes())

    def test_cp4_migration_refuses_conflicting_data_without_overwriting(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            base=Path(task_dir).resolve()
            self.assertTrue(base.is_relative_to(Path(__file__).parent.resolve()))
            source,target=base/'source',base/'target'
            source.mkdir();target.mkdir()
            (source/'dados.txt').write_bytes(b'origem')
            (target/'dados.txt').write_bytes(b'destino a conservar')
            result=self.migrate(source,target)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((source/'dados.txt').read_bytes(),b'origem')
            self.assertEqual((target/'dados.txt').read_bytes(),b'destino a conservar')


if __name__=='__main__':
    unittest.main()
