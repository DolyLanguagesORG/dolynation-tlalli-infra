#!/usr/bin/env python3
"""Abre un material sellado por doly-vpn.py.

    decrypt.py <fichero.sealed> <salida>

La passphrase se pide por terminal (no por linea de comandos: un `ps` de
otro usuario no debe poder leerla).
"""

import getpass
import hashlib
import pathlib
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"DOLYVPN1"
SCRYPT_N = 2 ** 15
SCRYPT_R = 8
SCRYPT_P = 1


def main():
    if len(sys.argv) != 3:
        print("uso: decrypt.py <fichero.sealed> <salida>", file=sys.stderr)
        sys.exit(1)

    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])

    pw = getpass.getpass("passphrase: ")
    data = src.read_bytes()
    if not data.startswith(MAGIC):
        print("ERROR: el fichero no esta sellado con el formato esperado",
              file=sys.stderr)
        sys.exit(1)

    salt, nonce, ct = data[8:24], data[24:36], data[36:]
    key = hashlib.scrypt(pw.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R,
                         p=SCRYPT_P, dklen=32, maxmem=64 * 1024 * 1024)
    try:
        plain = AESGCM(key).decrypt(nonce, ct, MAGIC)
    except Exception:
        print("ERROR: no se pudo abrir (passphrase incorrecta o fichero "
              "alterado)", file=sys.stderr)
        sys.exit(1)

    dst.write_bytes(plain)
    os_mode = 0o600
    dst.chmod(os_mode)
    print(f"abierto: {dst} ({len(plain)} bytes)")


if __name__ == "__main__":
    main()
