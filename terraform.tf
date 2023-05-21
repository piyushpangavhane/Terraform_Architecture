terraform {
  backend "remote" {
    organization = "pangavhane"
    workspaces {
      name = "learn-terraform-cloud-migrate"
    }
  }
}
