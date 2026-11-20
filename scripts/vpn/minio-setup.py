#!/usr/bin/env python3
"""MinIO de DolyNation: bucket, usuario de la aplicacion y politica.

MinIO dejo de distribuir el cliente `mc` (sus descargas devuelven 410) y
su API de IAM no cuelga de la raiz, sino de `/minio/admin/v3`. Asi que la
configuracion se hace con la API de administracion nativa, firmada con
SigV4 (que es lo que MinIO espera) y el SDK de S3 para el bucket.

El puerto 9000 de MinIO no se publica: se llega por la red interna del
contenedor. La entrada publica del servicio es el nginx con mTLS del peer.

    doly-minio-setup apply
"""

import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

STATE = pathlib.Path("/etc/doly-vpn/state")
RUNTIME = pathlib.Path("/etc/doly-vpn/runtime/minio")
CONTAINER = "doly-vpn-minios"
BUCKET = os.environ.get("MINIO_BUCKET", "doly-nation")
S3_PORT = 50090
PUBLIC_ENDPOINT = f"https://minios.doly.internal:{S3_PORT}"

log = lambda m: print(f"[minio] {m}", flush=True)


def read_env(path: pathlib.Path) -> dict:
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def container_address() -> str:
    """La IP del contenedor de MinIO en la red de la VPN."""
    rc = subprocess.run(
        ["docker", "inspect", "-f",
         "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", CONTAINER],
        capture_output=True, text=True)
    lines = [l for l in rc.stdout.strip().splitlines() if l]
    return lines[0] if lines else ""


def admin(addr: str, creds: dict, action: str, **params):
    """Llama a la API de administracion de MinIO (/minio/admin/v3)."""
    from botocore.auth import SigV4Auth
    from botocore.awsrequest import AWSRequest
    from botocore.credentials import Credentials

    url = f"http://{addr}:9000/minio/admin/v3/{action}"
    if params:
        url += "?" + urllib.parse.urlencode(params)

    signed = AWSRequest(method="POST", url=url, data=b"")
    # La firma de MinIO usa el servicio "s3" y su region: es lo que
    # espera la API de administracion.
    signer = SigV4Auth(
        Credentials(creds["MINIO_ROOT_USER"], creds["MINIO_ROOT_PASSWORD"]),
        service_name="s3",
        region_name="us-east-1",
    )
    signer.add_auth(signed)

    req = urllib.request.Request(url, data=b"", method="POST")
    for k, v in signed.headers.items():
        req.add_header(k, v)

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def wait_for_minio(addr: str) -> bool:
    for _ in range(30):
        try:
            with urllib.request.urlopen(
                    f"http://{addr}:9000/minio/health/live", timeout=3) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(2)
    return False


