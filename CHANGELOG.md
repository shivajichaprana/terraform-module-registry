# Changelog

All notable changes to this project are documented in this file. This file is
generated from Conventional Commit messages; do not edit released sections by hand.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-13

### Added

- `s3-bucket` module — hardened S3 bucket with encryption, public-access blocking,
  ACLs disabled, and TLS enforcement.
- `vpc` module — multi-AZ VPC with public/private subnets, per-AZ or single NAT
  egress, and encrypted VPC Flow Logs.
- `iam-role` module — reusable IAM role with service/account/OIDC trust, managed
  and inline policies, and a permissions boundary.
- Native Terraform test harness running against a mocked provider, with `tflint`
  and `checkov` policy scanning.
- Machine-readable module manifest (`registry.json`) generated from module sources,
  and semantic-version release automation driven by Conventional Commits.

[1.0.0]: https://github.com/<your-github-org>/terraform-module-registry/releases/tag/v1.0.0
