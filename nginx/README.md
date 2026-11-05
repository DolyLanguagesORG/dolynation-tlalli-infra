# Proxy inverso — DolyNation

Configuración de **nginx** que publica los entornos de DolyNation detrás de
Cloudflare.

## Qué resuelve

Los contenedores escuchan **solo en `127.0.0.1`** (ver
[`docker-compose.dev.yml`](../docker-compose.dev.yml)): el único que llega a
ellos es este proxy. Así, PostgreSQL no queda accesible desde internet y los
puertos del backend tampoco.

## Topología

```
Internet ──HTTPS──► Cloudflare ──HTTPS──► nginx (443) ──► 127.0.0.1:5701x
                            (cert de            (cert de
                             borde)              origen)
```

Cloudflare se encarga del TLS con el navegador. El tramo Cloudflare → origen
va cifrado con el **Origin Certificate**, que solo vale entre Cloudflare y el
servidor. Esa es exactamente la propiedad que se quiere: **el navegador nunca
habla TLS con el origen**, y el certificado de origen no sale del servidor.

## Ficheros

| Fichero | Qué es |
| --- | --- |
| `dolynation.conf` | Los vhosts de `devweb` y `devapi` |

## Instalación

```bash
# 1. Certificados (el CSR se genera en el servidor; la clave privada nunca sale)
sudo mkdir -p /etc/ssl/dolynation
sudo openssl req -new -newkey rsa:2048 -nodes \
  -keyout /tmp/origin.key -out /etc/ssl/dolynation/origin.csr \
  -subj "/CN=devweb.yakatercos.tech" \
  -addext "subjectAltName=DNS:devweb.yakatercos.tech,DNS:devapi.yakatercos.tech"

# 2. En el panel de Cloudflare: SSL/TLS > Origin Server > Create Certificate
#    (pegar el CSR, tipo RSA, validez 15 anos). Guardar el .pem como:
sudo install -m 644 origin.pem /etc/ssl/dolynation/origin.pem
sudo install -m 600 origin.key /etc/ssl/dolynation/origin.key

# 3. Configuracion
sudo install -m 644 nginx/dolynation.conf /etc/nginx/sites-available/dolynation.conf
sudo ln -sf /etc/nginx/sites-available/dolynation.conf /etc/nginx/sites-enabled/dolynation.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

## Puertos

| Puerto | Quién lo abre | Motivo |
| --- | --- | --- |
| `22` | SSH | El deploy de GitHub Actions entra por aquí |
| `80` | nginx | Solo para redirigir a HTTPS |
| `443` | nginx | Lo recibe Cloudflare |

Los puertos `57010`-`57012` **no se abren**: solo escuchan en `127.0.0.1`.

## Nota sobre el DNS

Los registros DNS de `devweb` y `devapi` deben apuntar a la IP del servidor
con la **nube naranja** (proxied). Con la nube gris, el certificado de origen
no se usa y el navegador negotiate TLS directamente contra el servidor.

Para staging y producción se replica esta configuración cambiando los
dominios y los puertos de los `upstream`.
