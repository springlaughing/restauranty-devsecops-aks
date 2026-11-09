# Persistent layer

The Azure resources that must **survive a daily cluster rebuild**: secrets, images and the domain's IP address. Nothing here depends on the cluster, so destroying and recreating the cluster never touches them.

Applied once, early, and then left alone.

| Resource | Why it is persistent |
| --- | --- |
| Key Vault (`kv-evgenia-restauranty`) | A deleted vault keeps its name reserved (soft delete), and the secret values would have to be set again. |
| Container registry (`acrevgeniarestauranty`, Basic) | The images outlive any single cluster. |
| Static public IP (`pip-evgenia-restauranty`) | The DNS records and the HTTPS certificate point at one fixed address. |
| Pipeline identity (`id-evgenia-restauranty-pipeline`) | GitHub Actions signs in as this; recreating it would break the federated login. |

The **cluster** lives in the separate `infra-aks` repo and is read with a data source where needed. The **per-service identities and their Key Vault roles** live in `../cluster-access/` (added with #8), because they depend on the cluster's OIDC issuer and are rebuilt with it.

## Apply (once)

```bash
cd terraform/persistent
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform plan -out persistent.tfplan   # review
terraform apply persistent.tfplan
```

## Set the secret values (once, by hand)

Terraform creates the vault but never the secret values, so no secret is ever in Terraform state.

```bash
KV=$(terraform output -raw key_vault_name)

# JWT keys (the pair created for local dev, or a fresh pair)
az keyvault secret set --vault-name "$KV" --name jwt-private-key --file jwt-private.pem
az keyvault secret set --vault-name "$KV" --name jwt-public-key  --file jwt-public.pem

# MongoDB password and Cloudinary keys
az keyvault secret set --vault-name "$KV" --name mongo-password     --value '<password>'
az keyvault secret set --vault-name "$KV" --name cloudinary-url     --value '<cloudinary url>'
```

## Notes

- `acr_name` must be globally unique. If `terraform apply` says the name is taken, set a different `acr_name` and re-run.
- Purge protection is off on purpose, so the vault can be fully removed when the course ends. Turn it on for a real deployment.
