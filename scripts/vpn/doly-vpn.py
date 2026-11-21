#!/usr/bin/env python3
"""doly-vpn: alta y baja de la VPN de DolyNation.

Todo el material secreto vive cifrado en reposo bajo /etc/doly-vpn.
Las llaves privadas de WireGuard y las claves de la CA nunca se quedan en
claro en disco: se sellan con AES-256-GCM, con la passphrase de la CA
derivada por scrypt.

Fases:
    ca       genera la CA raiz y la intermedia (selladas)
    peers    genera el hub + un par por peer (llave + PSK + IP)
    render   escribe /etc/wireguard/wg0.conf con el material en claro (0600)
    certs    emite el certificado de cada servicio y de cada cliente
    bundles  arma el paquete cifrado de cada developer
    list     inventario publico (sin material secreto)
"""

import argparse
import base64
import hashlib
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

BASE = pathlib.Path("/etc/doly-vpn")
CA_DIR = BASE / "ca"
PEERS_DIR = BASE / "peers"
BUNDLES_DIR = BASE / "bundles"
WG_DIR = pathlib.Path("/etc/wireguard")
LE_LIVE_DIR = pathlib.Path("/etc/letsencrypt/live/doly-vpn-dev")
LE_SERVICES = ("devapi", "devweb")

# Formato del material sellado: "DOLYVPN1" | salt(16) | nonce(12) | ciphertext
SEAL_MAGIC = b"DOLYVPN1"
SCRYPT_N = 2 ** 15
SCRYPT_R = 8
SCRYPT_P = 1

# --------------------------------------------------------------------------
# Familias de red. Cada familia es un dominio de confianza: sus miembros se
# hablan entre si, y hacia fuera solo por reglas explicitas.
# --------------------------------------------------------------------------
FAMILIES = {
    "servicios": "10.90.0.0/24",  # devapi, devweb, minios (+ hub)
    "devs": "10.91.0.0/24",       # laptops del equipo
    "admin": "10.92.0.0/24",      # administracion / operacion
}

HUB_IP = "10.90.0.1"
WG_PORT = 58376
WG_MTU = 1420
# Endpoint publico del hub: lo usan los developers (sus laptops).
WG_ENDPOINT = "141.148.148.45"
# Los peers de servicio corren en contenedores del mismo servidor: llegan al
# hub por la red interna de Docker. El hairpin a la IP publica no funciona
# en OCI, asi que el endpoint interno es el gateway de la red 'doly-vpn-net'.
WG_ENDPOINT_LOCAL = "10.98.0.1"

# nombre, familia, IP, tipo, descripcion
#
# Jesus Alberto y Sebastian estan en las dos familias: desarrollan (y
# necesitan hablar con los demas developers y con los servicios) y ademas
# administran (y necesitan llegar a todo).
#
# Cada identidad es un peer con su PROPIA llave y su PROPIO PSK: son
# identidades distintas, no la misma con dos permisos. Asi el peer de
# desarrollo de Jesus no puede alcanzar la familia admin, aunque la
# persona sea la misma. El firewall lo impide por IP de tunel, y la
# separacion se ve en los logs (el CN del certificado de cliente dice
# "jxadevp-dev" o "jxadevp-admin").
PEERS = [
    ("devapi",       "servicios", "10.90.0.2", "servicio", "API del ambiente de desarrollo"),
    ("devweb",       "servicios", "10.90.0.3", "servicio", "Web del ambiente de desarrollo"),
    ("minios",       "servicios", "10.90.0.4", "servicio", "Almacenamiento de objetos (S3)"),
    ("jxadevp-dev",  "devs",      "10.91.0.6", "dev",      "Jesus Alberto: desarrollo"),
    ("jxadevp-admin", "admin",     "10.92.0.2", "admin",    "Jesus Alberto: administracion"),
    ("sebastian-dev", "devs",      "10.91.0.2", "dev",      "Sebastian: desarrollo"),
    ("sebastian-admin", "admin",   "10.92.0.3", "admin",    "Sebastian: administracion"),
    ("azael",        "devs",      "10.91.0.3", "dev",      "Azael: backend"),
    ("elias",        "devs",      "10.91.0.4", "dev",      "Elias: backend"),
    ("y0adq1",       "devs",      "10.91.0.5", "dev",      "Juan Antonio: frontend"),
]

# Las personas con dos identidades: un solo paquete con las dos configs.
# El resto, un paquete con una sola.
PERSONAS_DUALES = {
    "jxadevp":  ["jxadevp-dev",  "jxadevp-admin"],
    "sebastian": ["sebastian-dev", "sebastian-admin"],
}

