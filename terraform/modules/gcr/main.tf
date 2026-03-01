# =============================================================================
# GCR Prerequisites Module (GCP Side)
# =============================================================================
# Creates: GCP API enablement, service account for GCR push,
#          Workload Identity Pool + Provider for GitHub Actions OIDC
# =============================================================================

locals {
  common_labels = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Enable Required GCP APIs
# -----------------------------------------------------------------------------
resource "google_project_service" "container_registry" {
  project = var.gcp_project_id
  service = "containerregistry.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iam" {
  project = var.gcp_project_id
  service = "iam.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "storage" {
  project = var.gcp_project_id
  service = "storage.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iam_credentials" {
  project = var.gcp_project_id
  service = "iamcredentials.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "sts" {
  project = var.gcp_project_id
  service = "sts.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# -----------------------------------------------------------------------------
# GCP Service Account: eks-gcr-pusher
# -----------------------------------------------------------------------------
resource "google_service_account" "gcr_pusher" {
  project      = var.gcp_project_id
  account_id   = "eks-gcr-pusher"
  display_name = "EKS GCR Pusher - Push images to GCR from EKS/GitHub Actions"

  depends_on = [google_project_service.iam]
}

# GCR uses GCS internally, so storage.admin grants push access
resource "google_project_iam_member" "gcr_pusher_storage" {
  project = var.gcp_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.gcr_pusher.email}"
}

# -----------------------------------------------------------------------------
# Service Account Key (sensitive — output for manual use if needed)
# -----------------------------------------------------------------------------
resource "google_service_account_key" "gcr_pusher" {
  service_account_id = google_service_account.gcr_pusher.name
}

# -----------------------------------------------------------------------------
# Workload Identity Pool + Provider for GitHub Actions OIDC
# -----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "${var.project_name}-github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions OIDC"

  depends_on = [google_project_service.iam, google_project_service.sts]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.project_name}-github-provider"
  display_name                       = "GitHub Actions Provider"
  description                        = "OIDC provider for GitHub Actions to push to GCR"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow the GitHub Actions identity to impersonate the GCR pusher service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.gcr_pusher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}
