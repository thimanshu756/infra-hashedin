# GCR Prerequisites Module (GCP)

## What it creates
- **GCP API Enablement** — Container Registry, IAM, Storage, IAM Credentials, STS
- **Service Account** (`eks-gcr-pusher`) with `roles/storage.admin` (GCR uses GCS)
- **Service Account Key** — output as sensitive value for manual use
- **Workload Identity Pool + Provider** — GitHub Actions OIDC for keyless GCR push
- **IAM Binding** — allows GitHub Actions to impersonate the service account

## Required inputs
| Variable | Description |
|---|---|
| `project_name` | Project name |
| `environment` | Environment |
| `owner` | Resource owner |
| `gcp_project_id` | GCP project ID |
| `github_org` | GitHub org or username |
| `github_repo` | GitHub repo name |

## Optional inputs
| Variable | Default | Description |
|---|---|---|
| `gcp_region` | `us-central1` | GCP region |

## Outputs
| Output | Description |
|---|---|
| `service_account_email` | GCR pusher SA email |
| `service_account_key` | Base64 encoded SA key (sensitive) |
| `workload_identity_provider` | WI provider resource name |
| `workload_identity_pool_name` | WI pool name |

## GitHub Actions Usage
Use the Workload Identity Provider output to authenticate in GitHub Actions:
```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ outputs.gcr_workload_identity_provider }}
    service_account: ${{ outputs.gcr_service_account_email }}
```
