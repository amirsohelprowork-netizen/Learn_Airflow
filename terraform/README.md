# Local Terraform orchestration

This profile runs entirely on your machine and shares lifecycle scripts with `./ctl start`.

```bash
./ctl terraform init
./ctl terraform plan
./ctl terraform apply
```

Use either Terraform or shell startup as the owner of a cluster. Existing MinIO-backed Terraform state must not be applied to the new profile without a deliberate migration. The backend is now local to remove the bootstrap dependency on MinIO. External data volumes and `.local/` are retained; Terraform destroy deletes its KinD cluster.

This uses provisioners for local service configuration and Helm deployment; it does not claim full declarative drift management. Read [the setup guide](../docs/LOCAL_SETUP.md#terraform-entry-point) before applying.
