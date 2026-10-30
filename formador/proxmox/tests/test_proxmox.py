"""Testes sem Proxmox: Bash real com comandos qm/pvesh simulados e cloud-init gerado."""
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
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'criar-vm-formador.sh'
SOURCE = SCRIPT.read_text(encoding='utf-8')
TOKEN = 'a' * 32


class ProxmoxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get('BASH_FOR_TESTS') or shutil.which('bash')
        if not cls.bash:
            raise unittest.SkipTest('É necessário Bash para estes testes.')

    def shell(self, command):
        env = dict(os.environ, PYTHON_FOR_TESTS=sys.executable.replace('\\', '/'), MSYS_NO_PATHCONV='1')
        harness = (
            'export PATH="${BASH%/*}:$PATH"\n'
            'python3() { "$PYTHON_FOR_TESTS" "$@"; }\n'
            'source ' + shlex.quote(SCRIPT.as_posix()) + '\n'
            f'VMID=601; TOKEN={TOKEN}; NODE=pve-teste\n'
            + command
        )
        return subprocess.run([self.bash, '-c', harness], text=True, encoding='utf-8',
                              capture_output=True, env=env, timeout=30)

    def test_script_and_embedded_guest_have_valid_bash_syntax(self):
        checked = subprocess.run([self.bash, '-n', str(SCRIPT)], capture_output=True, timeout=30)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        guest = self.shell('bootstrap_guest')
        self.assertEqual(guest.returncode, 0, guest.stderr)
        checked = subprocess.run([self.bash, '-n'], input=guest.stdout, text=True,
                                 encoding='utf-8', capture_output=True, timeout=30)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_other_vm_with_same_id_is_never_adopted(self):
        result = self.shell('''
qm() { printf 'description: outro-laboratorio\n'; }
pvesh() { printf '{"description":"outro-laboratorio"}\n'; }
verificar_identidade
printf 'PODE_ALTERAR_VM\n'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PODE_ALTERAR_VM', result.stdout)
        self.assertIn('não corresponde', result.stderr)

    def test_owned_vm_is_recognized_even_if_qm_encodes_description(self):
        result = self.shell('''
qm() { printf 'description: adm-srv-formador%%3A%s\n' "$TOKEN"; }
pvesh() {
    [[ "$*" == 'get /nodes/pve-teste/qemu/601/config --current 1 --output-format json' ]] || return 1
    printf '{"description":"adm-srv-formador:%s"}\n' "$TOKEN"
}
verificar_identidade
printf 'IDENTIDADE_OK\n'
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('IDENTIDADE_OK', result.stdout)

    def test_template_is_rejected_even_with_matching_marker(self):
        result = self.shell('''
qm() { printf 'description: adm-srv-formador:%s\ntemplate: 1\n' "$TOKEN"; }
pvesh() { printf '{"description":"adm-srv-formador:%s","template":1}\n' "$TOKEN"; }
verificar_identidade
printf 'PODE_ALTERAR_VM\n'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PODE_ALTERAR_VM', result.stdout)

    def test_encoded_literal_in_api_is_not_accepted_as_matching_marker(self):
        result = self.shell('''
pvesh() { printf '{"description":"adm-srv-formador%%3A%s"}\n' "$TOKEN"; }
verificar_identidade
printf 'PODE_ALTERAR_VM\n'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PODE_ALTERAR_VM', result.stdout)

    def test_invalid_or_missing_api_description_cannot_pass_identity(self):
        for value in ('nao-e-json', '{}', '[]', '{"description":"adm-srv-formador:outro-token"}'):
            with self.subTest(value=value):
                result = self.shell('pvesh() { printf %s ' + shlex.quote(value)
                                    + '; }; verificar_identidade; printf PODE_ALTERAR_VM')
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PODE_ALTERAR_VM', result.stdout)

    def test_occupied_id_stops_before_create(self):
        result = self.shell('''
pvesh() { return 1; }
qm() { printf 'CRIOU_VM_INDEVIDAMENTE\n'; }
escolher_vmid
qm create "$VMID"
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('CRIOU_VM_INDEVIDAMENTE', result.stdout)
        self.assertIn('ocupado', result.stderr)

    def test_auto_id_uses_cluster_api_value(self):
        result = self.shell('''
VMID=auto
pvesh() {
    if [[ "$*" == *'--vmid 609'* ]]; then return 0; fi
    if [[ "$*" == *'--vmid'* ]]; then return 1; fi
    printf '"609"\n'
}
escolher_vmid
printf 'VMID=%s\n' "$VMID"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('VMID=609', result.stdout)

    def test_dhcp_and_static_network_validation(self):
        good = self.shell('IP=dhcp; GATEWAY=; validar_opcoes')
        self.assertEqual(good.returncode, 0, good.stderr)
        good = self.shell("IP=192.0.2.10/24; GATEWAY=192.0.2.1; DNS='192.0.2.1 1.1.1.1'; validar_opcoes")
        self.assertEqual(good.returncode, 0, good.stderr)
        for settings in (
            'IP=192.0.2.10/24; GATEWAY=198.51.100.1',
            'IP=192.0.2.0/24; GATEWAY=192.0.2.1',
            'IP=192.0.2.10/24; GATEWAY=',
            'IP=dhcp; GATEWAY=192.0.2.1',
            'RAM=1024',
        ):
            with self.subTest(settings=settings):
                self.assertNotEqual(self.shell(settings + '; validar_opcoes').returncode, 0)

    def test_guest_pid_without_exit_status_is_not_success(self):
        result = self.shell('''
qm() { printf '{"pid":123}\n'; }
guest 1 'comando-simulado'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ainda decorre', result.stderr)

    def test_guest_failure_exit_status_is_propagated(self):
        result = self.shell('''
qm() { printf '{"exited":1,"exitcode":7,"err-data":"erro simulado"}\n'; }
guest 1 'comando-simulado'
''')
        self.assertEqual(result.returncode, 7)
        self.assertIn('erro simulado', result.stderr)


class LockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get('BASH_FOR_TESTS') or shutil.which('bash')
        if not cls.bash:
            raise unittest.SkipTest('É necessário Bash para estes testes.')

    shell = ProxmoxTests.shell

    def test_full_dispatch_does_not_reenter_main_when_script_is_sourced(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            temporary = Path(task_dir).resolve()
            state = temporary / 'parametros.sh'
            state.touch()
            fixture = temporary / 'criar-vm-formador.sh'
            overrides = '\nSTATE_DIR=' + shlex.quote(temporary.as_posix()) + '\nSTATE_FILE=' + shlex.quote(state.as_posix()) + '''
dependencias() { printf 'DEPENDENCIAS\n'; }
carregar_estado() { NODE=pve-teste; VMID=601; }
validar_opcoes() { :; }
verificar_identidade() { printf 'IDENTIDADE\n'; }
qm() { printf 'status: running\n'; }
ip_vm() { printf '192.0.2.10\n'; }
guest() { printf 'pronto\n'; }
flock() {
    [[ "$1 $2 $3 $4" == '--nonblock --conflict-exit-code 200 --close' ]] || return 99
    if [[ ${MOCK_NIVEL:-0} -ge 2 ]]; then
        printf 'REENTRADA_INDEVIDA\n' >&2
        return 200
    fi
    export MOCK_NIVEL=$((${MOCK_NIVEL:-0} + 1))
    shift 5
    "$@"
}
'''
            footer = 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi'
            self.assertIn(footer, SOURCE)
            adapted = SOURCE.replace('/bin/bash -c', '"$BASH" -c')
            fixture.write_text(adapted.replace(footer, overrides + '\n' + footer),
                               encoding='utf-8', newline='\n')
            # Mesmo nome/caminho em $0 e BASH_SOURCE na primeira chamada: reproduz
            # a forma usada pelo utilizador, atravessando os dois supervisores.
            result = self.shell('"$BASH" ' + shlex.quote(fixture.as_posix()) + ' estado')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count('DEPENDENCIAS'), 1)
            self.assertEqual(result.stdout.count('IDENTIDADE'), 1)
            self.assertIn('VMID: 601', result.stdout)
            self.assertIn('pronto', result.stdout)
            self.assertNotIn('REENTRADA_INDEVIDA', result.stderr)
            previous = adapted.replace('adm-srv-formador-bloqueado "${BASH_SOURCE[0]}"', '"$0" "${BASH_SOURCE[0]}"')
            fixture.write_text(previous.replace(footer, overrides + '\n' + footer),
                               encoding='utf-8', newline='\n')
            regression = self.shell('"$BASH" ' + shlex.quote(fixture.as_posix()) + ' estado')
            self.assertNotEqual(regression.returncode, 0)
            self.assertIn('REENTRADA_INDEVIDA', regression.stderr)

    def test_supervisor_closes_lock_before_executing_commands(self):
        for function, filename in (('com_bloqueio', 'controlo-v2.lock'),
                                   ('com_bloqueio_antigo', 'controlo.lock')):
            with self.subTest(function=function):
                result = self.shell('''
flock() {
    [[ "$1 $2 $3 $4" == '--nonblock --conflict-exit-code 200 --close' ]] || return 99
    printf 'BLOQUEIO=%s\n' "$5"
    [[ "$6 $7" == '/bin/bash -c' ]] || return 98
    [[ "$8" == *'source "$1"; shift;'* ]] || return 97
}
''' + function + ' diagnostico')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('BLOQUEIO=/root/adm-srv-formador-vm/' + filename, result.stdout)

    def test_concurrent_new_operation_is_rejected_without_entering_old_lock(self):
        result = self.shell('''
flock() { return 200; }
com_bloqueio_antigo() { printf OPERACAO_INDEVIDA; }
com_bloqueio alinhar
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Outro comando', result.stderr)
        self.assertNotIn('OPERACAO_INDEVIDA', result.stdout)

    def test_old_lock_active_operation_prevents_vm_commands(self):
        result = self.shell('''
flock() { return 200; }
verificar_bloqueio_herdado() { printf 'instalador antigo ativo\n' >&2; return 1; }
main_bloqueado() { printf OPERACAO_INDEVIDA; }
com_bloqueio_antigo alinhar
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('OPERACAO_INDEVIDA', result.stdout)

    def test_qemu_only_old_lock_can_continue(self):
        result = self.shell('''
flock() { return 200; }
verificar_bloqueio_herdado() { printf 'apenas QEMU\n'; }
main_bloqueado() { printf 'CONTINUOU %s\n' "$*"; }
com_bloqueio_antigo alinhar --espera 2400
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CONTINUOU alinhar --espera 2400', result.stdout)

    def test_holder_validator_rejects_installer_even_alongside_qemu(self):
        code = re.search(r"<<'PY_LOCK'\n(.*?)\nPY_LOCK", SOURCE, re.S).group(1)
        namespace = {'__name__': 'lock_tests'}
        exec(compile(code, '<lock-check>', 'exec'), namespace)
        validate = namespace['validar']
        validate([(1010417, 'kvm')])
        validate([(1010417, 'qemu-system-x86_64')])
        for holders in ([], [(1, 'bash')], [(1, 'kvm'), (2, 'bash')], [(1, 'desconhecido')]):
            with self.subTest(holders=holders):
                with self.assertRaises(RuntimeError):
                    validate(holders)

    def test_proc_scan_matches_inode_and_checks_executable(self):
        code = re.search(r"<<'PY_LOCK'\n(.*?)\nPY_LOCK", SOURCE, re.S).group(1)
        namespace = {'__name__': 'lock_tests'}
        exec(compile(code, '<lock-check>', 'exec'), namespace)
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            temporary = Path(task_dir).resolve()
            lock = temporary / 'controlo.lock'
            lock.touch()
            proc = temporary / 'proc'
            for pid in ('100', '200', '300'):
                (proc / pid / 'fd').mkdir(parents=True)
            os.link(lock, proc / '100/fd/9')
            os.link(lock, proc / '200/fd/9')
            (proc / '300/fd/9').touch()  # Mesmo nome, outro inode: não é titular.
            with patch('os.readlink', side_effect=lambda p: '/usr/bin/kvm' if p.parent.name == '100' else '/usr/bin/bash'):
                holders = namespace['titulares'](lock, proc)
            self.assertEqual(sorted(holders), [(100, 'kvm'), (200, 'bash')])
            with self.assertRaises(RuntimeError):
                namespace['validar'](holders)


class CloudInitTests(unittest.TestCase):
    def test_generated_config_uses_ubuntu_password_and_26_04_bootstrap(self):
        renderer = re.search(r"<<'PY_CLOUD'\n(.*?)\nPY_CLOUD", SOURCE, re.S).group(1)
        guest = re.search(r"<<'BASH_GUEST'\n(.*?)\nBASH_GUEST", SOURCE, re.S).group(1)
        # Temporários dentro da pasta de testes; a limpeza fica limitada a esta raiz.
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as task_dir:
            temporary = Path(task_dir).resolve()
            self.assertTrue(temporary.is_relative_to(Path(__file__).parent.resolve()))
            guest_path = temporary / 'guest.sh'
            guest_path.write_text(guest, encoding='utf-8', newline='\n')
            ca_path = temporary / 'ca.crt'
            ca_path.write_text('CERTIFICADO-PUBLICO-DE-TESTE\n', encoding='utf-8')
            result = subprocess.run([sys.executable, '-', 'formador-docker', '$6$HASH-DE-TESTE',
                                     'b' * 40, str(guest_path), 'formador', '192.0.2.200',
                                     str(ca_path), 'lab-backup-601'], input=renderer,
                                    capture_output=True, encoding='utf-8', timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.startswith('#cloud-config\n'))
            config = json.loads(result.stdout.split('\n', 1)[1])
        self.assertNotIn('user', config)
        self.assertEqual(config['users'][0]['name'], 'ubuntu')
        self.assertFalse(config['users'][0]['lock_passwd'])
        self.assertEqual(config['users'][0]['hashed_passwd'], '$6$HASH-DE-TESTE')
        self.assertTrue(config['ssh_pwauth'])
        self.assertFalse(config['chpasswd']['expire'])
        files = {item['path']: item for item in config['write_files']}
        bootstrap = files['/usr/local/sbin/preparar-formador-docker']['content']
        self.assertIn('"$VERSION_ID" == 26.04', bootstrap)
        self.assertIn('docker-compose-plugin', bootstrap)
        self.assertIn('preparar-posto.sh" instalar', bootstrap)
        self.assertNotIn('lab-formador.sh" subir', bootstrap)
        self.assertEqual(files['/etc/adm-srv-formador-ref']['content'], 'b' * 40 + '\n')
        options=json.loads(files['/etc/adm-srv-formador-opcoes.json']['content'])
        self.assertEqual(options, {'posto':'formador','ip_zabbix':'192.0.2.200','disco_serial':'lab-backup-601'})
        self.assertIn(['systemctl', 'start', '--no-block', 'adm-srv-formador.service'], config['runcmd'])
        self.assertNotIn(['systemctl', 'enable', 'adm-srv-formador.service'], config['runcmd'])


if __name__ == '__main__':
    unittest.main()