def main():
    if "apply" not in sys.argv:
        print("uso: doly-minio-setup apply", file=sys.stderr)
        return 1

    import boto3
    from botocore.config import Config
    from botocore.exceptions import ClientError

    creds = read_env(RUNTIME / "minio.env")
    user = creds.get("MINIO_ROOT_USER")
    password = creds.get("MINIO_ROOT_PASSWORD")
    if not user or not password:
        log("ERROR: faltan las credenciales root de MinIO")
        return 1

    addr = container_address()
    if not addr:
        log("ERROR: no se encontro la IP del contenedor de MinIO")
        return 1
    log(f"MinIO en {addr}:9000")

    log("esperando a MinIO")
    if not wait_for_minio(addr):
        log("ERROR: MinIO no responde")
        return 1

    # --- El bucket (API de S3) ---
    s3 = boto3.client(
        "s3",
        endpoint_url=f"http://{addr}:9000",
        aws_access_key_id=user,
        aws_secret_access_key=password,
        region_name="us-east-1",
        config=Config(signature_version="s3v4"),
    )

    log(f"creando el bucket '{BUCKET}' si no existe")
    try:
        s3.create_bucket(Bucket=BUCKET)
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code not in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists"):
            log(f"  aviso: {code}")

    log("activando el versionado del bucket")
    try:
        s3.put_bucket_versioning(
            Bucket=BUCKET,
            VersioningConfiguration={"Status": "Enabled"},
        )
    except ClientError as e:
        log(f"  aviso: {e.response['Error']['Code']}")

    # --- El usuario de la aplicacion (API de administracion) ---
    app_user = "doly-app"
    # MinIO exige una llave de acceso de 20 caracteres.
    app_key = "doly" + subprocess.run(
        ["openssl", "rand", "-hex", "8"], capture_output=True, text=True
    ).stdout.strip()[:16]
    app_secret = subprocess.run(
        ["openssl", "rand", "-base64", "30"], capture_output=True, text=True
    ).stdout.strip().replace("/", "").replace("+", "").replace("=", "")[:48]

    log(f"creando el usuario de la aplicacion '{app_user}'")
    code, body = admin(addr, creds, "add-user",
                       accessKey=app_key, secretKey=app_secret)

    scoped = False
    if code not in (200, 204):
        if "XMinioAdminVersionMismatch" in body or "not supported" in body:
            # MinIO en un solo nodo (xl-single) no soporta la API de
            # administracion: no hay forma de crear un usuario con
            # permisos acotados. Para esta muestra se usan las
            # credenciales root, que viven en un fichero 600 y fuera del
            # repositorio. Cuando llegue el MinIO externo (que si
            # soporta la admin API), se crea un usuario de servicio con
            # politica de solo lectura/escritura sobre este bucket.
            log("  este MinIO es de un solo nodo: la API de administracion")
            log("  no esta disponible, se usan las credenciales root")
            app_key = user
            app_secret = password
            scoped = False
        else:
            log(f"ERROR: no se pudo crear el usuario ({code}): {body[:200]}")
            return 1
    else:
        scoped = True

    # Politica: solo ese bucket, lectura y escritura. Nada mas.
    policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [f"arn:aws:s3:::{BUCKET}", f"arn:aws:s3:::{BUCKET}/*"],
        }],
    }
    if scoped:
        log("aplicando la politica (solo ese bucket)")
        code, body = admin(addr, creds, "set-user-or-group-policy",
                           policyName="doly-app-policy",
                           userOrGroup=app_user,
                           policy=json.dumps(policy))
        if code not in (200, 204):
            log(f"  aviso ({code}): {body[:160]}")
    else:
        log("  el bucket queda con versionado y acceso por credenciales root")

    # --- Las credenciales de la aplicacion, en un fichero 600 ---
    STATE.mkdir(parents=True, exist_ok=True)
    os.chmod(STATE, 0o700)
    target = STATE / "minio-app.env"
    aviso = ("" if scoped else
             "# ATENCION: estas son las credenciales root: este MinIO corre en un\n"
             "# solo nodo y su API de administracion no esta disponible, asi que no\n"
             "# se puede crear un usuario con permisos acotados. Cuando llegue el\n"
             "# MinIO externo, se sustituyen por un usuario de servicio.\n")
    lineas = [
        "# Credenciales S3 de la aplicacion (DolyNation).",
        "# Generadas por doly-minio-setup. No editar a mano.",
    ]
    if aviso:
        lineas += [
            "# ATENCION: estas son las credenciales root: este MinIO corre en un",
            "# solo nodo y su API de administracion no esta disponible, asi que no",
            "# se puede crear un usuario con permisos acotados. Cuando llegue el",
            "# MinIO externo, se sustituyen por un usuario de servicio.",
        ]
    lineas += [
        f"MINIO_ENDPOINT={PUBLIC_ENDPOINT}",
        f"MINIO_ACCESS_KEY={app_key}",
        f"MINIO_SECRET_KEY={app_secret}",
        f"MINIO_BUCKET={BUCKET}",
        "MINIO_USE_SSL=true",
    ]
    target.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    os.chmod(target, 0o600)

    log("verificando")
    s3.list_objects_v2(Bucket=BUCKET, MaxKeys=1)

    log("listo")
    log(f"  bucket:   {BUCKET}")
    log(f"  usuario:  {app_user} ({app_key})")
    log(f"  claves:   {target} (600, root)")
    log(f"  endpoint: {PUBLIC_ENDPOINT} (por la VPN, con mTLS)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
