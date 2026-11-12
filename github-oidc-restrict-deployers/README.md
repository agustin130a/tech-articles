# Restringir quién despliega a producción con GitHub Actions y OIDC

Código y guía paso a paso del artículo sobre cómo limitar **quién** y **desde qué workflow** se puede
asumir un rol de AWS desde **GitHub Actions** por OIDC, sin necesitar los required reviewers de GitHub
Enterprise.

- Artículo: `<URL-DEL-ARTÍCULO>`

## Cómo funciona

Una trust policy típica para GitHub Actions solo mira el `sub`, por ejemplo `repo:mi-org/*`. Con eso,
cualquiera con permiso de escritura en cualquier repo de la org puede asumir el rol desde cualquier rama.
AWS expone como claves de condición varios claims del token de GitHub
([documentación](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html#condition-keys-wif)).
La policy de este ejemplo usa tres:

| Clave | Qué limita |
|---|---|
| `actor_id` | **Quién**: solo los usuarios listados, por ID inmutable (un login se puede renombrar y volver a registrar). |
| `repository_id` | **Desde dónde**: solo el repo de deploy. Sin esta clave, otro repo puede llamar al workflow como reusable y sus acciones locales corren con el rol. |
| `job_workflow_ref` | **Qué**: solo los workflows de deploy, en la rama principal. Un workflow modificado en otra rama no puede asumir el rol. |

Un re-run conserva el `actor` de quien inició la corrida, y AWS no puede ver quién la relanzó. Por eso cada
job que asume el rol arranca con un step que valida `github.triggering_actor`.

## Estructura

```
github-oidc-restrict-deployers/
├── terraform/                      # rol de prueba con la trust policy (sin permisos)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── .github/
    ├── actions/whoami/action.yaml  # imprime los claims, asume el rol y corre get-caller-identity
    └── workflows/
        ├── deploy.yaml             # permitido (workflow_dispatch + workflow_call)
        ├── rollback.yaml           # permitido
        ├── upgrade-platform.yaml   # permitido
        ├── other.yaml              # no permitido
        ├── caller.yaml             # llama a deploy.yaml como reusable
        ├── _core.yaml              # variante con reusable: la lógica de deploy
        ├── prd-wrapper.yaml        # wrapper permitido (name: Deploy - Demo/Production)
        └── stg-wrapper.yaml        # wrapper no permitido (name: Deploy - Staging)
```

## Variante: workflows reusables

Si staging y producción comparten la lógica en un workflow reusable, `job_workflow_ref` es el del
reusable desde los dos lados y deja de distinguirlos. Para eso se suman dos claves:

- **`workflow`**: el `name:` del workflow que dispara la corrida (el wrapper). Tiene que ser ASCII,
  porque IAM rechaza policies con otros caracteres.
- **`ref`**: la rama de la corrida. Sin esta clave, una rama puede crear un workflow con el mismo
  nombre que llame al reusable de `main` por ruta completa
  (`uses: <org>/<repo>/.github/workflows/_core.yaml@main`). Con eso asume el rol, y las acciones locales
  salen de esa rama.

```hcl
allowed_workflows        = ["_core.yaml"]
allowed_caller_workflows = ["Deploy - Demo/Production"]
restrict_ref             = true
```

## Paso a paso

### 1. Requisitos

- Una cuenta de AWS con el proveedor OIDC `token.actions.githubusercontent.com` creado. El código lo lee
  con un `data` source: es uno por cuenta y suele estar compartido, así que no se crea acá.
- Un repo de GitHub donde subir `.github/`. Para usar `environment:` en una org con plan Free, el repo
  tiene que ser público.
- Un segundo usuario con permiso de escritura en el repo, para probar los casos denegados.

### 2. Crear el rol

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # completar org, repo, IDs
terraform init
terraform apply -var restrict=false            # primero, la policy "de antes"
```

Los IDs se obtienen con `gh`:

```bash
gh api users/<login> -q .id
gh api orgs/<org> -q .id
gh api repos/<org>/<repo> -q .id
```

### 3. Preparar el repo

```bash
gh api -X PUT repos/<org>/<repo>/environments/prd
gh variable set AWS_ROLE_ARN -R <org>/<repo> -b "$(terraform output -raw role_arn)"
```

Cambiá el login en el step `Check triggering actor` de los tres workflows permitidos. Va hardcodeado a
propósito: si fuera una variable del repo, se podría cambiar sin pasar por review.

### 4. Probar

Con `restrict=false`, el segundo usuario puede asumir el rol:

```bash
gh workflow run deploy.yaml --ref main   # como el segundo usuario
```

Después aplicá `terraform apply` (con `restrict = true`) y repetí los casos:

| Caso | Resultado esperado |
|---|---|
| Usuario autorizado, `deploy.yaml` / `rollback.yaml` / `upgrade-platform.yaml` en `main` | asume el rol |
| Usuario no autorizado, `deploy.yaml` en `main` | `Not authorized to perform sts:AssumeRoleWithWebIdentity` |
| `deploy.yaml` modificado en otra rama (`gh workflow run deploy.yaml --ref otra-rama`) | denegado |
| Workflow propio con `on: push` en otra rama | denegado |
| `other.yaml` en `main` | denegado |
| Otro repo de la org que llama a `deploy.yaml@main` como reusable | denegado (`repository_id`) |
| Re-run de una corrida del usuario autorizado, lanzado por el no autorizado | lo frena el step `Check triggering actor` |

Cada corrida imprime los claims del token (sin la firma), así se ve qué valor llega en cada caso.

### 5. Limpiar

```bash
terraform destroy
```

## Limitaciones

- **La rama principal tiene que exigir PR con review.** Si no, quien tenga write cambia el workflow
  permitido y `job_workflow_ref` deja de proteger.
- **Re-runs de corridas viejas.** Un re-run usa el workflow del commit original, así que las corridas
  anteriores al guard se pueden relanzar sin validación (GitHub permite re-runs hasta 30 días después).
  IAM no acepta `run_attempt` como condición.
- **El guard compara el login**, no un ID.
- **Mismo artefacto.** Un re-run despliega lo que apunte hoy el tag o la release. Protegé los tags con un
  ruleset o usá releases inmutables.
- **Checkout.** Los jobs que asumen el rol tienen que hacer checkout del ref de la corrida. Si hacen
  checkout de un ref elegido por input, las acciones locales salen de código no revisado.
- **Agregar o quitar un usuario** es un cambio de IaC.
