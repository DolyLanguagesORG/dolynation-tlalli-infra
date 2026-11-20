#!/usr/bin/env python3
"""Abre los paquetes de la VPN (sellados) y comprueba que estan completos.

    abrir-paquetes.py <carpeta> <passphrase>

Cada paquete sale como `<peer>.tar.gz`, con sus permisos restringidos: el
paquete lleva la llave privada del peer, asi que no puede quedar en un
sitio de mundo legible.
"""

import pathlib
import sys
import tarfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"DOLYVPN1"
SCRYPT_N = 2 ** 15
SCRYPT_R = 8
SCRYPT_P = 1

# Lo que tiene que traer cada paquete. Las identidades duales traen
# varias configs (wg-dev.conf / wg-admin.conf) y un .p12 por identidad.
ESPERADO = [
    "ca.crt",
    "root-ca.crt",
    "LEEME.txt",
]


def abrir(blob: bytes, passphrase: str) -> bytes:
    if not blob.startswith(MAGIC):
        raise RuntimeError("el fichero no esta sellado con el formato esperado")
    salt, nonce, ct = blob[8:24], blob[24:36], blob[36:]
    import hashlib
    key = hashlib.scrypt(passphrase.encode(), salt=salt, n=SCRYPT_N,
                         r=SCRYPT_R, p=SCRYPT_P, dklen=32,
                         maxmem=64 * 1024 * 1024)
    return AESGCM(key).decrypt(nonce, ct, MAGIC)


def main():
    if len(sys.argv) != 3:
        print("uso: abrir-paquetes.py <carpeta> <passphrase>", file=sys.stderr)
        return 1

    carpeta = pathlib.Path(sys.argv[1])
    passphrase = sys.argv[2]
    fallos = 0

    for sellado in sorted(carpeta.glob("*.tar.gz.sealed")):
        peer = sellado.name.replace(".tar.gz.sealed", "")
        destino = carpeta / f"{peer}.tar.gz"
        try:
            datos = abrir(sellado.read_bytes(), passphrase)
        except Exception as e:
            print(f"  {peer}: NO se pudo abrir ({e})")
            fallos += 1
            continue

        destino.write_bytes(datos)
        destino.chmod(0o600)

        # Se comprueba el contenido: un paquete incompleto no sirve.
        with tarfile.open(destino, "r:gz") as tar:
            nombres = {pathlib.Path(n).name for n in tar.getnames()}
        faltan = [f for f in ESPERADO if f not in nombres]
        configs = [n for n in nombres if n.startswith("wg")
                   and n.endswith(".conf")]
        p12 = [n for n in nombres if n.endswith(".p12")]

        if faltan or not configs or not p12:
            print(f"  {peer}: INCOMPLETO (faltan {faltan or 'config o .p12'})")
            fallos += 1
            continue

        # Cada identidad tiene su config y su .p12. Los nombres no
        # coinciden (wg-dev.conf frente a jxadevp-dev.p12), asi que se
        # comprueba que haya tantos .p12 como identidades.
        identidades = {n[:-5] for n in configs}
        if len(p12) != len(identidades):
            print(f"  {peer}: INCOMPLETO ({len(configs)} configs y "
                  f"{len(p12)} certificados)")
            fallos += 1
            continue

        ids_p12 = sorted(n[:-4] for n in p12)
        print(f"  {peer}: OK  ({len(datos)} bytes, {len(configs)} identidad(es): "
              f"{', '.join(ids_p12)})")
        sellado.unlink()

    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
