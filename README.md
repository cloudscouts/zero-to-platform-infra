# Zero to Platform Infrastructure

This repository contains the infrastructure as code (IaC) for deploying a complete platform using Terraform. The infrastructure includes a VPC, EKS cluster, and additional platform components.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (recommended version >= 1.0.0)
- kubectl installed

## Deployment Steps

The infrastructure must be deployed in a specific order to ensure proper resource creation and dependencies. Follow these steps:

### 1. Initialize Terraform

```bash
terraform init
```

This command initializes Terraform, downloads required providers, and sets up the backend.

### 2. Deploy VPC Infrastructure

```bash
terraform apply -target "module.vpc"
```

This step creates the VPC, subnets, route tables, and other networking components.

### 3. Deploy EKS Cluster

```bash
terraform apply -target "module.eks"
```

This creates the EKS cluster, node groups, and required IAM roles.

### 4. Deploy Remaining Infrastructure

```bash
terraform apply
```

This final step deploys any remaining components and ensures all resources are in their desired state.

## Post-Deployment

After successful deployment, you can:

1. Configure kubectl to interact with your cluster:
```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

2. Verify the cluster status:
```bash
kubectl get nodes
```

## Clean Up

To destroy all resources when they're no longer needed:

```bash
terraform destroy
```

**Note:** This will delete all resources created by Terraform. Make sure to backup any important data before proceeding.
