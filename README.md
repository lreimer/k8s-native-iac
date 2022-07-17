# K8s-native Infrastructure-as-code

Demo repository for Kubernetes-native infrastructure as code showcases, including Pulumi Operator, Crossplane, AWS Controllers for Kubernetes (ACK) and Cluster API.

## Bootstrapping

```bash
# define required ENV variables for the next steps to work
export AWS_ACCOUNT_ID=`aws sts get-caller-identity --query Account --output text`
export GITHUB_USER=lreimer
export GITHUB_TOKEN=<your-token>

# setup a GKE cluster with Flux2 for Crossplane and Pulumi demos
make create-gke-cluster
make bootstrap-gke-flux2

# setup an EKS cluster with Flux2 for ACK demos
make create-eks-cluster
make bootstrap-eks-flux2

# modify Flux kustomization and add
# - cluster-sync.yaml

make destroy-clusters
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

```bash
export ACK_SYSTEM_NAMESPACE=ack-system
export AWS_REGION=eu-central-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export OIDC_PROVIDER=$(aws eks describe-cluster --name eks-k8s-iac-cluster --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

aws ecr-public get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin public.ecr.aws

# install the S3 controller
helm install -n $ACK_SYSTEM_NAMESPACE ack-s3-controller \
    oci://public.ecr.aws/aws-controllers-k8s/s3-chart --version=v0.1.3 --set=aws.region=$AWS_REGION

# setup IAM permissions and IRSA
envsubst < ack/s3/ack-s3-controller-trust.tpl > ack/s3/ack-s3-controller-trust.json
aws iam create-role \
    --role-name ack-s3-controller \
    --assume-role-policy-document file://ack/s3/ack-s3-controller-trust.json \
    --description "IRSA role for ACK S3 controller"
aws iam attach-role-policy \
    --role-name ack-s3-controller \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-s3-controller --query Role.Arn --output text)
export IRSA_ROLE_ARN=eks.amazonaws.com/role-arn=$ACK_CONTROLLER_IAM_ROLE_ARN
kubectl annotate serviceaccount -n ack-system ack-s3-controller $IRSA_ROLE_ARN
kubectl -n ack-system rollout restart deployment ack-s3-controller-s3-chart

# see https://github.com/aws-controllers-k8s/s3-controller/tree/main/test/e2e/resources
kubectl apply -f ack/s3/bucket.yaml
kubectl get buckets
aws s3 ls
kubectl delete -f ack/s3/bucket.yaml
aws s3 ls

# install the ECR controller
helm install -n $ACK_SYSTEM_NAMESPACE ack-ecr-controller \
    oci://public.ecr.aws/aws-controllers-k8s/ecr-chart --version=v0.1.4 --set=aws.region=$AWS_REGION

envsubst < ack/ecr/ack-ecr-controller-trust.tpl > ack/ecr/ack-ecr-controller-trust.json
aws iam create-role \
    --role-name ack-ecr-controller \
    --assume-role-policy-document file://ack/ecr/ack-ecr-controller-trust.json \
    --description "IRSA role for ACK ECR controller"
aws iam attach-role-policy \
    --role-name ack-ecr-controller \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-ecr-controller --query Role.Arn --output text)
export IRSA_ROLE_ARN=eks.amazonaws.com/role-arn=$ACK_CONTROLLER_IAM_ROLE_ARN
kubectl annotate serviceaccount -n ack-system ack-ecr-controller $IRSA_ROLE_ARN
kubectl -n ack-system rollout restart deployment ack-ecr-controller-ecr-chart

# see https://github.com/aws-controllers-k8s/ecr-controller/tree/main/test/e2e/resources
kubectl apply -f ack/ecr/repository.yaml
kubectl get repositories
aws ecr describe-repositories
kubectl delete -f ack/ecr/repository.yaml

# install the RDS controller
helm install -n $ACK_SYSTEM_NAMESPACE ack-rds-controller \
    oci://public.ecr.aws/aws-controllers-k8s/rds-chart --version=v0.0.28 --set=aws.region=$AWS_REGION

envsubst < ack/rds/ack-rds-controller-trust.tpl > ack/rds/ack-rds-controller-trust.json
aws iam create-role \
    --role-name ack-rds-controller \
    --assume-role-policy-document file://ack/rds/ack-rds-controller-trust.json \
    --description "IRSA role for ACK RDS controller"
aws iam attach-role-policy \
    --role-name ack-rds-controller \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-rds-controller --query Role.Arn --output text)
export IRSA_ROLE_ARN=eks.amazonaws.com/role-arn=$ACK_CONTROLLER_IAM_ROLE_ARN
kubectl annotate serviceaccount -n ack-system ack-rds-controller $IRSA_ROLE_ARN
kubectl -n ack-system rollout restart deployment ack-rds-controller-rds-chart

# see https://github.com/aws-controllers-k8s/rds-controller/tree/main/test/e2e/resources
# see https://aws-controllers-k8s.github.io/community/docs/tutorials/aurora-serverless-v2/
kubectl create secret generic mydb-instance-creds --from-literal=password=topsecret
kubectl apply -f ack/rds/db-subnet-group.yaml
kubectl apply -f ack/rds/db-instance.yaml
```


## Pulumi Demo


## CAPI Demo


## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE`
file for details.

