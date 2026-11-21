# Changelog

Todas las novedades relevantes de este repositorio se registran aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado es [SemVer](https://semver.org/lang/es/).

La **versión vive en `version.txt`**: el tag de la release y el `CHANGELOG.md`
deben coincidir con ella. El versionado es automático: `release-please` mantiene
un PR de release contra `develop` que sube la versión y escribe esta sección; al
mergearlo se crean el tag anotado y la GitHub Release. Ver
[`conventions/versioning.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md).

## [0.15.3](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.15.2...v0.15.3) (2026-11-21)


### Bug Fixes

* **infra:** el resumen mostraba el app_version en la columna de cada repo ([#249](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/249)) ([90388f2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/90388f2ae2df1142c18cf77f93381ce78190a1ea))

## [0.15.2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.15.1...v0.15.2) (2026-11-21)


### Bug Fixes

* **infra:** el bot del manifiesto se quedaba esperando por un campo que no existe ([#244](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/244)) ([72ebfec](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/72ebfec9691bfc8ffcae18753ed71b48eef24748)), closes [#245](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/245)

## [0.15.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.15.0...v0.15.1) (2026-11-21)


### Bug Fixes

* **infra:** el site_version del manifesto salia con el texto de una busqueda ([#241](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/241)) ([d138bf7](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/d138bf73823433d42f9d27aa8ed7ab7798681527)), closes [#240](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/240)

## [0.15.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.14.0...v0.15.0) (2026-11-21)


### Features

* **infra:** la landing entra en el flujo multirepo ([#235](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/235)) ([e9959cf](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e9959cfc32be3a56667ad14ecb57739e7c1c9a4f)), closes [#234](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/234)
* **vpn:** peer devsite para la landing del ambiente de desarrollo ([#237](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/237)) ([1426dd7](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/1426dd73bd2b7e6fadcb4f596e198ced4e944cf2)), closes [#234](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/234)

## [0.14.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.13.0...v0.14.0) (2026-11-21)


### Features

* **infra:** agrega schema y variables de despliegue para google oauth ([#229](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/229)) ([460134a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/460134a1bc77494b5cc65b249fb2899a4e707299))

## [0.13.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.12.0...v0.13.0) (2026-11-21)


### Features

* **vpn:** el config no lleva DNS y el instalador deja todo listo ([#224](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/224)) ([87ecd21](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/87ecd210181414f8f39980f844b0534e7caa18b5)), closes [#214](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/214)

## [0.12.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.11.1...v0.12.0) (2026-11-21)


### Features

* **vpn:** acceso simple sin mTLS con TLS Let's Encrypt DNS-01 y LEEME actualizado ([#220](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/220)) ([e53bea6](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e53bea68d820943679c189821badbe113b660414)), closes [#214](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/214)


### Bug Fixes

* **vpn:** el LEEME avisa del resolvedor de DNS y el hub no publica AAAA ([#218](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/218)) ([95f5925](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/95f592598522639caae575eb11efb218577bd9c7)), closes [#214](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/214)

## [0.11.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.11.0...v0.11.1) (2026-11-20)


### Bug Fixes

* **vpn:** los puertos pasan a 58376 (VPN) y 59253 (SSH del bot) ([#215](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/215)) ([3578987](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/357898795ebc03b194db30f80af384b28fc84748)), closes [#208](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/208)

## [0.11.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.10.0...v0.11.0) (2026-11-20)


### Features

* **vpn:** DNS de tunel para los servicios y origen solo tras Cloudflare ([#205](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/205)) ([921b2da](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/921b2dae3eaabea3b7d0fdaf5a7fe240892f1917))


### Reverts

* **deploy:** el .env del backend lo escribe el workflow del backend ([#212](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/212)) ([74957af](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/74957af9cbf403deaabc398b3b69477c9dc689c3)), closes [#208](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/208)

## [0.10.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.9.0...v0.10.0) (2026-11-20)


### Features

* **vpn:** identidades duales de desarrollo y administracion ([#200](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/200)) ([4644e32](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/4644e32e02b5d67ac762a0a678d2fb4c604f1359)), closes [#97](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/97)


### Bug Fixes

* **deploy:** el deploy de desarrollo escribe el .env del backend ([#202](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/202)) ([f66308c](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/f66308c83ae8180b1c942bdf44bae0c399fd1e57))

## [0.9.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.8.0...v0.9.0) (2026-11-20)


### Features

* **billing:** agrega tablas, variables y webhook stripe en nginx ([#197](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/197)) ([1dd1195](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/1dd119522ec992aefc0996e99fde6658baf4f1ee))

## [0.8.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.7.0...v0.8.0) (2026-11-20)


### Features

* **vpn:** los scripts de la VPN de desarrollo ([#190](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/190)) ([31d79cf](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/31d79cfaee8783f3432674d8655f50bb5d4e497d)), closes [#97](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/97)

## [0.7.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.6...v0.7.0) (2026-11-19)


### Features

* **db:** agrega roles, solicitudes de acceso y tablas de logs ([#185](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/185)) ([5ead93d](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/5ead93da8942957265c3ceded6047001d92f58bd))

## [0.6.6](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.5...v0.6.6) (2026-11-18)


### Bug Fixes

* **deploy:** la version de la aplicacion la inyecta el deploy ([#176](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/176)) ([95f64a6](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/95f64a6fae2d9f23fe4ea11a5df9dac5eab58718)), closes [#121](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/121)

## [0.6.5](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.4...v0.6.5) (2026-11-16)


### Bug Fixes

* **db:** el backend usa las mismas credenciales que la base ([#160](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/160)) ([d57634a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/d57634ac455ae1f4fd205662258283aa87be9d33)), closes [#159](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/159)

## [0.6.4](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.3...v0.6.4) (2026-11-15)


### Bug Fixes

* **schema:** el schema vive en un solo archivo y se aplica en cada deploy ([#152](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/152)) ([39c4adf](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/39c4adf0b41e0235e90ccee3b140d2c7b218a0cc)), closes [#112](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/112)

## [0.6.3](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.2...v0.6.3) (2026-11-15)


### Bug Fixes

* **kanban:** leer la accion del evento y no el nombre del step ([#146](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/146)) ([e45f2b3](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e45f2b3c8ae7054f9ab20cb6042d4d0f33c23f05)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)

## [0.6.2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.1...v0.6.2) (2026-11-15)


### Bug Fixes

* **kanban:** detecta si un numero es issue o pull request ([#139](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/139)) ([ec65aff](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/ec65aff7137513a0034512f54daa77520a38c90f)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)

## [0.6.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.6.0...v0.6.1) (2026-11-12)


### Bug Fixes

* **release:** el paso del manifiesto usaba una variable que no existe ([#134](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/134)) ([78d6011](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/78d6011169054288516bd59eebf45ee0236b578e)), closes [#76](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/76)

## [0.6.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.5.0...v0.6.0) (2026-11-12)


### Features

* **release:** el PR del manifiesto se mergea solo cuando la CI esta en verde ([#132](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/132)) ([801d9bd](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/801d9bd7d26713d6f6dd6424e5653e7e5fcf0338)), closes [#76](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/76)

## [0.5.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.4.0...v0.5.0) (2026-11-12)


### Features

* **kanban:** las issues pasan a 'In Review' solas ([#119](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/119)) ([d8fcadc](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/d8fcadcf9165d23685afa591be0e879f853fd98a)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **kanban:** las issues pasan a 'In Review' solas ([#120](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/120)) ([5069726](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/5069726366181c9ed15bf33b3c6e8691c7a74020)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **kanban:** las issues pasan a 'In Review' solas ([#121](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/121)) ([ec78bfa](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/ec78bfa6dbdf475e4838a408ce27aa535382e4aa)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **kanban:** las issues pasan a 'In Review' solas ([#122](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/122)) ([29abe66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/29abe66204005075afd7da206d21589fa700170d)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **kanban:** las issues pasan a 'In Review' solas ([#123](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/123)) ([9692615](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/9692615702b95bfd1ecfd4df2c1befa67bb77b20)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **kanban:** las issues pasan a 'In Review' solas ([#124](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/124)) ([8e05c62](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/8e05c6299a1f88af83334a79b0ae21db47b30dab)), closes [#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)
* **release:** la cascada tambien promueve la documentacion ([#111](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/111)) ([93306e9](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/93306e9b98bc7412f60d09cc186269d4f14d7bcd)), closes [#8](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/8)
* **schema:** agregar soporte de suscripciones y explicaciones en postgres ([#118](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/118)) ([4b908a7](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/4b908a779bf1f419edff9d07309c347e5c520a75))
* **smtp:** que las variables de correo lleguen al contenedor ([#116](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/116)) ([a559fdb](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/a559fdb6c3e14179b1a0b34310563c44b2275396)), closes [#102](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/102)


### Bug Fixes

* **ci:** endurecer el despliegue (permisos del .env y llave del host) ([#114](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/114)) ([ae0ce1e](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/ae0ce1ec9d37aac97d8bab0a7d46ce5a2931195a)), closes [#6](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/6)
* **ci:** quitar las claves duplicadas de los deploys y validar los workflows con actionlint ([#125](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/125)) ([0c2f1a2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/0c2f1a2a9a0da9e4bbe20e3f6a1bc5dd78430a8b)), closes [#102](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/102)
* **ci:** validar la rama normalizada (los acentos no bloquean el PR) ([#113](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/113)) ([9b66fc0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/9b66fc0d221d6a3e8879f6ea25706341a3d2e5cc)), closes [#46](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/46)
* **compose:** quitar las claves SMTP duplicadas del compose ([#126](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/126)) ([c490234](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/c49023463d2563be3e722a025bd911dbbf35d539))
* **deploy:** staging espera a que el ambiente de simulacion termine ([#109](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/109)) ([6ea8c0a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/6ea8c0aa393eaee0a22e81dddb9e00c53d290bcd)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)

## [0.4.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.3.4...v0.4.0) (2026-11-09)


### Features

* **schema:** tabla admins y skill de CI/CD al dia ([#101](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/101)) ([bd82170](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/bd821705893dd2d8e5db937e97435ce807457fb9)), closes [#22](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/22)
* **schema:** tabla user_settings ([#103](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/103)) ([a04df8a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/a04df8a0485e49362a9ade8073aca3e25dc307b5)), closes [#22](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/22)


### Bug Fixes

* **deploy:** staging verifica el ambiente de simulacion en el momento ([#99](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/99)) ([f6833d8](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/f6833d80c9b2f813062e26c2909c6e46f1b9fc83)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)

## [0.3.4](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.3.3...v0.3.4) (2026-11-09)


### Bug Fixes

* **deploy:** el gate de rehearsal debe buscar cualquier smoke en verde ([#94](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/94)) ([b216a96](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/b216a96a1f5ea4d7a05e20373c201f5bb2673f23)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)
* **deploy:** enviar los archivos del ambiente por stdin del ssh ([#93](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/93)) ([be8faf5](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/be8faf5ac1eba88e45336a3a1c6f513e14df4d7d)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)
* **deploy:** subir al servidor los archivos del commit que se despliega ([#90](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/90)) ([8cfe8fc](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/8cfe8fc6bc72da4766409121a64748162a63a4bf)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)
* **deploy:** una etiqueta de imagen por servicio y manifiesto de develop ([#92](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/92)) ([16b4f0d](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/16b4f0db39c6882a256c9322629da98443dd4b56)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)
* **versions:** la coherencia del manifiesto es aviso, no error ([#88](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/88)) ([857d938](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/857d93887f6cc84b99c5e2b4c1487ea53bc8b92b)), closes [#27](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/27)

## [0.3.3](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.3.2...v0.3.3) (2026-11-09)


### Bug Fixes

* **deploy:** cablear el circuito real rc -&gt; rehearsal -&gt; staging -&gt; main ([#82](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/82)) ([02490e7](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/02490e7a6e2bdd8d2f105a7c068362dab46aa276)), closes [#13](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/13)

## [0.3.2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.3.1...v0.3.2) (2026-11-09)


### Bug Fixes

* **release:** activar el auto-merge aunque el PR de release ya exista ([#66](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/66)) ([e8f3086](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e8f3086c045c9918e47ad09225570603127daf1c)), closes [#4](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/4)
* **versions:** usar el PAT para pedir el SHA del tag ([#77](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/77)) ([487bb03](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/487bb033adbd64cb93719f6a4fd94559ef88eb44)), closes [#27](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/27)

## [0.3.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.3.0...v0.3.1) (2026-11-08)


### Bug Fixes

* **versions:** anadir el commit que faltaba en la fila de infra ([#74](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/74)) ([08029dd](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/08029ddb5dc732ccfbac02bfbce1061bda589706)), closes [#27](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/27)
* **versions:** corregir el SHA y el grupo de concurrencia del manifiesto ([#71](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/71)) ([7990ca9](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/7990ca915880ff7e52316d5d26ff5632042cc190)), closes [#27](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/27)

## [0.3.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.2.1...v0.3.0) (2026-11-08)


### Features

* **infra:** staging y produccion desplegados por imagen ([#68](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/68)) ([57f33a4](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/57f33a422418b1e0114b639fb527c1c86c341b67)), closes [#43](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/43) [#44](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/44)


### Bug Fixes

* **ci:** enviar el nombre del repositorio en el aviso al manifiesto ([#56](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/56)) ([af9b690](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/af9b6908b695b252ae50599da9e34fab727248f0))

## [0.2.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.2.0...v0.2.1) (2026-11-06)


### Bug Fixes

* **ci:** separar el checkout del paso que anota el tag ([#54](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/54)) ([98bea3c](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/98bea3ca377c32603f3c6ffeb6a727b262e92a0e))
* **manifest:** corregir la actualizacion de la fila en el manifiesto ([#53](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/53)) ([82ada34](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/82ada34c66e7602685d3b26c7641c93e7b379d79))

## [0.2.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.1.0...v0.2.0) (2026-11-06)


### Features

* **nginx:** anadir el proxy inverso de los entornos ([#37](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/37)) ([358f180](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/358f1803d3d5a8c58ed1ba1a5148a6c989f63a16))


### Bug Fixes

* **ci:** compartir el agente SSH entre todos los pasos del workflow ([#38](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/38)) ([e941a6f](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e941a6fa5b34b5b12501ffb7bb59d558dd9f74bb))
* **ci:** reportar el estado del deployment a GitHub ([#39](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/39)) ([cc2ae22](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/cc2ae2218bb0f1b516ce0d99fe93289933e590d1))
* **deploy:** preparar el servidor nuevo y desplegar con la llave cifrada ([#36](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/36)) ([5a85760](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/5a8576034a745af69d2bcfdde8a8a96595c80cbc))
* **nginx:** corregir el dominio a yacaterkos.tech ([#41](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/41)) ([956139a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/956139af859a5f05efda157e6461fdae7a53a44a))

## [No publicado]

### Añadido
- `versions.yml`: manifiesto con la versión publicada de cada repositorio del
  proyecto.
- Job `schema-sql` en el CI: aplica `01-init.sql` y `updates/*.sql` sobre una
  base PostgreSQL limpia, para que un SQL roto falle en el PR.
- Devcontainer con Docker, Compose y `gh`.
- Skills `infra-docker`, `schema-migrations` y `ci-cd-release`, más `AGENTS.md`.

## [0.1.0] - 2026-10-12

### Añadido
- Estructura inicial del repositorio con los compose de desarrollo, prueba y
  producción, y el schema inicial de PostgreSQL.

[No publicado]: https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/releases/tag/v0.1.0
