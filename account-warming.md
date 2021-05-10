# Account Warming / Onboarding

This document describes the process for warming and onboarding a new linked AWS account.

## Step 1 - Prerequisites

Let's consider a fictitious account named `frem03`.

### Existing infrastructure

 - Linked customer AWS account from Elisity
 - admin AWS credentials to the above account
 - a "reference" account from which AWS secrets will be copied

### Command-line Tools

 - terraform 0.14.x
 - jq
 - awscli v2
 - bash

### Environment

 - ~/.aws/config prepared with a profile named `elisity-frem03`
   - has the admin creds
   - has the default region configured
 - initial environment variables prepared:
   - `frem03_duplo_host=https://elisity-frem03.duplocloud.net`

## Step 2 - Initial onboarding script

Let's consider a fictitious account named `frem03`.

Running `scripts/onboard-account.sh frem03` will:

 - copy any missing AWS secrets from the "reference" account to `frem03`
 - ensure that storage for Terraform state has been created in `frem03`
 - run Terraform on the `terraform/account` project to perform initial onboarding:
   - configure an internal DNS zone `frem03.intdev.elisity.net`
   - configure an SSL cert for `*.frem03.intdev.elisity.net` and `frem03.intdev.elisity.net`
   - configure an SSL cert for `*.elisity.net`
   - give permission to launch the master's TLS server AMIs from `frem03`
   - give permission to pull master's ECR images from `frem03`
   - install Duplo in the new account

## Step 3 - Duplo configuration and preparation

Let's consider a fictitious account named `frem03`.

### Duplo operations staff actions

To be performed by Duplo operations staff:

 - Create DNS entry for Duplo server:  `https://elisity-frem03.duplocloud.net`
 - Configure master settings:
   - `AWSEXTRAREGIONS="us-east-1;us-east-2;us-west-1"`
   - `AWSENABLEJITADMINAPI="true"`
   - `ENABLEAWSJITACCESSTOKEN="true"`
 - Generate a long-lived admin token from the UI
   - give to elisity operations staff
 - Deploy duplo shell (for EKS shell)
 - Onboard Elisity operations admins
   - Enable O365 logins
   - Create accounts:
     - raghavan@elisity.com
     - barath@elisity.com

### Elisity operations staff actions

To be performed by Elisity operations staff:

 - update environment variables with long-lived admin token from duplo operations staff
   - `frem03_duplo_token=THE-TOKEN-FROM-DUPLO-OPERATIONS-STAFF`

## Step 4 - Generate and commit temporary tenant configuration

Let's consider a fictitious account named `frem03`.

 - TODO: Ragahavan and Joe will come up with a way to copy a `config/golden-frem` to `config/frem03`

## Step 5 - Deploy a warmed environment without Elisity software

Let's consider a fictitious account named `frem03`.

Create the pre-warmed infrastructure:

 - `scripts/apply.sh frem03 base-infra`
 - `scripts/apply.sh frem03 app-services`
