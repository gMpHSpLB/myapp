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
•	A production-grade GitHub Actions CI pipeline with 6 stages
•	Container image built with multi-stage Dockerfile using BuildKit cache mounts
•	Trivy vulnerability scan as a hard blocking gate (CRITICAL CVEs fail the build)
•	Cosign keyless image signing using GitHub Actions OIDC (no long-lived keys)
•	Syft SBOM generation in CycloneDX format, attested to the OCI registry
•	Helm chart linted and unit-tested in CI
•	Image tag committed to the GitOps repo as a PR (triggering ArgoCD sync)
•	Complete reusable workflow structure: one workflow calls another
•	All secrets managed via GitHub Environments, not repository secrets


