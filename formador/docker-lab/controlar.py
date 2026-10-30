#!/usr/bin/env python3
"""Operações limitadas aos volumes do laboratório Docker do formador."""
from __future__ import annotations

import argparse
import base64
import json
import multiprocessing
import os
from pathlib import Path
import re
import ssl
import stat
import sys
import time
from typing import Callable
import urllib.error
import urllib.request

HOST = "docker-formador"
SCENARIO = "HTTPS-formador"
MARKER = "ESTADO-FORMADOR"
FAULTS = {"t6-1", "t6-404", "t6-502", "t14", "t16-a", "t16-b", "t16-c"}


def wait_for(label: str, function: Callable, timeout: float = 300, interval: float = 3):
    deadline = time.monotonic() + timeout
    last_error = "sem resposta"
    announced = 0.0
    while True:
        try:
            result = function()
            if result:
                return result
            last_error = "a condição ainda não foi satisfeita"
        except (RuntimeError, OSError, ValueError, urllib.error.URLError) as exc:
            last_error = str(exc)
        now = time.monotonic()
        if now >= deadline:
            raise RuntimeError(f"Tempo excedido: {label}. Último resultado: {last_error}")
        if now - announced >= 15:
            print(f"A aguardar {label}...", flush=True)
            announced = now
        time.sleep(min(interval, max(0, deadline - now)))


class API:
    def __init__(self, url: str | None = None):
        self.url = url or os.environ.get("ZBX_API", "http://zabbix-web:8080/api_jsonrpc.php")
        self.token = ""

    def call(self, method: str, params=None):
        payload = {"jsonrpc": "2.0", "method": method, "params": {} if params is None else params, "id": 1}
        headers = {"Content-Type": "application/json-rpc"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers)
        with urllib.request.urlopen(request, timeout=12) as response:
            data = json.load(response)
        if "error" in data:
            error = data["error"]
            raise RuntimeError(f"API {method}: {error.get('message', 'erro')} — {error.get('data', '')}")
        return data["result"]

    def login(self, password: str):
        self.token = ""
        self.token = self.call("user.login", {"username": "Admin", "password": password})
        return self.token

    def logout(self):
        if self.token:
            try:
                self.call("user.logout", [])
            except (RuntimeError, OSError, ValueError):
                pass
            self.token = ""


def login_ready(api: API, allow_initial: bool = False):
    wanted = os.environ["ZBX_ADMIN_PASSWORD"]

    def attempt():
        try:
            api.login(wanted)
            return "configurada"
        except (RuntimeError, OSError, ValueError, urllib.error.URLError):
            if not allow_initial:
                raise
        api.login("zabbix")
        return "inicial"

    mode = wait_for("API e autenticação Zabbix", attempt)
    if mode == "inicial":
        users = api.call("user.get", {"output": ["userid"], "filter": {"username": ["Admin"]}})
        if len(users) != 1:
            raise RuntimeError("Não foi possível identificar a conta Admin desta stack.")
        api.call("user.update", {"userid": users[0]["userid"], "current_passwd": "zabbix", "passwd": wanted})
        api.login(wanted)
        print("Palavra-passe inicial do Zabbix substituída pela credencial privada do laboratório.")


