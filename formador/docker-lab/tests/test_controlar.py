"""Testes de recuperação com ficheiros reais temporários; não exigem Docker."""
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from controlar import Lab, MARKER, SCENARIO, login_ready, monitoring_ready


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.lab = Lab(Path(self.temp.name))
        self.lab.conf.mkdir()
        self.config = self.lab.conf / "default.conf"
        self.config.write_text("server { root /srv/site; }\n", encoding="utf-8")
        self.lab.seed()

    def staged(self, filename="estado.html", content=b"RECUPERADO\n"):
        stage = "restauro-20261030T120000-123"
        source = self.lab.restore / stage / "origens" / "site" / filename
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_bytes(content)
        return stage

    def test_seed_preserves_existing_student_work(self):
        target = self.lab.data / "dados.txt"
        target.write_bytes(b"trabalho alterado\x00\n")
        self.lab.seed()
        self.assertEqual(target.read_bytes(), b"trabalho alterado\x00\n")

    def test_missing_file_undo_preserves_original_bytes(self):
        target = self.lab.site / "estado.html"
        original = b"estado com alteracoes\x00\n"
        target.write_bytes(original)
        self.lab.inject("t16-c")
        self.assertFalse(target.exists())
        self.lab.undo("t16-c")
        self.assertEqual(target.read_bytes(), original)
        self.assertIsNone(self.lab.active())

    def test_second_fault_and_preparation_do_not_overwrite_recovery(self):
        self.lab.inject("t16-c")
        record = self.lab.fault_file.read_bytes()
        with self.assertRaises(RuntimeError):
            self.lab.inject("t6-404")
        with self.assertRaises(RuntimeError):
            self.lab.seed()
        self.assertEqual(self.lab.fault_file.read_bytes(), record)
        self.assertFalse((self.lab.site / "estado.html").exists())

    def test_wrong_undo_id_keeps_fault(self):
        self.lab.inject("t14")
        with self.assertRaises(RuntimeError):
            self.lab.undo("t6-502")
        self.assertEqual(self.lab.active()["id"], "t14")
        self.lab.undo("t14")

    def test_invalid_fault_does_not_mutate_files(self):
        original = self.config.read_bytes()
        with self.assertRaises(RuntimeError):
            self.lab.inject("../outro")
        self.assertEqual(self.config.read_bytes(), original)
        self.assertIsNone(self.lab.active())

    def test_nginx_faults_restore_previous_configuration(self):
        original = self.config.read_bytes()
        for identifier in ("t6-404", "t16-b"):
            with self.subTest(identifier=identifier):
                self.lab.inject(identifier)
                self.assertNotEqual(self.config.read_bytes(), original)
                self.lab.undo(identifier)
                self.assertEqual(self.config.read_bytes(), original)

    @unittest.skipIf(os.name == "nt", "Permissões POSIX verificadas apenas em Linux")
    def test_permission_faults_restore_original_modes(self):
        for identifier, target, bad_mode in (
            ("t6-1", self.lab.site / "estado.html", 0o600),
            ("t16-a", self.lab.site, 0o700),
        ):
            original = target.stat().st_mode & 0o777
            self.lab.inject(identifier)
            self.assertEqual(target.stat().st_mode & 0o777, bad_mode)
            self.lab.undo(identifier)
            self.assertEqual(target.stat().st_mode & 0o777, original)

    def test_restore_promotes_only_selected_file_and_clears_missing_fault(self):
        index = self.lab.site / "index.html"
        original_index = index.read_bytes()
        self.lab.inject("t16-c")
        stage = self.staged(content=(MARKER + " restaurado\n").encode())
        self.lab.promote(stage, "estado.html")
        self.assertIn(b"restaurado", (self.lab.site / "estado.html").read_bytes())
        self.assertEqual(index.read_bytes(), original_index)
        self.assertIsNone(self.lab.active())

    def test_missing_staging_never_reuses_old_restored_file(self):
        self.staged(content=b"snapshot anterior")
        target = self.lab.site / "estado.html"
        original = target.read_bytes()
        with self.assertRaises(RuntimeError):
            self.lab.promote("restauro-20261030T120001-456", "estado.html")
        self.assertEqual(target.read_bytes(), original)

    def test_restore_rejects_path_traversal_and_other_active_faults(self):
        stage = self.staged()
        for candidate, filename in (("../fora", "estado.html"), (stage, "../../passwd")):
            with self.assertRaises(RuntimeError):
                self.lab.promote(candidate, filename)
        self.lab.inject("t6-404")
        with self.assertRaises(RuntimeError):
            self.lab.promote(stage, "estado.html")
        self.assertEqual(self.lab.active()["id"], "t6-404")


class MonitoringTests(unittest.TestCase):
    def test_stale_or_failed_samples_cannot_pass_readiness(self):
        now = int(time.time())
        items = [
            {"key_": "agent.ping", "lastvalue": "1", "lastclock": str(now), "state": "0"},
            {"key_": f"web.test.fail[{SCENARIO}]", "lastvalue": "0", "lastclock": str(now), "state": "0"},
        ]

        class FakeAPI:
            def call(self, method, params):
                return [{"hostid": "1"}] if method == "host.get" else items

        api = FakeAPI()
        self.assertTrue(monitoring_ready(api))
        items[1]["lastclock"] = str(now - 181)
        self.assertFalse(monitoring_ready(api))
        items[1]["lastclock"] = str(now)
        items[1]["lastvalue"] = "1"
        self.assertFalse(monitoring_ready(api))
        items[1]["lastvalue"] = "0"
        items[0]["state"] = "1"
        self.assertFalse(monitoring_ready(api))

    def test_first_login_supplies_current_password_when_changing_own_password(self):
        class FreshAPI:
            def __init__(self):
                self.password = "zabbix"
                self.changes = []

            def login(self, password):
                if password != self.password:
                    raise RuntimeError("Credencial ainda não configurada")
                return "token"

            def call(self, method, params):
                if method == "user.get":
                    return [{"userid": "1"}]
                if method == "user.update":
                    if params.get("current_passwd") != self.password:
                        raise RuntimeError("Falta a palavra-passe atual")
                    self.password = params["passwd"]
                    self.changes.append(params)
                    return {"userids": ["1"]}
                raise AssertionError(method)

        api = FreshAPI()
        with patch.dict(os.environ, {"ZBX_ADMIN_PASSWORD": "Aa1_teste_privado"}):
            login_ready(api, allow_initial=True)
            login_ready(api, allow_initial=True)
        self.assertEqual(len(api.changes), 1)
        self.assertEqual(api.password, "Aa1_teste_privado")


if __name__ == "__main__":
    unittest.main()
