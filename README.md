# K8s-native Infrastructure-as-code

Demo repository for Kubernetes-native infrastructure as code showcases, including Pulumi Operator, Crossplane, ACK and Cluster API.

## Bootstrapping

```bash
# define required ENV variables for the next steps to work
$ export AWS_ACCOUNT_ID=`aws sts get-caller-identity --query Account --output text`
$ export GITHUB_USER=lreimer
$ export GITHUB_TOKEN=<your-token>

# setup a GKE cluster with Flux2 for Crossplane and Pulumi demos
$ make create-gke-cluster
$ make bootstrap-gke-flux2

# setup an EKS cluster with Flux2 for ACK demos
$ make create-eks-cluster
$ make bootstrap-eks-flux2

# modify Flux kustomization and add
# - cluster-sync.yaml

$ make destroy-clusters
```

## Custom Demo


## Crossplane Demo

For AWS the configuration needs to reference the required credentials in the form of a secret.
These are basically the `aws_access_key_id` and `aws_secret_access_key` from the default profile found in the `${HOME}/.aws/credentials` file. With this information we can create a secret and reference it from a provider config resource.

```bash
kubectl create secret generic aws-credentials -n crossplane-system --from-file=credentials=${HOME}/.aws/credentials

# we could manually install the AWS provider
# kubectl crossplane install provider crossplane/provider-aws:v0.29.0

cd crossplane/aws/
kubectl apply -n crossplane-system -f provider.yaml
kubectl apply -n crossplane-system -f providerconfig.yaml

cd crossplane/aws/examples/

# create an S3 bucket in eu-central-1
kubectl apply -f s3/bucket.yaml
aws s3 ls

# create an ECR in eu-central-1
kubectl apply -f ecr/repository.yaml
aws ecr describe-repositories

# create Aurora Serverless in eu-central-1
kubectl apply -f db/aurora-serverless.yaml
aws rds describe-db-clusters
kubectl apply -f db/aurora-client.yaml

# use XRD to create an S3 bucket
kubectl apply -f xrd/bucket/definition.yaml
kubectl apply -f xrd/bucket/composition.yaml
kubectl apply -f xrd/bucket/examples/example-bucket.yaml

# use XRD to create an ECR
kubectl apply -f xrd/repository/definition.yaml
kubectl apply -f xrd/repository/composition.yaml
kubectl apply -f xrd/repository/examples/example-repository.yaml

# use XRD to create PostgreSQL instance
kubectl apply -f xrd/postgresql/definition.yaml
kubectl apply -f xrd/postgresql/composition.yaml
kubectl apply -f xrd/postgresql/examples/example-db.yaml

kubectl get postgresqlinstances.db.aws.qaware.de example-db
kubectl get claim

kubectl get secrets
kubectl describe secret example-db-conn

kubectl apply -f xrd/postgresql/examples/example-db-client.yaml
kubectl get pods
kubectl logs example-db-client-sjdh7
```

## ACK Demo


## Pulumi Demo


## CAPI Demo


## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE`
file for details.

