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


