# Terraform / Terragrunt rules (TF)

- **TF-STATE** (hard): Remote state with locking; no local state for shared stacks.
- **TF-VARS** (hard): No hardcoded account IDs, regions, or secrets; use variables and data sources.
- **TF-TAGS** (judgement): Consistent tagging via `default_tags` or module convention.
- **TF-MODULE** (judgement): Reuse modules; avoid copy-paste resources.

Applies to `*.tf`, `*.tfvars`, `*.hcl`.