def provision(api: API):
    psk = os.environ["AGENT_PSK"]
    if not re.fullmatch(r"[a-fA-F0-9]{64}", psk):
        raise RuntimeError("AGENT_PSK inválida: recuperar os parâmetros gerados.")
    groups = api.call("hostgroup.get", {"output": ["groupid"], "filter": {"name": ["Formacao/Docker"]}})
    gid = groups[0]["groupid"] if groups else api.call("hostgroup.create", {"name": "Formacao/Docker"})["groupids"][0]
    templates = api.call("template.get", {"output": ["templateid"], "filter": {"host": ["Linux by Zabbix agent"]}})
    if not templates:
        raise RuntimeError("Template Linux by Zabbix agent não encontrado na base inicial.")
    hosts = api.call("host.get", {"output": ["hostid"], "filter": {"host": [HOST]}})
    encryption = {"tls_connect": 2, "tls_accept": 2, "tls_psk_identity": "FORMADOR-DOCKER", "tls_psk": psk}
    if not hosts:
        hid = api.call("host.create", {
            "host": HOST, "status": 0, "groups": [{"groupid": gid}],
            "templates": [{"templateid": templates[0]["templateid"]}],
            "interfaces": [{"type": 1, "main": 1, "useip": 0, "ip": "", "dns": "agent", "port": "10050"}],
            **encryption,
        })["hostids"][0]
    else:
        hid = hosts[0]["hostid"]
        api.call("host.update", {"hostid": hid, "status": 0, **encryption})
    defaults = api.call("host.get", {"output": ["hostid"], "filter": {"host": ["Zabbix server"]}})
    for item in defaults:
        api.call("host.update", {"hostid": item["hostid"], "status": 1})
    scenarios = api.call("httptest.get", {"output": ["httptestid"], "hostids": [hid], "filter": {"name": [SCENARIO]}})
    if not scenarios:
        api.call("httptest.create", {
            "name": SCENARIO, "hostid": hid, "delay": "15s", "verify_peer": 1, "verify_host": 1,
            "steps": [{"name": "estado", "no": 1, "url": "https://formador.lab.test/estado.html",
                       "status_codes": "200", "required": MARKER},
                      {"name": "CP4", "no": 2, "url": "https://formador.lab.test/app/dados.txt",
                       "status_codes": "200", "required": "CP4-DADOS-OK"}],
        })

    def ensure_trigger(description, expression, priority):
        existing = api.call("trigger.get", {"output": ["triggerid"], "hostids": [hid], "filter": {"description": [description]}})
        if not existing:
            api.call("trigger.create", {"description": description, "expression": expression, "priority": priority})

    ensure_trigger("Site do formador indisponivel", f"last(/{HOST}/web.test.fail[{SCENARIO}])<>0", 4)
    cpu = api.call("item.get", {"output": ["key_"], "hostids": [hid],
                               "filter": {"key_": ["system.cpu.util", "system.cpu.util[,idle]"]}})
    keys = {item["key_"] for item in cpu}
    if "system.cpu.util" in keys:
        expression = f"min(/{HOST}/system.cpu.util,5m)>80"
    elif "system.cpu.util[,idle]" in keys:
        expression = f"max(/{HOST}/system.cpu.util[,idle],5m)<20"
    else:
        raise RuntimeError("O template não disponibilizou um item CPU compatível; confirmar a versão instalada.")
    ensure_trigger("CPU elevada no contexto do agente", expression, 2)
    print("Host com PSK, template, cenário HTTPS e dois triggers configurados.")


def monitoring_ready(api: API):
    hosts = api.call("host.get", {"output": ["hostid"], "filter": {"host": [HOST]}})
    if not hosts:
        raise RuntimeError("Host do laboratório não configurado.")
    wanted = {"agent.ping": "1", f"web.test.fail[{SCENARIO}]": "0"}
    items = api.call("item.get", {
        "output": ["key_", "lastvalue", "lastclock", "state", "error"],
        "hostids": [hosts[0]["hostid"]], "webitems": True,
        "filter": {"key_": list(wanted)},
    })
    seen = {item["key_"]: item for item in items}
    now = int(time.time())
    for key, expected in wanted.items():
        item = seen.get(key)
        if not item or not int(item.get("lastclock", 0)):
            return False
        if now - int(item["lastclock"]) > 180 or item.get("lastvalue") != expected:
            return False
        if str(item.get("state", "0")) != "0":
            return False
    return True


