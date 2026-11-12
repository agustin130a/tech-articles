# Pre-releases automáticas al mergear

Código y guía paso a paso del artículo sobre cómo publicar una **pre-release automática** en cada merge
a `main` con **GitHub Actions**, sin que una ráfaga de merges la posponga para siempre y sin que dos
versiones se desplieguen a staging fuera de orden.

- Artículo: `<URL-DEL-ARTÍCULO>`

## Cómo funciona

1. El primer push a `main` arranca una espera (`PRERELEASE_QUIET_PERIOD_SECONDS`, 300 s por defecto). Los
   pushes siguientes **no** la reinician.
2. Al terminar, se lee la punta actual de `main`, se corren los tests sobre ese commit y se publica
   `v<MAJOR>.<MINOR>.<patch + 1>` como pre-release.
3. La pre-release dispara `build-artifacts.yaml` (`release: published`). El run de `auto-prerelease`
   espera a que ese build termine, deploy a staging incluido.
4. Los pushes que llegan mientras tanto dejan **un único** run pendiente
   (`concurrency` con `cancel-in-progress: false`). Cuando arranca, publica la punta de `main` en ese
   momento, o no hace nada si ya tiene tag.

## Estructura

```
github-auto-prerelease/
└── .github/
    ├── actions/
    │   ├── next-version/action.yaml        # calcula el próximo tag de la serie MAJOR.MINOR
    │   └── publish-prerelease/action.yaml  # genera las notas y crea la pre-release
    └── workflows/
        ├── auto-prerelease.yaml            # espera, tests, publicación y espera del deploy
        ├── unit-tests.yaml                 # stub: reemplázalo por tus tests (mantén el input `ref`)
        └── build-artifacts.yaml            # stub: simula build + deploy con un sleep de 120 s
```

Los dos stubs existen para probar el flujo sin una aplicación real. En un repo real, `unit-tests.yaml` y
`build-artifacts.yaml` son los tuyos: el primero tiene que aceptar el input opcional `ref` y el segundo
tiene que dispararse con `release: published`.

## Requisitos

- Una **GitHub App** de la organización, con permiso **Contents: Read and write**, instalada en el repo.
  Hace falta porque una release creada con `GITHUB_TOKEN` no dispara otros workflows
  ([documentación](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication#using-the-github_token-in-a-workflow)).
- En **Settings → Secrets and variables → Actions**:

| Nombre | Tipo | Valor |
|---|---|---|
| `RELEASE_APP_CLIENT_ID` | variable | Client ID de la App |
| `RELEASE_APP_PRIVATE_KEY` | secret | Private key (`.pem`) de la App |
| `RELEASE_VERSION_MAJOR` | variable | Major de la serie, por ejemplo `3` |
| `RELEASE_VERSION_MINOR` | variable | Minor de la serie, por ejemplo `1` |
| `PRERELEASE_QUIET_PERIOD_SECONDS` | variable | Opcional, por defecto `300` |

## Probarlo en un repo sandbox

1. Crea un repo privado de prueba y copia la carpeta `.github/` en su raíz.
2. Crea un tag inicial, por ejemplo `v3.1.10`, y súbelo.
3. Carga las variables con una espera corta:

   ```bash
   R=<org>/<repo>
   gh variable set RELEASE_APP_CLIENT_ID -R $R -b <client-id>
   gh variable set RELEASE_VERSION_MAJOR -R $R -b 3
   gh variable set RELEASE_VERSION_MINOR -R $R -b 1
   gh variable set PRERELEASE_QUIET_PERIOD_SECONDS -R $R -b 30
   gh secret set RELEASE_APP_PRIVATE_KEY -R $R < <ruta-al-pem>
   ```

   Después de cargar el secret, borra el `.pem` de tu máquina.

4. **Ráfaga:** haz tres pushes a `main` con 10 s de diferencia. Resultado esperado: una sola pre-release
   sobre el último commit; el segundo run queda cancelado y el tercero se saltea porque la punta ya tiene
   tag.
5. **Merge durante el deploy:** haz un push, espera a que el job *Wait for build and staging deploy* esté
   en curso y haz otro push. Resultado esperado: el segundo run arranca recién cuando termina el build del
   primero, y los builds no se solapan:

   ```bash
   for id in $(gh run list -R $R --workflow build-artifacts.yaml --json databaseId --jq '.[].databaseId'); do
     gh run view $id -R $R --json headBranch,jobs --jq '"\(.headBranch): \(.jobs[0].startedAt) -> \(.jobs[0].completedAt)"'
   done
   ```

## Limitaciones

- El job que espera el deploy ocupa un runner durante todo el build.
- "Re-run failed jobs" reutiliza el SHA leído en el intento original; usa "Re-run all jobs".
- Las pre-releases manuales no entran en el bloqueo.
- El reporte de tests queda asociado al commit que disparó el run, no necesariamente al testeado.
