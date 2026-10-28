locals {
  project_root = abspath("${path.root}/..")
  # Same build inputs as local_config.release_tag; hashes drive reconciliation.
  source_files = sort(concat(
    ["Dockerfile", "requirements.txt", "requirements-security.txt", "values.yaml"],
    tolist(fileset(local.project_root, "config/**")),
    tolist(fileset(local.project_root, "constraints/**")),
    tolist(fileset(local.project_root, "dags/**/*.py")),
    tolist(fileset(local.project_root, "scripts/*.sh")),
    tolist(fileset(local.project_root, "scripts/*.py")),
    tolist(fileset(local.project_root, "tests/*.py")),
    tolist(fileset(local.project_root, "k8s/**"))
  ))
  source_revision = sha256(join("", [for name in local.source_files : filesha256("${local.project_root}/${name}") if !strcontains(name, "__pycache__")]))
}

module "docker_infra" {
  source          = "./modules/docker_infra"
  project_root    = local.project_root
  source_revision = local.source_revision
}

module "kind_cluster" {
  source       = "./modules/kind_cluster"
  cluster_name = "airflow-local"
  depends_on   = [module.docker_infra]
}

module "k8s_bridge" {
  source          = "./modules/k8s_bridge"
  project_root    = local.project_root
  source_revision = local.source_revision
  depends_on      = [module.kind_cluster]
}

module "platform_addons" {
  source       = "./modules/platform_addons"
  project_root = local.project_root
  depends_on   = [module.k8s_bridge]
}

module "airflow" {
  source          = "./modules/airflow"
  project_root    = local.project_root
  source_revision = local.source_revision
  depends_on      = [module.platform_addons]
}
