"""Preparação direta: SSH simulado, configuração pública e disco identificado."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'formador/preparar-vm-direto.sh'
SOURCE = SCRIPT.read_text(encoding='utf-8')
PUBLIC = '-----BEGIN CERTIFICATE-----\nPUBLICO-DE-TESTE\n-----END CERTIFICATE-----\n'


class DirectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get('BASH_FOR_TESTS') or shutil.which('bash')
        if not cls.bash:
            raise unittest.SkipTest('Bash é necessário para estes testes.')

    def shell(self, command):
        env = dict(os.environ, PYTHON_FOR_TESTS=sys.executable.replace('\\', '/'), MSYS_NO_PATHCONV='1')
        prefix = ('set +o posix\nexport PATH="${BASH%/*}:$PATH"\n'
                  'python3() { "$PYTHON_FOR_TESTS" "$@"; }\n'
                  'source ' + shlex.quote(SCRIPT.as_posix()) + '\n')
        return subprocess.run([self.bash, '-c', prefix + command], text=True,
                              encoding='utf-8', capture_output=True, env=env, timeout=30)

    def test_bash_syntax_and_help_do_not_require_root_or_proxmox(self):
        result = subprocess.run([self.bash, '-n', str(SCRIPT)], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.shell('main_direto --help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('sudo bash preparar-vm-direto.sh', result.stdout)

    def test_proxmox_address_is_an_address_not_an_ssh_option_or_command(self):
        for good in ('192.0.2.10', 'pve01', 'pve01.example.test'):
            with self.subTest(host=good):
                result = self.shell('validar_proxmox ' + shlex.quote(good))
                self.assertEqual(result.returncode, 0, result.stderr)
        for bad in ('', '-oProxyCommand=id', 'root@pve01', 'https://pve01:8006',
                    'pve01;id', 'pve01$(id)', '999.1.2.3', 'pve..example', '-pve', 'pve-'):
            with self.subTest(host=bad):
                self.assertNotEqual(self.shell('validar_proxmox ' + shlex.quote(bad)).returncode, 0)

    def test_lock_dispatch_sources_script_without_recursive_main(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            fixture = Path(task_dir) / 'preparar-vm-direto.sh'
            footer = 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main_direto "$@"; fi'
            overrides = '''
verificar_vm_direto() { printf 'VERIFICOU_VM\n'; }
executar_direto() { printf 'EXECUTAR=%s\n' "$*"; }
flock() {
    [[ "$1 $2 $3 $4" == '--nonblock --conflict-exit-code 200 --close' ]] || return 99
    [[ ${MOCK_NIVEL:-0} -eq 0 ]] || return 200
    export MOCK_NIVEL=1
    shift 5
    "$@"
}
'''
            self.assertIn(footer, SOURCE)
            adapted = SOURCE.replace('/bin/bash', '"$BASH"')
            fixture.write_text(adapted.replace(footer, overrides + '\n' + footer), encoding='utf-8', newline='\n')
            result = self.shell('"$BASH" ' + shlex.quote(fixture.as_posix()) + ' --proxmox 192.0.2.10')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count('VERIFICOU_VM'), 1)
            self.assertIn('EXECUTAR=--proxmox 192.0.2.10', result.stdout)

    def test_existing_docker_and_compose_are_reused_without_package_installation(self):
        result = self.shell('''
docker() { [[ "$*" == 'compose version' || "$*" == info ]]; }
systemctl() { [[ "$*" == 'enable --now docker' ]]; }
apt-get() { printf INSTALACAO_INDEVIDA; return 99; }
preparar_motor_direto
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('existentes reutilizados', result.stdout)
        self.assertNotIn('INSTALACAO_INDEVIDA', result.stdout)

    def test_remote_export_only_returns_public_ca_and_zabbix_ip(self):
        code = re.search(r"<<'PY_SALA_REMOTA'\n(.*?)\nPY_SALA_REMOTA", SOURCE, re.S).group(1)
        namespace = {'__name__': 'direct_tests'}
        exec(compile(code, '<remote-export>', 'exec'), namespace)
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            folder = Path(task_dir)
            conf, ca = folder / 'lab.conf', folder / 'ca.crt'
            conf.write_text('IP_ZABBIX="192.0.2.200" # sala\nSEGREDO=nao-exportar\n', encoding='utf-8')
            ca.write_text(PUBLIC, encoding='utf-8')
            data = namespace['exportar'](conf, ca)
            self.assertEqual(data, {'ip_zabbix': '192.0.2.200', 'ca_publica': PUBLIC})
            self.assertNotIn('nao-exportar', json.dumps(data))
            ca.write_text(PUBLIC + '-----BEGIN PRIVATE KEY-----\n', encoding='utf-8')
            with self.assertRaises(ValueError):
                namespace['exportar'](conf, ca)

    def test_received_private_key_or_invalid_ip_is_rejected_before_writing_ca(self):
        code = re.search(r"<<'PY_SALA_LOCAL'\n(.*?)\nPY_SALA_LOCAL", SOURCE, re.S).group(1)
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            folder = Path(task_dir)
            metadata, ca = folder / 'sala.json', folder / 'ca.crt'
            for data in ({'ip_zabbix': '', 'ca_publica': PUBLIC},
                         {'ip_zabbix': '192.0.2.200', 'ca_publica': PUBLIC + 'PRIVATE KEY'},
                         {'ip_zabbix': '192.0.2.200', 'ca_publica': ['nao-e-certificado']}):
                with self.subTest(data=data):
                    metadata.write_text(json.dumps(data), encoding='utf-8')
                    result = subprocess.run([sys.executable, '-', str(metadata), str(ca)],
                                            input=code, capture_output=True, encoding='utf-8', timeout=30)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(ca.exists())
            metadata.write_text(json.dumps({'ip_zabbix': '192.0.2.200', 'ca_publica': PUBLIC}), encoding='utf-8')
            result = subprocess.run([sys.executable, '-', str(metadata), str(ca)],
                                    input=code, capture_output=True, encoding='utf-8', timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(ca.read_text(encoding='utf-8'), PUBLIC)

    def test_backup_disk_requires_a_unique_labelled_serial(self):
        result = self.shell("mountpoint() { return 1; }; lsblk() { printf 'sistema-sem-serial-lab\\nlab-backup-101\\n'; }; escolher_disco_direto")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'lab-backup-101')
        for disks in ('', 'lab-backup-101\nlab-backup-102\n', 'lab-backup-101\nlab-backup-101\n'):
            with self.subTest(disks=disks):
                result = self.shell('mountpoint() { return 1; }; lsblk() { printf %s ' + shlex.quote(disks) + '; }; escolher_disco_direto')
                self.assertNotEqual(result.returncode, 0)

    def test_mounted_backup_is_reused_without_requiring_disk_serial(self):
        result = self.shell('''
mountpoint() { [[ "$*" == '-q /srv/backup' ]]; }
lsblk() { printf ESCOLHEU_DISCO_INDEVIDAMENTE; return 99; }
escolher_disco_direto
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_missing_backup_disk_cannot_reach_bootstrap_or_service_changes(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            folder = Path(task_dir)
            ca = folder / 'ca.crt'
            ca.write_text(PUBLIC, encoding='utf-8')
            mocks = '''
openssl() { return 0; }
install() { mkdir -p -- "${@: -1}"; }
mountpoint() { return 1; }
lsblk() { printf 'disco-do-sistema\n'; }
aplicar_direto() { printf ALTEROU_VM_INDEVIDAMENTE; }
'''
            result = self.shell('ESTADO_DIRETO=' + shlex.quote((folder / 'estado').as_posix()) + '\n'
                                + mocks + 'executar_direto --ip-zabbix 192.0.2.200 --ca-cert '
                                + shlex.quote(ca.as_posix()))
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('ALTEROU_VM_INDEVIDAMENTE', result.stdout)

    def test_successful_preflight_passes_validated_settings_to_local_bootstrap(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            folder = Path(task_dir)
            ca = folder / 'ca.crt'
            ca.write_text(PUBLIC, encoding='utf-8')
            mocks = '''
openssl() { return 0; }
install() { mkdir -p -- "${@: -1}"; }
mountpoint() { return 1; }
lsblk() { printf 'lab-backup-101\n'; }
aplicar_direto() { printf 'APLICAR posto=%s servidor=%s serial=%s\n' "$2" "$3" "$4"; }
'''
            result = self.shell('ESTADO_DIRETO=' + shlex.quote((folder / 'estado').as_posix()) + '\n'
                                + mocks + 'executar_direto --ip-zabbix 192.0.2.200 --ca-cert '
                                + shlex.quote(ca.as_posix()))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('APLICAR posto=formador servidor=192.0.2.200 serial=lab-backup-101', result.stdout)


if __name__ == '__main__':
    unittest.main()
