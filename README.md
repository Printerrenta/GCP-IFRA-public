# Printer rental infrastructure - public reference

Terraform modules and mock tests for the printer rental microservices.
See the [system overview](https://github.com/Printerrenta/PSI-BE-public).

```mermaid
flowchart LR
  Images[Independent service images] --> Run[Private Cloud Run services]
  Scheduler[Scheduler] --> Run
  Run --> PubSub[Pub/Sub]
  PubSub --> Run
  Run --> Secrets[Secret Manager references]
  Run --> DB[Separate PostgreSQL databases]
```

The public copy includes Terraform logic and mock tests. Real backend buckets,
environment files, deployment identities, operating release records and Cloud
Build deployment configuration are excluded. Mock project IDs and addresses are
examples. No runnable Java application belongs to this infrastructure repository.

From terraform/:

```sh
terraform fmt -check -recursive
terraform init -backend=false -lockfile=readonly
terraform validate
terraform test
```

Mock tests require no GCP credentials and create no cloud resources. Applying
infrastructure requires a separately configured backend, your own credentials,
review of IAM and costs, and an explicit operator decision. This public mirror
does not deploy the private environment.

PUBLIC_MIRROR.json records snapshot checksums. The public history is independent;
new snapshots follow successful main CI. Production configuration and private Git
history are never exported by the allowlist. Contributions belong in the source;
this generated mirror may replace direct edits on synchronization.

## Infrastructure and delivery boundaries

- Terraform owns service settings, runtime identities and narrowly scoped
  service-to-service invoker grants.
- Service delivery pipelines own deployed image digests and traffic promotion;
  the Cloud Run module excludes those fields from Terraform drift updates.
- Secret Manager configuration contains references, not secret payloads.
- Use the included mock tests to inspect infrastructure behavior without
  operational cloud credentials. Environment examples must be adapted to your
  own project; they do not provide access to the hosted deployment.
