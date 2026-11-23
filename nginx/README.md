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
| `dolynation.conf` | Los vhosts públicos de `staging` (`staging`, `stagingplay`) y `prod` (`dolynation.app`, `www`, `play`). Desarrollo vive en la VPN |

## Instalación

```bash
# 1. Certificados (el CSR se genera en el servidor; la clave privada nunca sale)
sudo mkdir -p /etc/ssl/dolynation
sudo openssl req -new -newkey rsa:2048 -nodes \
  -keyout /etc/ssl/dolynation/origin.key -out /etc/ssl/dolynation/origin.csr \
  -subj "/CN=dolynation.app" \
  -addext "subjectAltName=DNS:dolynation.app,DNS:*.dolynation.app"

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

Los registros DNS públicos (`dolynation.app`, `www`, `play`, `staging`,
`stagingplay`) deben apuntar a la IP del servidor con la **nube naranja**
(proxied). Con la nube gris, el certificado de origen no se usa y el navegador
negocia TLS directamente contra el servidor.

Los tres subdominios de desarrollo (`devplay`, `devapi`, `dev`) son
**solo por VPN** (`10.90.0.2/3/5`), llevan **nube gris** (DNS Only, sin `AAAA`)
y usan TLS de Let's Encrypt dentro de sus contenedores peer.

## Cambiar el dominio público

El `server_name` de esta configuración es el **único lugar del código** donde
aparece el dominio público de staging y producción. El frontend no lo conoce: su
`BACKEND_INTERNAL_URL` es interno en los 4 ambientes
(`http://backend:3333/api/v1`, por la red de compose).

Al cambiar el dominio hay que tocar **3 cosas**, y solo una es este archivo:

| # | Dónde | Qué | ¿Requiere código? |
| --- | --- | --- | --- |
| 1 | **este archivo** (`server_name`) | el ruteo de `stagingplay` / `staging` / `play` / `dolynation.app` | **Sí** |
| 2 | `NEXT_ALLOWED_DEV_ORIGINS` (variable del environment `desarrollo` de `dolynation-tonatiuh-front`) | el websocket de HMR | **No** |
| 3 | `FRONTEND_BASE_URL` (variable del environment correspondiente de `dolynation-atl-back`) | los enlaces de los correos transaccionales | **No** |

1. **DNS / Cloudflare** → apuntar el host nuevo al servidor y emitir el
   certificado de origen si hace falta.
2. **Este archivo** → `server_name` del host nuevo (y `upstream` si cambian los
   puertos). PR a `develop` y el deploy.
3. **`NEXT_ALLOWED_DEV_ORIGINS`** → el patrón del dominio nuevo. Admite
   comodines: `**.dolynation.app` matchea cualquier subdominio (no el apex).
   Redeploy del frontend.
4. **`FRONTEND_BASE_URL`** → la URL pública nueva (y actualizar OAuth / Turnstile / Stripe). Redeploy del backend.

> La variable 2 solo aplica al **dev server**: en rehearsal, staging y
> producción la app corre compilada (`output: 'standalone'`), sin HMR y sin
> websocket.
>
> `rehearsal` **no tiene `server_name`**: no sale a internet y se accede por
> puerto (`5704x`) desde el propio servidor.

El procedimiento completo está en
[`operations/PLAN-DE-DESPLIEGUE.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/PLAN-DE-DESPLIEGUE.md).
