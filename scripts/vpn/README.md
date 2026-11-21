# VPN de DolyNation

Los scripts de la VPN de desarrollo: WireGuard, las tres
familias de red, TLS Let's Encrypt DNS-01 en `devapi`/`devweb` (`MTLS_VERIFY=off`)
y el peer de MinIO con CA interna y mTLS (`MTLS_VERIFY=on`).

**Ninguno de estos ficheros lleva material secreto.** Las llaves
privadas, los PSKs y la passphrase de la CA viven solo en el servidor,
en `/etc/doly-vpn/`, sellados con AES-256-GCM. Este directorio es la
parte publica: la logica, las plantillas y las comprobaciones.

## Que hay aqui

| Fichero | Que hace |
| --- | --- |
| `doly-vpn.py` | CA (raiz + intermedia), peers, certificados, paquetes y runtime |
| `decrypt.py` | Abre un material sellado (la passphrase se pide por terminal) |
| `vpn-firewall.sh` | Reglas de iptables: que entra, que sale y que familia habla con cual |
| `vpn-up.sh` | Levanta y baja el hub y los peers de servicio |
| `vpn-sshd.sh` | Endurece el SSH (puerto 50022, sin root, sin forwarding) |
| `vpn-test.sh` | Comprueba el tunel, el TLS/mTLS y el aislamiento entre familias |
| `vpn-tls-sync.sh` | Copia el cert Let's Encrypt a `runtime/{devapi,devweb}` y recarga nginx |
| `vpn-install.sh` | Instala las unidades de systemd y la persistencia |
| `minio-setup.py` | Crea el bucket y las credenciales de la aplicacion |
| `Dockerfile.peer` | Imagen de los peers de servicio (WireGuard + nginx con mTLS) |
| `Dockerfile.minio` | Imagen del peer de MinIO (binario oficial verificado por SHA256) |
| `entrypoint.sh` | Arranque de un peer de servicio |
| `entrypoint.minio.sh` | Arranque del peer de MinIO |
| `nginx.conf.template` | nginx con mTLS y proxy hacia la aplicacion |
| `docker-compose.vpn.yml` | Los tres peers de servicio |

## Donde se instala

```bash
sudo install -m 0750 doly-vpn.py      /usr/local/sbin/doly-vpn
sudo install -m 0750 vpn-firewall.sh   /etc/doly-vpn/vpn-firewall.sh
sudo install -m 0750 vpn-up.sh         /etc/doly-vpn/vpn-up.sh
sudo install -m 0750 vpn-sshd.sh       /etc/doly-vpn/vpn-sshd.sh
sudo install -m 0750 vpn-test.sh       /etc/doly-vpn/vpn-test.sh
sudo install -m 0750 vpn-tls-sync.sh   /etc/doly-vpn/vpn-tls-sync.sh
sudo install -m 0750 vpn-install.sh    /etc/doly-vpn/vpn-install.sh
sudo install -m 0750 minio-setup.py    /usr/local/sbin/doly-minio-setup
sudo install -m 0750 decrypt.py        /usr/local/sbin/doly-vpn-decrypt
sudo install -m 0755 entrypoint.sh entrypoint.minio.sh /etc/doly-vpn/
sudo install -m 0644 Dockerfile.* nginx.conf.template docker-compose.vpn.yml /etc/doly-vpn/
```

Y el envoltorio que pide la passphrase:

```bash
sudo tee /etc/doly-vpn/vpn-firewall.sh >/dev/null # (ya instalado arriba)
```

`vpn-up.sh` usa `/etc/doly-vpn/vpn-firewall.sh` y
`/etc/doly-vpn/docker-compose.vpn.yml`, asi que todo vive en
`/etc/doly-vpn/`.

## Orden de puesta en marcha

```bash
# 1. La CA (una vez). Pide la passphrase por variable de entorno.
export PASSPHRASE='...'
sudo doly-vpn ca

# 2. Los peers, el hub, los certificados y los paquetes.
sudo doly-vpn peers
sudo doly-vpn render
sudo doly-vpn certs
sudo doly-vpn bundles
sudo doly-vpn runtime

# 3. El firewall y el SSH.
sudo /etc/doly-vpn/vpn-firewall.sh apply
sudo /etc/doly-vpn/vpn-sshd.sh apply

# 4. Las unidades y la persistencia.
sudo /etc/doly-vpn/vpn-install.sh

# 5. Levantar.
sudo /etc/doly-vpn/vpn-up.sh start

# 6. Comprobar.
sudo /etc/doly-vpn/vpn-test.sh
```

> El envoltorio `/usr/local/sbin/doly-vpn-run` (que pide la passphrase
> desde un fichero 600 en vez de la linea de comandos) tambien se
> instala en el servidor.

## Lo que hay que abrir en la OCI

Desde la consola de Oracle Cloud, en la Security List de la VCN:

| Regla | Protocolo | Puerto | Origen |
| --- | --- | --- | --- |
| VPN | UDP | 50443 | `0.0.0.0/0` |
| SSH del bot | TCP | 50022 | `0.0.0.0/0` (el firewall filtra por los rangos de GitHub Actions) |

El `22` se puede cerrar cuando el bot entre por el `50022`.

## Documentacion

- [`conventions/vpn.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/vpn.md) — las reglas.
- [`operations/VPN.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/VPN.md) — el runbook.