class Lab:
    def __init__(self, root: Path = Path("/")):
        self.root = root
        self.site = root / "site"
        self.data = root / "dados"
        self.conf = root / "conf"
        self.state = root / "estado"
        self.restore = root / "restauro"
        self.fault_file = self.state / "falha.json"

    def active(self):
        if self.fault_file.exists():
            return json.loads(self.fault_file.read_text(encoding="utf-8"))
        return None

    @staticmethod
    def regular(path: Path):
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"Não é um ficheiro regular do laboratório: {path.name}")

    def seed(self):
        if self.active():
            raise RuntimeError("Há uma falha ativa. Usa repor antes de voltar a preparar a stack.")
        for directory in (self.site, self.data, self.state):
            if directory.is_symlink():
                raise RuntimeError("Um diretório de dados não pode ser uma ligação simbólica.")
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o755 if directory != self.state else 0o700)
        defaults = {
            self.site / "index.html": "<h1>Formador - SITE-OK</h1>\n",
            self.site / "estado.html": MARKER + "\n",
            self.site / "teste-restauro.html": "RESTAURO-FORMADOR\n",
            self.data / "index.html": "<h1>CP4 - Formador Docker</h1>\n",
            self.data / "dados.txt": "CP4-DADOS-OK\n",
        }
        for path, text in defaults.items():
            if not path.exists() and not path.is_symlink():
                path.write_text(text, encoding="utf-8")
                path.chmod(0o644)
            self.regular(path)
        print("Dados iniciais presentes; ficheiros anteriores conservados.")

    def _save_fault(self, identifier: str, path: Path | None):
        record = {"id": identifier, "created": int(time.time())}
        if path is not None:
            mode = stat.S_IMODE(path.stat().st_mode)
            record["kind"] = "directory" if path.is_dir() else "file"
            record["target"] = "site" if path == self.site else "config" if path.parent == self.conf else "estado"
            record["mode"] = mode
            if path.is_file():
                self.regular(path)
                record["content"] = base64.b64encode(path.read_bytes()).decode("ascii")
        self.state.mkdir(parents=True, exist_ok=True)
        with self.fault_file.open("x", encoding="utf-8") as handle:
            json.dump(record, handle)
        self.fault_file.chmod(0o600)

    def inject(self, identifier: str, check: Callable | None = None):
        if identifier not in FAULTS:
            raise RuntimeError("Falha desconhecida.")
        if self.active():
            raise RuntimeError("Já existe uma falha ativa; repõe-a antes de introduzir outra.")
        if check is not None:
            check()
        path = self.site / "estado.html" if identifier in {"t6-1", "t16-c"} else \
            self.site if identifier == "t16-a" else \
            self.conf / "default.conf" if identifier in {"t6-404", "t16-b"} else None
        if path and path.is_symlink():
            raise RuntimeError("O alvo da falha não pode ser uma ligação simbólica.")
        if identifier == "t6-404" and "root /srv/site;" not in path.read_text(encoding="utf-8"):
            raise RuntimeError("Não foi encontrada a raiz esperada no modelo Nginx.")
        self._save_fault(identifier, path)
        if identifier == "t6-1":
            path.chmod(0o600)
        elif identifier == "t16-a":
            path.chmod(0o700)
        elif identifier == "t6-404":
            text = path.read_text(encoding="utf-8").replace("root /srv/site;", "root /nao-existe;")
            path.write_text(text, encoding="utf-8")
        elif identifier == "t16-b":
            with path.open("a", encoding="utf-8") as handle:
                handle.write("\ndirectiva_invalida on;\n")
        elif identifier == "t16-c":
            path.unlink()
        print(f"Falha registada: {identifier}")

    def undo(self, identifier: str):
        record = self.active()
        if not record or record.get("id") != identifier:
            raise RuntimeError("O identificador não corresponde à falha ativa.")
        target = record.get("target")
        if target:
            path = self.site if target == "site" else self.conf / "default.conf" if target == "config" else self.site / "estado.html"
            if path.is_symlink():
                raise RuntimeError("Alvo de reposição inesperado.")
            if record["kind"] == "file":
                path.write_bytes(base64.b64decode(record["content"], validate=True))
            path.chmod(record["mode"])
        self.fault_file.unlink()
        print(f"Falha revertida: {identifier}")

    def promote(self, stage: str, filename: str):
        if not re.fullmatch(r"restauro-\d{8}T\d{6}-\d+", stage):
            raise RuntimeError("Identificador de staging inválido.")
        if filename not in {"estado.html", "teste-restauro.html"}:
            raise RuntimeError("Ficheiro de restauro não autorizado.")
        active = self.active()
        if active and active.get("id") != "t16-c":
            raise RuntimeError("Há outra falha ativa; não promover dados sobre esse estado.")
        source = self.restore / stage / "origens" / "site" / filename
        if not source.resolve().is_relative_to(self.restore.resolve()):
            raise RuntimeError("O restauro aponta para fora da área de staging.")
        self.regular(source)
        target = self.site / filename
        if target.is_symlink():
            raise RuntimeError("Destino de promoção inesperado.")
        target.write_bytes(source.read_bytes())
        target.chmod(0o644)
        if filename == "estado.html" and active:
            self.fault_file.unlink()
        print(f"Ficheiro promovido do snapshot: {filename}")


