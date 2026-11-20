"""Sellado del material secreto de la VPN (AES-256-GCM + scrypt).

Modulo aparte para que otros scripts (los de prueba) puedan abrir el
material sin cargar todo el gestor de la VPN.
"""

import hashlib
import pathlib
import secrets

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SEAL_MAGIC = b"DOLYVPN1"
SCRYPT_N = 2 ** 15
SCRYPT_R = 8
SCRYPT_P = 1


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


