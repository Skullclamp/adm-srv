"""Sintaxe da documentação e guardas executadas em Bash, sem alterar serviços."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
GUIDE = (ROOT / 'formador/GUIA_RESOLUCAO.md').read_text(encoding='utf-8')
INSTALLER = (ROOT / 'preparar-posto.sh').read_text(encoding='utf-8')


class GuideTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get('BASH_FOR_TESTS') or shutil.which('bash')
        if not cls.bash:
            raise unittest.SkipTest('Bash é necessário para validar os blocos.')

    def shell(self, command):
        env = dict(os.environ, PYTHON_FOR_TESTS=sys.executable.replace('\\', '/'), MSYS_NO_PATHCONV='1')
        prefix = ('export PATH="${BASH%/*}:$PATH"\n'
                  'python3() { "$PYTHON_FOR_TESTS" "$@"; }\n')
        return subprocess.run([self.bash, '-c', prefix + command], text=True,
                              encoding='utf-8', capture_output=True, env=env, timeout=30)

    def parameters(self, folder):
        renderer = re.search(r"<<'PY_PARAMS'\n(.*?)\nPY_PARAMS", INSTALLER, re.S).group(1)
        destination = folder / 'parametros.sh'
        args = [str(ROOT / 'formador/parametros.exemplo.sh'), str(destination), 'p1',
                '192.0.2.10', '192.0.2.0/24', '192.0.2.200', '/home/ubuntu/cp4',
                '/var/lib/docker/volumes/cp4_dados/_data']
        result = subprocess.run([sys.executable, '-', *args], input=renderer,
                                capture_output=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return destination

    def test_all_documented_bash_blocks_and_scripts_have_valid_syntax(self):
        count = 0
        for path in ROOT.rglob('*.md'):
            for match in re.finditer(r'```bash\n(.*?)\n```', path.read_text(encoding='utf-8'), re.S):
                count += 1
                line = path.read_text(encoding='utf-8').count('\n', 0, match.start()) + 1
                with self.subTest(file=str(path.relative_to(ROOT)), line=line):
                    result = subprocess.run([self.bash, '-n'], input=match.group(1),
                                            text=True, encoding='utf-8', capture_output=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreater(count, 50)
        for path in ROOT.rglob('*.sh'):
            with self.subTest(script=str(path.relative_to(ROOT))):
                result = subprocess.run([self.bash, '-n', str(path)], capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_valid_parameters_and_invalid_empty_paths_networks_and_ports(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            destination = self.parameters(Path(task_dir))
            source = 'source ' + shlex.quote(destination.as_posix()) + '\n'
            good = self.shell(source + 'validar_parametros')
            self.assertEqual(good.returncode, 0, good.stderr)
            # A rede autorizada pode ser outra rede de clientes, distinta da interface do servidor.
            good = self.shell(source + 'REDE_LAB=198.51.100.0/24; validar_parametros')
            self.assertEqual(good.returncode, 0, good.stderr)
            for bad in ('IP_ZABBIX=', 'IP_VM=999.1.2.3', 'REDE_LAB=nao-e-rede',
                        'WEB_ROOT=', 'WEB_ROOT=/', 'WEB_ROOT=/var/www/../etc',
                        'unset WEB_ROOT', 'DIR_TLS=/tmp/tls', 'PORTA_HTTP=443',
                        'PORTA_HTTP=0', 'PORTA_HTTP=999999999999999999999',
                        'unset PORTA_HTTP', 'VOLUME_CP4=outro',
                        'URL_ZABBIX=https://user:segredo@example.test'):
                with self.subTest(parameters=bad):
                    result = self.shell(source + bad + '\nvalidar_parametros')
                    self.assertNotEqual(result.returncode, 0)

    def task_blocks(self, number):
        section = re.search(r'^## T' + str(number) + r' —.*?(?=^## T\d+ —|\Z)', GUIDE, re.S | re.M).group(0)
        return re.findall(r'```bash\n(.*?)\n```', section, re.S)

    def test_nginx_workers_are_selected_from_native_service_not_container_processes(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            destination = self.parameters(Path(task_dir))
            block = next(b for b in self.task_blocks(4) if 'CONTAS_NGINX' in b)
            block = block.replace('source "$HOME/parametros-posto.sh"', 'source ' + shlex.quote(destination.as_posix()))
            mocks = '''
systemctl() { [[ "$1" != show ]] || printf '123\n'; }
ps() {
    if [[ "$1 $2" == '--ppid 123' ]]; then
        printf 'www-data nginx: worker process\nwww-data nginx: worker process\n'
    else
        printf 'uuidd nginx: worker process\n1997 nginx: worker process\n'
    fi
}
namei() { :; }
sudo() {
    if [[ "$1" == -u ]]; then
        [[ "$2" == www-data && "$4" == -r ]]
    else
        return 0
    fi
}
'''
            result = self.shell(mocks + block)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('workers=www-data', result.stdout)
            self.assertIn('Leitura permitida', result.stdout)
            self.assertIn('Escrita negada', result.stdout)
            self.assertNotIn('uuidd', result.stdout)

    def test_firewall_is_not_enabled_after_invalid_parameters_or_rule_failure(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            destination = self.parameters(Path(task_dir))
            original = destination.read_text(encoding='utf-8')
            block = next(b for b in self.task_blocks(4) if 'ufw --force enable' in b)
            block = block.replace('source "$HOME/parametros-posto.sh"', 'source ' + shlex.quote(destination.as_posix()))
            mocks = '''
ufw() { :; }
sudo() {
    printf 'CHAMADA=%s\n' "$*"
    [[ "$*" != 'ufw allow from 192.0.2.200 to any port 10050 proto tcp' ]]
}
'''
            failed_rule = self.shell(mocks + block)
            self.assertNotEqual(failed_rule.returncode, 0)
            self.assertNotIn('CHAMADA=ufw --force enable', failed_rule.stdout)
            destination.write_text(re.sub(r'^IP_ZABBIX=.*$', 'IP_ZABBIX=', original, flags=re.M), encoding='utf-8')
            empty = self.shell(mocks + block)
            self.assertNotEqual(empty.returncode, 0)
            self.assertNotIn('CHAMADA=', empty.stdout)


class DocumentLinksTests(unittest.TestCase):
    def test_relative_document_links_point_to_existing_files(self):
        for path in ROOT.rglob('*.md'):
            for match in re.finditer(r'\[[^\]]+\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
                target = match.group(1).strip('<>')
                if urlsplit(target).scheme or target.startswith('#'):
                    continue
                target = unquote(target.split('#', 1)[0])
                with self.subTest(document=str(path.relative_to(ROOT)), link=target):
                    self.assertTrue((path.parent / target).exists(), target)


if __name__ == '__main__':
    unittest.main()