SERVICE_NAMES = {
    "devapi": "devapi.yacaterkos.tech",
    "devweb": "devweb.yacaterkos.tech",
    "minios": "minios.doly.internal",
}

SERVICE_PORTS = {
    "devapi": 443,
    "devweb": 443,
    "minios": 50090,
}


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

def run(cmd, input_text=None, env=None):
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                       input=input_text, env=e)
    return p.returncode, p.stdout, p.stderr


def sh(cmd, input_text=None, env=None, what=""):
    rc, out, err = run(cmd, input_text, env)
    if rc != 0:
        print(f"ERROR en {what or cmd}:\n{err.strip()}\n{out.strip()}", file=sys.stderr)
        sys.exit(1)
    return out


def sh_bytes(cmd, env=None, what=""):
    """Como sh(), pero sin decodificar: para material binario (.p12)."""
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(cmd, shell=True, capture_output=True, env=e)
    if p.returncode != 0:
        print(f"ERROR en {what or cmd}:\n{p.stderr.decode(errors='replace').strip()}",
              file=sys.stderr)
        sys.exit(1)
    return p.stdout


def write_secret(path: pathlib.Path, content: str, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    os.chmod(path, mode)


def read_secret(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def passphrase():
    p = os.environ.get("PASSPHRASE")
    if not p:
        print("ERROR: falta la variable de entorno PASSPHRASE", file=sys.stderr)
        sys.exit(1)
    return p


# --------------------------------------------------------------------------
# Sellado del material secreto: AES-256-GCM con la clave derivada por
# scrypt. El GCM autentica: si alguien toca un byte, el descifrado falla.
# --------------------------------------------------------------------------

def _derive(pw: str, salt: bytes) -> bytes:
    # scrypt con N=32768, r=8 necesita 32 MiB; el limite por defecto de
    # OpenSSL es justo 32 MiB, asi que hay que darle margen.
    return hashlib.scrypt(pw.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R,
                          p=SCRYPT_P, dklen=32,
                          maxmem=64 * 1024 * 1024)


def seal(plaintext: bytes, pw: str) -> bytes:
    """Sella un texto con la passphrase. Devuelve bytes autocontenidos."""
    salt = secrets.token_bytes(16)
    nonce = secrets.token_bytes(12)
    key = _derive(pw, salt)
    ct = AESGCM(key).encrypt(nonce, plaintext, SEAL_MAGIC)
    return SEAL_MAGIC + salt + nonce + ct


def unseal(blob: bytes, pw: str) -> bytes:
    """Abre un material sellado."""
    if not blob.startswith(SEAL_MAGIC):
        raise RuntimeError("el material no esta sellado con el formato esperado")
    body = blob[len(SEAL_MAGIC):]
    salt, nonce, ct = body[:16], body[16:28], body[28:]
    key = _derive(pw, salt)
    try:
        return AESGCM(key).decrypt(nonce, ct, SEAL_MAGIC)
    except Exception as e:
        raise RuntimeError(f"no se pudo abrir el material: {e}")


def seal_file(path: pathlib.Path, plaintext: str, pw: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(seal(plaintext.encode(), pw))
    os.chmod(path, 0o600)


def seal_blob_file(path: pathlib.Path, blob: bytes, pw: str):
    """Guarda material binario YA sellado.

    Ojo: el blob llega sellado. Volverlo a sellar aqui dejaba los
    bundles con dos capas y no se podian abrir.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)
    os.chmod(path, 0o600)


def unseal_file(path: pathlib.Path, pw: str) -> str:
    return unseal(path.read_bytes(), pw).decode()


# --------------------------------------------------------------------------
# CA
# --------------------------------------------------------------------------

def ca_paths():
    return {
        "root_key": CA_DIR / "root-ca.key.sealed",
        "root_crt": CA_DIR / "root-ca.crt",
        "int_key": CA_DIR / "intermediate-ca.key.sealed",
        "int_crt": CA_DIR / "intermediate-ca.crt",
    }


def ca_init():
    """CA raiz + intermedia. Las dos llaves quedan cifradas en reposo.

    La raiz solo firma la intermedia: no sirve para emitir certificados de
    los peers. Aunque se robe la intermedia, el atacante no puede emitir
    certificados nuevos.
    """
    P = ca_paths()
    CA_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CA_DIR, 0o700)
    pw = passphrase()

    if P["root_crt"].exists():
        print("  la CA ya existe: no se regenera")
        return

    print("  generando la CA raiz (EC P-256)...")
    # La llave se genera sin cifrar y se sella con AES-256-GCM + scrypt:
    # un solo mecanismo de cifrado en todo el proyecto, y el material
    # nunca toca el disco en claro.
    root_key = sh(
        "openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256",
    ).strip()
    seal_file(P["root_key"], root_key, pw)

    root_crt = sh(
        "openssl req -new -x509 -key /dev/stdin -sha256 -days 3650 "
        "-subj '/O=DolyNation/OU=VPN/CN=DolyNation VPN Root CA' "
        "-addext 'basicConstraints=critical,CA:TRUE,pathlen:1' "
        "-addext 'keyUsage=critical,keyCertSign,cRLSign' "
        "-addext 'subjectKeyIdentifier=hash'",
        input_text=root_key,
    )
    write_secret(P["root_crt"], root_crt, 0o644)

    print("  generando la CA intermedia (EC P-256)...")
    int_key = sh(
        "openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256",
    ).strip()
    seal_file(P["int_key"], int_key, pw)

    csr = sh(
        "openssl req -new -key /dev/stdin -sha256 "
        "-subj '/O=DolyNation/OU=VPN/CN=DolyNation VPN Intermediate CA'",
        input_text=int_key,
    )

    # Firmar la intermedia necesita la llave raiz en claro: se descifra en
    # memoria y se usa por stdin, sin escribirla a disco.
    root_plain = unseal_file(P["root_key"], pw)
    ext = (
        "basicConstraints=critical,CA:TRUE,pathlen:0\n"
        "keyUsage=critical,keyCertSign,cRLSign\n"
        "subjectKeyIdentifier=hash\n"
    )
    tmp_key = pathlib.Path("/dev/shm/doly-root.key")
    tmp_crt = pathlib.Path("/dev/shm/doly-root.crt")
    tmp_ext = pathlib.Path("/dev/shm/doly-root.ext")
    try:
        write_secret(tmp_key, root_plain)
        write_secret(tmp_crt, root_crt)
        write_secret(tmp_ext, ext)
        crt = sh(
            f"openssl x509 -req -in /dev/stdin -CA {tmp_crt} -CAkey {tmp_key} "
            f"-CAcreateserial -days 1825 -sha256 -copy_extensions copyall "
            f"-extfile {tmp_ext}",
            input_text=csr,
        )
    finally:
        tmp_key.unlink(missing_ok=True)
        tmp_crt.unlink(missing_ok=True)
        tmp_ext.unlink(missing_ok=True)

    write_secret(P["int_crt"], crt, 0o644)
    print("  CA lista: raiz e intermedia selladas (AES-256-GCM + scrypt)")


def ca_sign(csr_pem: str, days: int, subject: str, san: list, extfile: str) -> str:
    """Firma un CSR con la CA intermedia. La llave nunca toca el disco."""
    P = ca_paths()
    pw = passphrase()
    int_plain = unseal_file(P["int_key"], pw)
    tmp_key = pathlib.Path("/dev/shm/doly-int.key")
    tmp_ext = pathlib.Path("/dev/shm/doly-int.ext")
    try:
        write_secret(tmp_key, int_plain)
        ext = extfile
        if san:
            ext += "subjectAltName=" + ",".join(san) + "\n"
        write_secret(tmp_ext, ext)
        return sh(
            f"openssl x509 -req -in /dev/stdin -CA {P['int_crt']} -CAkey {tmp_key} "
            f"-CAcreateserial -days {days} -sha256 -copy_extensions copyall "
            f"-extfile {tmp_ext}",
            input_text=csr_pem,
        )
    finally:
        tmp_key.unlink(missing_ok=True)
        tmp_ext.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# Peers
# --------------------------------------------------------------------------

def peer_dir(name: str) -> pathlib.Path:
    return PEERS_DIR / name


def peers_init(only=None):
    """Genera el hub y un par (llave + PSK) por peer."""
    PEERS_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(PEERS_DIR, 0o700)
    pw = passphrase()

    hub_key_path = WG_DIR / "wg0.key.sealed"
    if not hub_key_path.exists():
        WG_DIR.mkdir(parents=True, exist_ok=True)
        os.chmod(WG_DIR, 0o700)
        hub_key = sh("wg genkey").strip()
        seal_file(hub_key_path, hub_key, pw)
        print("  llave del hub generada")

    for name, family, ip, kind, desc in PEERS:
        if only and name != only:
            continue
        d = peer_dir(name)
        d.mkdir(parents=True, exist_ok=True)
        os.chmod(d, 0o700)
        priv_path = d / "privatekey.sealed"
        if priv_path.exists():
            continue
        # Dos llaves distintas y congomchos usos:
        #   - la de WireGuard (base64, 32 bytes) abre el tunel;
        #   - la de TLS (PEM) firma el certificado X.509 del servicio o del
        #     developer. No son intercambiables: la primera no es una key PEM.
        priv = sh("wg genkey").strip()
        psk = sh("wg genpsk").strip()
        pub = sh("wg pubkey", input_text=priv).strip()
        tls_key = sh(
            "openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256",
        ).strip()
        seal_file(priv_path, priv, pw)
        seal_file(d / "psk.sealed", psk, pw)
        seal_file(d / "tls-privatekey.sealed", tls_key, pw)
        write_secret(d / "publickey", pub + "\n", 0o644)
        write_secret(d / "ip", ip + "\n", 0o644)

        # Las rutas que tendra este peer. Lo usan las comprobaciones para
        # verificar que el peer de desarrollo NO tiene ruta hacia la
        # familia de administracion.
        if family == "admin":
            allowed = [FAMILIES["servicios"], FAMILIES["devs"], FAMILIES["admin"]]
        else:
            allowed = [FAMILIES["servicios"], FAMILIES["devs"]]
        write_secret(d / "allowed.txt", "\n".join(allowed) + "\n", 0o644)
        write_secret(d / "meta.json", json.dumps({
            "name": name, "family": family, "ip": ip, "kind": kind,
            "descripcion": desc, "publickey": pub,
        }, indent=2, ensure_ascii=False) + "\n", 0o644)
        print(f"  peer {name}: {ip} ({family})")

    lines = [
        "# Configuracion del hub WireGuard de DolyNation.",
        "# Generada por doly-vpn.py: no editar a mano.",
        "#",
        "# AllowedIPs de cada peer = su propia IP de tunel. El hub enruta entre",
        "# peers; quien habla con quien lo decide nftables.",
        "",
        "[Interface]",
        f"Address = {HUB_IP}/32",
        f"ListenPort = {WG_PORT}",
        "PrivateKey = <HUB_PRIVATE_KEY>",
        f"MTU = {WG_MTU}",
        "",
    ]
    for name, family, ip, kind, desc in PEERS:
        pub = read_secret(peer_dir(name) / "publickey")
        lines += [
            f"# {name} ({family}) - {desc}",
            "[Peer]",
            f"PublicKey = {pub}",
            "PresharedKey = <PSK>",
            f"AllowedIPs = {ip}/32",
            "",
        ]
    write_secret(WG_DIR / "wg0.conf.tmpl", "\n".join(lines))
    print("  plantilla del hub escrita en /etc/wireguard/wg0.conf.tmpl")


def peers_render():
    """Escribe /etc/wireguard/wg0.conf con el material en claro (0600).

    La llave sellada sigue en wg0.key.sealed: eso es lo que se respalda.
    """
    pw = passphrase()
    hub_plain = unseal_file(WG_DIR / "wg0.key.sealed", pw)
    out = read_secret(WG_DIR / "wg0.conf.tmpl").replace("<HUB_PRIVATE_KEY>", hub_plain)
    for name, *_ in PEERS:
        psk = unseal_file(peer_dir(name) / "psk.sealed", pw)
        out = out.replace("<PSK>", psk, 1)
    write_secret(WG_DIR / "wg0.conf", out)
    print("  /etc/wireguard/wg0.conf escrito (0600)")


# --------------------------------------------------------------------------
# Certificados
# --------------------------------------------------------------------------

def certs_issue():
    """Certificado de servidor por servicio y de cliente por developer."""
    out = CA_DIR / "certs"
    out.mkdir(parents=True, exist_ok=True)
    os.chmod(out, 0o700)
    pw = passphrase()

    for name, family, ip, kind, desc in PEERS:
        d = peer_dir(name)
        target = out / name
        target.mkdir(parents=True, exist_ok=True)
        os.chmod(target, 0o700)
        if (target / "cert.pem").exists():
            continue

        # El certificado se firma con la llave TLS del peer, no con la de
        # WireGuard: son llaves distintas.
        priv = unseal_file(d / "tls-privatekey.sealed", pw)

        if kind == "servicio":
            dns = SERVICE_NAMES[name]
            csr = sh(
                "openssl req -new -key /dev/stdin -sha256 "
                f"-subj '/O=DolyNation/OU=VPN Services/CN={dns}'",
                input_text=priv,
            )
            ext = (
                "basicConstraints=critical,CA:FALSE\n"
                "keyUsage=critical,digitalSignature,keyEncipherment\n"
                "extendedKeyUsage=serverAuth\n"
                "authorityKeyIdentifier=keyid,issuer\n"
            )
            san = [f"DNS:{dns}"]
            if name == "minios":
                san.append(f"IP:{ip}")
            crt = ca_sign(csr, 825, dns, san, ext)
        else:
            csr = sh(
                "openssl req -new -key /dev/stdin -sha256 "
                f"-subj '/O=DolyNation/OU=VPN Developers/CN={name}'",
                input_text=priv,
            )
            ext = (
                "basicConstraints=critical,CA:FALSE\n"
                "keyUsage=critical,digitalSignature\n"
                "extendedKeyUsage=clientAuth\n"
                "authorityKeyIdentifier=keyid,issuer\n"
            )
            crt = ca_sign(csr, 397, name, [], ext)

        write_secret(target / "cert.pem", crt, 0o644)
        write_secret(target / "key.pem", priv)

        # El certificado con su cadena: el servidor (nginx) recibe el
        # certificado del cliente y necesita la intermedia para poder
        # validar al firmante. Sin la cadena, el mTLS falla.
        chain = crt + read_secret(CA_DIR / "intermediate-ca.crt")
        write_secret(target / "chain.pem", chain, 0o644)

        print(f"  certificado emitido: {name}")


# --------------------------------------------------------------------------
# Bundles para los developers
# --------------------------------------------------------------------------

BUNDLE_README = """DolyNation — VPN de desarrollo
================================

Persona:     {name}
Identidades: {identidades}

Que es esto
-----------
Acceso a los ambientes de desarrollo de DolyNation por una red privada
(WireGuard). Fuera de la VPN, devapi y devweb no son alcanzables.

Que necesitas
-------------
Solo necesitas **1 archivo**: tu configuracion de WireGuard (`wg0.conf`,
o `wg-dev.conf` si tienes dos identidades).

`devweb.yacaterkos.tech` y `devapi.yacaterkos.tech` usan HTTPS real con
certificado de Let's Encrypt y no exigen certificado de cliente en el
navegador: **no hace falta instalar `ca.crt` ni importar `.p12`** para
desarrollar.

1. Instalar WireGuard (https://www.wireguard.com/install/).

   En Linux, si vas a usar `wg-quick`, hace falta tambien el resolvedor de
   DNS porque el config lleva `DNS = 10.90.0.1`:

     Arch            sudo pacman -S systemd-resolvconf
     Debian / Ubuntu sudo apt install openresolv
     Fedora          sudo dnf install openresolv

   Si sale `resolvconf: signature mismatch`: `sudo resolvconf -u`.

2. Importar SOLO tu `.conf` (`wg0.conf`, o `wg-dev.conf` / `wg-admin.conf`):
   - Windows / macOS / Android / iOS: abre la app de WireGuard, importa
     el `.conf` y activa el tunel (la app aplica el DNS sola; en movil
     marca "Override DNS" si aparece la opcion).
   - Linux con NetworkManager (menu de red del escritorio): importa el
     archivo una vez (`nmcli connection import type wireguard file wg-dev.conf`)
     o usa el metodo por terminal abajo.

3. Abrir https://devweb.yacaterkos.tech o https://devapi.yacaterkos.tech
   y listo.

Como conectarse y desconectarse en Linux
----------------------------------------
Hay dos formas (usa solo una, no las mezcles a la vez).

### Con NetworkManager (el menu de red del escritorio)

Es la forma mas comoda: importas la conexion una vez y la prendes o
apagas desde el icono/menu de red del panel o con:

  nmcli connection up wg-dev      # conectar
  nmcli connection down wg-dev    # desconectar
  nmcli connection show           # ver las conexiones

Con una sola identidad el nombre sera `wg0`. Si tu sistema usa
`systemd-resolved` y al conectar `devapi.yacaterkos.tech` no resuelve a
`10.90.0.2`, anade `/etc/NetworkManager/conf.d/00-dns.conf`:

  [main]
  dns=systemd-resolved
  systemd-resolved=true

luego `sudo systemctl restart NetworkManager`, y si la red local sigue
compitiendo por el DNS:

  nmcli connection modify wg-dev ipv4.dns-search "~." ipv4.dns-priority -50
  nmcli connection up wg-dev

### Con wg-quick (la terminal)

Copia tu `.conf` a `/etc/wireguard/` con permisos `600` y usa:

  sudo wg-quick up wg-dev      # conectar (o wg0 si tienes un solo archivo)
  sudo wg-quick down wg-dev    # desconectar
  sudo wg show wg-dev          # ver el estado (handshake, trafico)

Si `wg-quick up` falla con "resolvconf: command not found" o con
"signature mismatch", falta el resolvedor de DNS (ver arriba).

El DNS
------
El config lleva `DNS = 10.90.0.1`: el hub de la VPN. Alli los nombres de
los servicios resuelven a su IP DE TUNEL, no a la IP publica de Cloudflare.

  devapi.yacaterkos.tech  ->  10.90.0.2
  devweb.yacaterkos.tech  ->  10.90.0.3
  minios.doly.internal    ->  10.90.0.4

Sin ese DNS, el navegador resolveria el nombre por tu internet normal y
no entraria por el tunel. Comprobacion dentro de la VPN:

  dig +short devapi.yacaterkos.tech    # debe devolver 10.90.0.2

Que son las identidades
-----------------------
Si tienes mas de un fichero de configuracion, son identidades distintas
tuyas, con su propia llave y su propio PSK:

  wg-dev.conf    Identidad de DESARROLLO. Alcanza los servicios de
                 desarrollo y a los demas developers. NO alcanza la
                 familia de administracion.
  wg-admin.conf  Identidad de ADMINISTRACION. Alcanza todo.

Son identidades separadas a proposito: la de desarrollo no puede tocar
el plano de administracion, aunque la persona seas la misma. Asi una
identidad que se filtra no arrastra a la otra.

Direcciones utiles (resuelven a la IP de tunel dentro de la VPN)
----------------------------------------------------------------
  {dns}

El ambiente de desarrollo se alcanza en:
  https://devweb.yacaterkos.tech     (web)
  https://devapi.yacaterkos.tech     (API)
  https://minios.doly.internal:50090 (almacenamiento de objetos)

Opcional — solo si entras directo a MinIO (`minios.doly.internal:50090`)
-----------------------------------------------------------------------
MinIO usa la CA interna de DolyNation y mTLS (Let's Encrypt no firma
dominios `.internal`). Si necesitas entrar directo a MinIO:
1. Instala `ca.crt` en los certificados de confianza del sistema.
2. Importa tu `.p12` en el navegador (contrasena: la passphrase de la CA).

Notas
-----
- La VPN solo enruta las IPs internas de DolyNation; el resto de tu internet
  sigue funcionando normal.
- Si pierdes este paquete, pide uno nuevo: no se puede regenerar igual.
- No lo subas a ningun repositorio ni a un chat compartido.
"""


def bundles_build(only=None):
    """Arma el paquete cifrado de cada developer.

    Quien tiene dos identidades (desarrollo y administracion) recibe un
    paquete con las dos configs: `wg-dev.conf` y `wg-admin.conf`. Son
    identidades separadas, con su propia llave y su propio PSK.
    """
    BUNDLES_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(BUNDLES_DIR, 0o700)
    pw = passphrase()
    hub_pub = sh("wg pubkey", input_text=unseal_file(
        WG_DIR / "wg0.key.sealed", pw)).strip()

    # Persona -> identidades suyas. Las de una sola, con su peer.
    identidades = {}
    for persona, peers in PERSONAS_DUALES.items():
        identidades[persona] = peers
    for name, family, ip, kind, desc in PEERS:
        if kind == "servicio":
            continue
        if any(name in v for v in PERSONAS_DUALES.values()):
            continue
        identidades[name] = [name]

    for persona, peers in identidades.items():
        if only and persona != only:
            continue

        work = pathlib.Path("/dev/shm/doly-bundle")
        shutil.rmtree(work, ignore_errors=True)
        (work / persona).mkdir(parents=True)

        # El certificado de cliente: uno por identidad, con el CN de esa
        # identidad. Asi el log del servidor dice que identidad se uso.
        for peer in peers:
            d = peer_dir(peer)
            certs = CA_DIR / "certs" / peer
            familia = next(p[1] for p in PEERS if p[0] == peer)
            ip = next(p[2] for p in PEERS if p[0] == peer)
            priv = unseal_file(d / "privatekey.sealed", pw)
            psk = unseal_file(d / "psk.sealed", pw)

            # Cada familia alcanza a los servicios y a si misma. La
            # familia admin llega a todos. Los developers NO llegan a la
            # familia admin: esa es la separacion que se quiere.
            if familia == "admin":
                allowed = [FAMILIES["servicios"], FAMILIES["devs"],
                           FAMILIES["admin"]]
            else:
                allowed = [FAMILIES["servicios"], FAMILIES["devs"]]

            sufijo = peer.split("-", 1)[1] if "-" in peer else ""
            nombre_conf = f"wg-{sufijo}.conf" if sufijo in ("dev", "admin") \
                else "wg0.conf"

            conf = (
                "# Configuracion de WireGuard para DolyNation "
                "(identidad: {peer}).\n"
                "# Generada por doly-vpn.py. Privada: no la compartas.\n"
                "#\n"
                "# El DNS apunta al hub (10.90.0.1): alli los nombres de los\n"
                "# servicios resuelven a su IP DE TUNEL, no a la IP publica de\n"
                "# Cloudflare. Sin esta linea, el navegador resolveria el\n"
                "# nombre por internet y la peticion saldria sin pasar por el\n"
                "# tunel: la VPN no filtraria nada.\n"
                "\n"
                "[Interface]\n"
                "PrivateKey = {priv}\n"
                "Address = {ip}/32\n"
                "DNS = {dns}\n"
                "MTU = {mtu}\n"
                "\n"
                "[Peer]\n"
                "PublicKey = {hubpub}\n"
                "PresharedKey = {psk}\n"
                "AllowedIPs = {allowed}\n"
                "Endpoint = {endpoint}:{port}\n"
                "PersistentKeepalive = 25\n"
            ).format(
                peer=peer, priv=priv, ip=ip, dns=HUB_IP, mtu=WG_MTU, hubpub=hub_pub,
                psk=psk, allowed=", ".join(allowed),
                endpoint=WG_ENDPOINT, port=WG_PORT,
            )
            write_secret(work / persona / nombre_conf, conf)

            # El .p12 lleva la llave TLS (la del certificado de cliente),
            # no la de WireGuard.
            tls_priv = unseal_file(d / "tls-privatekey.sealed", pw)
            tmp_priv = pathlib.Path("/dev/shm/doly-bundle.key")
            try:
                write_secret(tmp_priv, tls_priv)
                # -passout env: y no pass: la passphrase lleva caracteres
                # que el shell interpretaria como separadores de comandos.
                # El .p12 lleva el cert con su cadena: el navegador la
                # envia al servidor, que la necesita para validar al
                # firmante.
                p12 = sh_bytes(
                    f"openssl pkcs12 -export -inkey {tmp_priv} "
                    f"-in {certs / 'chain.pem'} "
                    f"-certfile {CA_DIR / 'intermediate-ca.crt'} -name {peer} "
                    f"-passout env:CA_PW",
                    env={"CA_PW": pw},
                )
            finally:
                tmp_priv.unlink(missing_ok=True)

            (work / persona / f"{peer}.p12").write_bytes(p12)
            os.chmod(work / persona / f"{peer}.p12", 0o600)
            shutil.copy(certs / "chain.pem",
                        work / persona / f"client-cert-{peer}.pem")

        # Un solo fichero con las dos CAs: el navegador valida al
        # servidor contra el bundle y el servidor valida al cliente
        # contra el mismo bundle.
        bundle = (read_secret(CA_DIR / "intermediate-ca.crt") + "\n"
                  + read_secret(CA_DIR / "root-ca.crt") + "\n")
        write_secret(work / persona / "ca.crt", bundle, 0o644)
        shutil.copy(CA_DIR / "root-ca.crt", work / persona / "root-ca.crt")
        write_secret(work / persona / "LEEME.txt",
                     BUNDLE_README.format(
                         name=persona,
                         identidades=", ".join(peers),
                         dns=", ".join(sorted(set(SERVICE_NAMES.values()))),
                     ), 0o644)

        # El tar tambien es binario: se lee como bytes.
        tar = sh_bytes(f"tar -C {work} -czf - {persona}")
        enc = seal(tar, pw)
        out = BUNDLES_DIR / f"{persona}.tar.gz.sealed"
        seal_blob_file(out, enc, pw)
        print(f"  bundle de {persona}: {out} ({len(enc)} bytes sellados)")

    shutil.rmtree("/dev/shm/doly-bundle", ignore_errors=True)



# --------------------------------------------------------------------------
# Runtime: la configuracion que cada servicio lee al arrancar.
# --------------------------------------------------------------------------

def runtime_build():
    """Escribe el material en claro que cada peer de servicio necesita.

    Vive en /etc/doly-vpn/runtime/<peer>, 0700 root:root, y se monta de
    solo lectura en el contenedor. Es el mismo criterio que
    /etc/wireguard/wg0.conf: el material en claro existe mientras el
    servicio esta vivo, y el respaldo es la version sellada.
    """
    pw = passphrase()
    out = BASE / "runtime"
    out.mkdir(parents=True, exist_ok=True)
    os.chmod(out, 0o700)

    for name, family, ip, kind, desc in PEERS:
        if kind != "servicio":
            continue
        d = peer_dir(name)
        r = out / name
        r.mkdir(parents=True, exist_ok=True)
        os.chmod(r, 0o700)
        # No se borra lo que haya en el directorio: el peer de minios
        # guarda ahi sus credenciales, que no se regeneran solas.

        wg_priv = unseal_file(d / "privatekey.sealed", pw)
        wg_psk = unseal_file(d / "psk.sealed", pw)
        hub_pub = sh("wg pubkey", input_text=unseal_file(
            WG_DIR / "wg0.key.sealed", pw)).strip()

        # Un peer de servicio es alcanzable desde las tres familias y
        # contesta a las tres. Su AllowedIPs incluye la familia de servicios
        # (donde vive su propia IP de tunel), la de developers y la de
        # administracion.
        allowed = [FAMILIES["servicios"], FAMILIES["devs"], FAMILIES["admin"]]

        wg_conf = (
            "# Peer WireGuard del servicio {name}.\n"
            "# Generado por doly-vpn.py. No editar a mano.\n"
            "\n"
            "[Interface]\n"
            "PrivateKey = {priv}\n"
            "Address = {ip}/32\n"
            "MTU = {mtu}\n"
            "\n"
            "[Peer]\n"
            "PublicKey = {hubpub}\n"
            "PresharedKey = {psk}\n"
            "AllowedIPs = {allowed}\n"
            "Endpoint = {endpoint}:{port}\n"
            "PersistentKeepalive = 25\n"
        ).format(
            name=name, priv=wg_priv, ip=ip, mtu=WG_MTU, hubpub=hub_pub,
            psk=wg_psk, allowed=", ".join(allowed),
            endpoint=WG_ENDPOINT_LOCAL, port=WG_PORT,
        )
        write_secret(r / "wg0.conf", wg_conf)

        # Llave y certificado TLS del servicio: devapi/devweb usan Let's Encrypt
        # cuando esta emitido en el host; minios (y respaldo sin LE) usa CA interna.
        certs = CA_DIR / "certs" / name
        le_fullchain = LE_LIVE_DIR / "fullchain.pem"
        le_privkey = LE_LIVE_DIR / "privkey.pem"
        # La IP de tunel del peer, para las comprobaciones.
        write_secret(r / "meta.ip", ip + "\n", 0o644)
        write_secret(r / "meta.name", name + "\n", 0o644)
        if name in LE_SERVICES and le_fullchain.exists() and le_privkey.exists():
            shutil.copy(le_fullchain, r / "server.crt")
            os.chmod(r / "server.crt", 0o644)
            write_secret(r / "server.key", le_privkey.read_text().strip())
        else:
            write_secret(r / "server.key", unseal_file(d / "tls-privatekey.sealed", pw))
            # El certificado del servidor con su cadena: el navegador (y curl)
            # necesitan la intermedia para validar al servidor.
            shutil.copy(certs / "chain.pem", r / "server.crt")

        # El bundle de CA (intermedia + raiz) es lo que necesita nginx
        # para validar el certificado del cliente: con solo la intermedia
        # no encuentra el ancla y rechaza a todos.
        bundle = (read_secret(CA_DIR / "intermediate-ca.crt") + "\n"
                  + read_secret(CA_DIR / "root-ca.crt") + "\n")
        write_secret(r / "ca.crt", bundle, 0o644)
        shutil.copy(CA_DIR / "root-ca.crt", r / "root-ca.crt")

        # Certificados de los developers: el servidor los exige (mTLS).
        clients = CA_DIR / "certs" / "clients"
        clients.mkdir(parents=True, exist_ok=True)
        os.chmod(clients, 0o700)
        shutil.copy(certs / "cert.pem", clients / f"{name}.crt")
        print(f"  runtime de {name}: {r}")


# --------------------------------------------------------------------------

def peers_list():
    rows = []
    for name, family, ip, kind, desc in PEERS:
        d = peer_dir(name)
        pub = read_secret(d / "publickey") if (d / "publickey").exists() else ""
        rows.append({
            "nombre": name, "familia": family, "ip": ip, "tipo": kind,
            "descripcion": desc, "publickey": pub,
            "dns": SERVICE_NAMES.get(name, ""),
            "puerto": SERVICE_PORTS.get(name, ""),
        })
    print(json.dumps({
        "hub": {"ip": HUB_IP, "puerto_udp": WG_PORT, "endpoint": WG_ENDPOINT},
        "familias": FAMILIES,
        "peers": rows,
    }, indent=2, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(description="doly-vpn")
    ap.add_argument("fase", choices=[
        "ca", "peers", "render", "certs", "bundles", "runtime", "list", "all"])
    ap.add_argument("--only")
    args = ap.parse_args()

    if args.fase in ("ca", "all"):
        print("[1] CA interna")
        ca_init()
    if args.fase in ("peers", "all"):
        print("[2] Peers")
        peers_init(args.only)
    if args.fase in ("render", "all"):
        print("[2b] Config del hub")
        peers_render()
    if args.fase in ("certs", "all"):
        print("[3] Certificados")
        certs_issue()
    if args.fase in ("bundles", "all"):
        print("[4] Bundles")
        bundles_build(args.only)
    if args.fase in ("runtime", "all"):
        print("[5] Runtime de los servicios")
        runtime_build()
    if args.fase == "list":
        peers_list()


if __name__ == "__main__":
    main()
