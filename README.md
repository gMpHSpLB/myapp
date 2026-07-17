# Project:
"Enterprise Kubernetes CI Pipeline: Secure Image Build, Cosign Signing, SBOM Attestation, and GitOps Promotion with GitHub Actions"

## Tool versions: 
```console
  GitHub Actions runners ubuntu-24.04,
  docker/build-push-action@v6,
  actions/checkout@v4,
  cosign-installer@v3.6.0,
  syft v1.x,
  trivy v0.58+,
  Kubernetes version: 1.31+,
  ArgoCD 2.12+,
  Helm 3.16+
```
# What You Will Build
```console
•	A production-grade GitHub Actions CI pipeline with 6 stages
•	Container image built with multi-stage Dockerfile using BuildKit cache mounts
•	Trivy vulnerability scan as a hard blocking gate (CRITICAL CVEs fail the build)
•	Cosign keyless image signing using GitHub Actions OIDC (no long-lived keys)
•	Syft SBOM generation in CycloneDX format, attested to the OCI registry
•	Helm chart linted and unit-tested in CI
•	Image tag committed to the GitOps repo as a PR (triggering ArgoCD sync)
•	Complete reusable workflow structure: one workflow calls another
•	All secrets managed via GitHub Environments, not repository secrets
```
## CI's job is to produce and verify an artefact. Delivery is ArgoCD's job.

CI produces and verifies an artefact; ArgoCD is the only thing with cluster credentials. 
Every design decision in this pipeline:
   — no kubectl apply in CI, 
   — SHA/digest tags instead of latest, 
   — A separate GitOps repo — falls out of that one boundary.
   
# Pipeline Stage Overview

<img width="2720" height="3440" alt="t05_github_actions_pipeline" src="https://github.com/user-attachments/assets/2e1ef39a-486f-4d9c-8cd5-6b73e79a89c0" />

```console
Stage 1: Test + Lint
  ├── Python unit tests (pytest)
  ├── Helm lint (helm lint --strict)
  └── helm-unittest (chart unit tests)

Stage 2: Build (depends on Stage 1)
  ├── docker buildx build (multi-platform: linux/amd64 + linux/arm64)
  ├── BuildKit cache mount (faster rebuilds)
  └── Push to GHCR with SHA tag

Stage 3: Security Scan (depends on Stage 2)
  ├── trivy image scan
  ├── CRITICAL CVE → fail build (exit non-zero)
  └── Scan report uploaded as GitHub Actions artefact

Stage 4: Sign + Attest (depends on Stage 3)
  ├── cosign sign (keyless — OIDC via GitHub Actions)
  ├── syft generate SBOM (CycloneDX JSON)
  └── cosign attest (attach SBOM to image in registry)

Stage 5: Helm Package (parallel with Stage 4)
  ├── helm package ./charts/myapp
  └── helm push oci://ghcr.io/org/charts

Stage 6: GitOps Update (depends on Stage 4)
  ├── Clone gitops-repo
  ├── Update envs/dev/values.yaml: image.tag: $DIGEST
  ├── Commit + push (direct to dev, PR for staging/prod)
  └── ArgoCD webhook fires → sync begins
```

# Storage map — where every artifact physically lives:
<img width="2720" height="2600" alt="t05_artifact_storage_map" src="https://github.com/user-attachments/assets/9fc361cb-e8d4-41fa-9a5b-8790fa1368f2" />

## Why three repos and how they link
You have:
 1. myapp repo : Contains app source code (FastAPI), Dockerfile, Helm chart, and dev/staging/prod values for development and testing.
  
 2. Gitops-Argocd_1 repo : Contains ArgoCD Application definitions and environment values for dev, staging, prod — this is the deployment config repo ArgoCD watches.
  
 3. OCI registry (GHCR) : Stores built container images and Helm charts (ghcr.io/gmphsplb/myapp, ghcr.io/gmphsplb/helm-lab).

### How they link:
  - CI in myapp builds and pushes the image/chart to GHCR.
  - The same CI updates the Gitops-Argocd_1 repo (values files) to point to the new image digest / version.
  - ArgoCD is configured to watch the Gitops-Argocd_1 repo; when values change (and PR is merged), ArgoCD syncs the cluster to match Git.

So:
myapp repo = how to build & test the app.
GHCR = where the built artifacts live.
Gitops-Argocd_1 = what should be deployed where.

### This separation is a recommended GitOps pattern: 
  - app code in one repo, deployment config in another, artifacts in a registry. 
  - It decouples development from operations and lets ArgoCD only need read access to the config repo and registry.

## Why both repos have environment values
You effectively have two layers of environment-specific config:

1. myapp repo values
  - Used for development/CI: helm lint, helm unittest, maybe local dev cluster installs.
  - Owned by the app team; close to the chart and code.

2. Gitops-Argocd_1 envs/dev|staging|prod/values.yaml
  - Used for actual deployments in the cluster, via ArgoCD.
  - Owned by the ops/platform/GitOps perspective.

### Why have both:
It lets you:
    - Test the chart in myapp with realistic values (dev/staging/prod) without touching the live cluster config.
    - Keep deployment ownership and promotion rules in a dedicated GitOps repo (Gitops-Argocd_1), including PR approvals, audit trail, and  
      environment separation.

Over time, you can converge these so that Gitops-Argocd_1 values become the single source of truth, and myapp’s values are used only for 
local testing or are even removed if you prefer one config repo pattern.

In short: myapp values are for pre-deploy validation; Gitops-Argocd_1 values are for actual deployment state that ArgoCD enforces.

## When OCI is used vs when Gitops-Argocd_1 comes in
### OCI (GHCR) use
  OCI registry is used when:
    1. CI runs in myapp:
        - Builds the Docker image and pushes ghcr.io/gmphsplb/myapp@sha256:....
        - Packages the Helm chart and pushes oci://ghcr.io/gmphsplb/helm-lab/myapp.
    2. ArgoCD deploys:
        - Kubernetes pulls the image from GHCR.
        - (If you configure ArgoCD to use the OCI Helm chart directly, Helm in ArgoCD pulls from GHCR too.)
  So OCI is the artifact store: images and charts live there, immutable and versioned.

### Gitops-Argocd_1 use
  Gitops-Argocd_1 comes into play when:
    -  You want to change what is deployed: you update envs/dev/values.yaml or envs/staging/values.yaml to point to a new image digest or 
       change config.
    -  CI (from myapp) automates that change by:
         - Checking out Gitops-Argocd_1.
         - Updating image.digest, image.tag, image.repository in envs/dev or envs/staging.
         - Committing/pushing and creating a PR for staging.
    -  ArgoCD monitors Gitops-Argocd_1:
         - Sees that values changed.
         - Syncs the cluster to those new values (deploying the new image from GHCR).
  So Gitops-Argocd_1 is the declarative desired state for each environment; OCI is the actual artifact that implements that state.

  
<img width="2720" height="1840" alt="t05_job4_5_6_data_flow" src="https://github.com/user-attachments/assets/7f49da37-e103-4ec8-823c-26a2454434ab" />