def check_web(timeout: float = 90):
    context = ssl.create_default_context(cafile="/ca/ca.crt")

    def request(path, expected):
        with urllib.request.urlopen("https://formador.lab.test" + path, context=context, timeout=8) as response:
            text = response.read(1024 * 1024).decode("utf-8")
            if response.status != 200 or expected not in text:
                raise RuntimeError(f"Conteúdo inesperado no pedido {path}")
        return True

    wait_for("HTTPS com CA, nome e conteúdo válidos", lambda: request("/estado.html", MARKER), timeout=timeout)
    wait_for("aplicação CP4 através do reverse proxy", lambda: request("/app/dados.txt", "CP4-DADOS-OK"), timeout=timeout)
    print("HTTPS e CP4 funcionais; verificação TLS ativa.")


def burn_cpu(seconds: int):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        sum(i * i for i in range(10000))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["inicializar", "configurar-zabbix", "verificar", "verificar-web", "falha", "repor", "promover", "carga"])
    parser.add_argument("args", nargs="*")
    args = parser.parse_args(argv)
    lab = Lab()
    if args.command == "inicializar":
        lab.seed()
    elif args.command in {"falha", "repor"}:
        if len(args.args) != 1:
            parser.error("Indicar uma falha.")
        if args.command == "falha":
            lab.inject(args.args[0], check=lambda: check_web(timeout=20))
        else:
            lab.undo(args.args[0])
    elif args.command == "promover":
        if len(args.args) != 2:
            parser.error("Indicar staging e ficheiro.")
        lab.promote(*args.args)
    elif args.command == "verificar-web":
        check_web()
    elif args.command == "carga":
        seconds = int(args.args[0]) if args.args else 30
        if not 1 <= seconds <= 120:
            parser.error("Duração permitida: 1–120 segundos.")
        workers = [multiprocessing.Process(target=burn_cpu, args=(seconds,)) for _ in range(min(2, os.cpu_count() or 1))]
        for worker in workers:
            worker.start()
        try:
            for worker in workers:
                worker.join(timeout=seconds + 10)
        finally:
            for worker in workers:
                if worker.is_alive():
                    worker.terminate()
                worker.join()
        print("Carga controlada terminada.")
    else:
        api = API()
        try:
            login_ready(api, allow_initial=args.command == "configurar-zabbix")
            if args.command == "configurar-zabbix":
                provision(api)
            else:
                check_web()
                wait_for("agent.ping=1 e cenário HTTPS saudável com amostras recentes", lambda: monitoring_ready(api))
                print("Zabbix confirmou recolha por PSK e monitorização HTTPS recente.")
        finally:
            api.logout()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, urllib.error.URLError) as error:
        print(f"ERRO: {error}", file=sys.stderr)
        sys.exit(1)
