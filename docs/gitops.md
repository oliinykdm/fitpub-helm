# GitOps Examples

These examples assume the chart is published through GitHub Pages at:

```text
https://oliinykdm.github.io/fitpub-helm
```

Use an externally managed Kubernetes Secret for production credentials.

## Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: fitpub
  namespace: flux-system
spec:
  interval: 1h
  url: https://oliinykdm.github.io/fitpub-helm
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: fitpub
  namespace: fitpub
spec:
  interval: 15m
  chart:
    spec:
      chart: fitpub
      version: 0.3.x
      sourceRef:
        kind: HelmRepository
        name: fitpub
        namespace: flux-system
  values:
    productionChecks:
      enabled: true
    config:
      FITPUB_DATABASE_URL: jdbc:postgresql://postgres.example.com:5432/fitpub
      FITPUB_DOMAIN: fitpub.example.com
      FITPUB_BASE_URL: https://fitpub.example.com
      FITPUB_PUSH_ENABLED: "false"
    applicationSecret:
      existingSecret: fitpub-secret
    ingress:
      enabled: true
      className: traefik
      hosts:
        - host: fitpub.example.com
          paths:
            - path: /
              pathType: Prefix
```

## Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fitpub
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://oliinykdm.github.io/fitpub-helm
    chart: fitpub
    targetRevision: 0.3.x
    helm:
      values: |
        productionChecks:
          enabled: true
        config:
          FITPUB_DATABASE_URL: jdbc:postgresql://postgres.example.com:5432/fitpub
          FITPUB_DOMAIN: fitpub.example.com
          FITPUB_BASE_URL: https://fitpub.example.com
          FITPUB_PUSH_ENABLED: "false"
        applicationSecret:
          existingSecret: fitpub-secret
        ingress:
          enabled: true
          className: traefik
          hosts:
            - host: fitpub.example.com
              paths:
                - path: /
                  pathType: Prefix
  destination:
    server: https://kubernetes.default.svc
    namespace: fitpub
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Secret Management

Do not store production secrets directly in Git. Use your platform's preferred secret workflow, for example:

- External Secrets Operator
- Sealed Secrets
- SOPS with Flux
- Argo CD Vault Plugin

The resulting Kubernetes Secret should contain keys matching the FitPub environment variables, such as `FITPUB_DATABASE_USERNAME`, `FITPUB_DATABASE_PASSWORD`, `FITPUB_JWT_SECRET` and `FITPUB_EMAIL_SECRET`. If you enable `FITPUB_PUSH_ENABLED`, also include `FITPUB_VAPID_PUBLIC_KEY` and `FITPUB_VAPID_PRIVATE_KEY`, and set `FITPUB_VAPID_SUBJECT` in `config`.
