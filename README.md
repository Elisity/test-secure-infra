# Elisity Infrastructure Automation

*THIS DOCUMENTATION IS A WORK IN PROGRESS!!!*
## Quick start

### Prequisites (work in progress)

#### Install CLI tools

On a UNIX-like (or Mac OS) environment:

- Install basic tools:  `jq`, `curl`
- Install `terraform` 0.14 or later
- Optional: install `direnv` to manage your environment variables


#### Configure your AWS credentials

Please refer to the AWS document or use the `aws configure` command to configure your AWS credentials.

 - Credentials *must* be configured in an AWS profile named `duplo-elisity`, as the scripts will expect that.

#### Set up environment variables

If you are using `direnv`, populate the following in your `.envrc` (in the project root), then run `direnv allow`.

If you are not using `direnv`, you can just run the following in your shell.

```shell
# .envrc

# Needed to authenticate to Duplo
export duplo_token="!! REPLACE WITH YOUR DUPLO TOKEN (generated from the Duplo UI) !!"
export duplo_host="https://elisity.duplocloud.net"

# Needed for Terraform state to be stored in S3
export AWS_DEFAULT_REGION="us-west-2"
export AWS_REGION="us-west-2"
```

### Configuring the application

--- TODO -- 

config subdirectory:  config/@NAME@/@TF_PROJECT_NAME@.tfvars.json

### Deploying the application

Come up with a name for your tenant, such as `dev`.

Replace the `dev` below with whatever your tenant name is.

#### Planning changes with Terraform

A plan is non-destructive, it is just like a "dry run".

```shell
name="dev"  # <== CHANGE "dev" HERE

# Plans the base infrastructure
scripts/plan.sh "$name" base-infra

# Plans the tenant and any services used by the application.
scripts/plan.sh "$name" app-services

# Plans the application deployment (Elisity microservices)
scripts/plan.sh "$name" app
```

#### Applying changes with Terraform

Applying changes can be **DESTRUCTIVE**.  Always check what your changes might be, first, by running `plan.sh` (see above).

```shell
name="dev"  # <== CHANGE "dev" HERE

# Applies the base infrastructure
scripts/apply.sh "$name" base-infra

# Applies the tenant and any services used by the application.
scripts/apply.sh "$name" app-services

# Applies the application deployment (Elisity microservices)
scripts/apply.sh "$name" app
```
