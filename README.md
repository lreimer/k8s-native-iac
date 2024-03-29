# kubectl apply -f cloud-infrastructure.yaml with Crossplane et al.

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

## Custom Operator Demo

A custom AWS ECR operator can be built easily using the Operator SDK.

```bash
# checkout the following Git repository
git clone https://github.com/lreimer/aws-ecr-operator
cd aws-ecr-operator
make docker-build
make deploy

# try to create an ECR and do cleanup afterwards
kubectl apply -k config/samples
kubectl delete -k config/samples

# or locally
kubectl apply -f custom/repository.yaml
```

## Google ConfigConnector Demo

The ConfigConnector add-on from GKE allows the declarative management of other GCP cloud resources such as SQL instances or storage bucket. However, after the installation it needs to be configured for it to work correctly.

```yaml
kind: Namespace
apiVersion: v1
metadata:
  name: config-connector
  annotations:
    # required to configure Config Connector with Google Cloud ProjectID
    cnrm.cloud.google.com/project-id: cloud-native-experience-lab
---
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  # the name is restricted to ensure that there is only one
  # ConfigConnector resource installed in your cluster
  name: configconnector.core.cnrm.cloud.google.com
  namespace: cnrm-system
spec:
 mode: cluster
 googleServiceAccount: "cloud-native-explab@cloud-native-experience-lab.iam.gserviceaccount.com"
```

```bash
kubectl annotate namespace default cnrm.cloud.google.com/project-id="cloud-native-experience-lab"

cd applications/gke-cluster/
kubectl apply -f config-connector/storagebucket.yaml

kubectl get storagebucket -n config-connector
kubectl describe storagebucket k8s-native-iac-lab-demo -n config-connector

gcloud storage buckets list
open https://console.cloud.google.com/storage/browser?project=cloud-native-experience-lab

kubectl delete -f config-connector/storagebucket.yaml
gcloud storage buckets list
```

## AWS Controllers for Kubernetes (ACK) Demo

The Amazon controllers for Kubernetes are a lightweight AWS only option to provision cloud infrastructure the K8s-native way.

```bash
export ACK_SYSTEM_NAMESPACE=ack-system
export AWS_REGION=eu-north-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export OIDC_PROVIDER=$(aws eks describe-cluster --name eks-k8s-iac-cluster --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

cd applications/eks-cluster/

# we need to login to the public chart ECR
aws ecr-public get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin public.ecr.aws

# install the S3 controller
helm install -n $ACK_SYSTEM_NAMESPACE ack-s3-controller \
    oci://public.ecr.aws/aws-controllers-k8s/s3-chart --version=1.0.7 --set=aws.region=$AWS_REGION
kubectl get all -n ack-system

# setup IAM permissions and IRSA
envsubst < ack/s3/ack-s3-controller-trust.tpl > ack/s3/ack-s3-controller-trust.json
aws iam create-role \
    --role-name ack-s3-controller-k8s-iac-cluster-eu-north-1 \
    --assume-role-policy-document file://ack/s3/ack-s3-controller-trust.json \
    --description "IRSA role for ACK S3 controller"
aws iam attach-role-policy \
    --role-name ack-s3-controller-k8s-iac-cluster-eu-north-1 \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-s3-controller-k8s-iac-cluster-eu-north-1 --query Role.Arn --output text)
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
    oci://public.ecr.aws/aws-controllers-k8s/ecr-chart --version=1.0.10 --set=aws.region=$AWS_REGION
kubectl get all -n ack-system

envsubst < ack/ecr/ack-ecr-controller-trust.tpl > ack/ecr/ack-ecr-controller-trust.json
aws iam create-role \
    --role-name ack-ecr-controller-k8s-iac-cluster-eu-north-1 \
    --assume-role-policy-document file://ack/ecr/ack-ecr-controller-trust.json \
    --description "IRSA role for ACK ECR controller"
aws iam attach-role-policy \
    --role-name ack-ecr-controller-k8s-iac-cluster-eu-north-1 \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-ecr-controller-k8s-iac-cluster-eu-north-1 --query Role.Arn --output text)
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
    oci://public.ecr.aws/aws-controllers-k8s/rds-chart --version=1.1.9 --set=aws.region=$AWS_REGION
kubectl get all -n ack-system

envsubst < ack/rds/ack-rds-controller-trust.tpl > ack/rds/ack-rds-controller-trust.json
aws iam create-role \
    --role-name ack-rds-controller-k8s-iac-cluster-eu-north-1 \
    --assume-role-policy-document file://ack/rds/ack-rds-controller-trust.json \
    --description "IRSA role for ACK RDS controller"
aws iam attach-role-policy \
    --role-name ack-rds-controller-k8s-iac-cluster-eu-north-1 \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

export ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name=ack-rds-controller-k8s-iac-cluster-eu-north-1 --query Role.Arn --output text)
export IRSA_ROLE_ARN=eks.amazonaws.com/role-arn=$ACK_CONTROLLER_IAM_ROLE_ARN
kubectl annotate serviceaccount -n ack-system ack-rds-controller $IRSA_ROLE_ARN
kubectl -n ack-system rollout restart deployment ack-rds-controller-rds-chart

# see https://github.com/aws-controllers-k8s/rds-controller/tree/main/test/e2e/resources
# see https://aws-controllers-k8s.github.io/community/docs/tutorials/aurora-serverless-v2/
kubectl create secret generic mydb-instance-creds --from-literal=password=topsecret
kubectl apply -f ack/rds/db-subnet-group.yaml
kubectl apply -f ack/rds/db-instance.yaml
```

## Azure Service Operator (for Kubernetes)

see https://github.com/Azure/azure-service-operator

## Crossplane Demo

For AWS the configuration needs to reference the required credentials in the form of a secret.
These are basically the `aws_access_key_id` and `aws_secret_access_key` from the default profile found in the `${HOME}/.aws/credentials` file. With this information we can create a secret and reference it from a provider config resource.

```bash
kubectl create secret generic aws-secret -n crossplane-system --from-file=credentials=${HOME}/.aws/credentials

# install individual crossplance providers and provider config
cd crossplane/aws/
kubectl apply -n crossplane-system -f provider-aws-xyz.yaml
kubectl apply -n crossplane-system -f providerconfig-aws-xyz.yaml
kubectl get -n crossplane-system providers.pkg.crossplane.io

# you could also install the community-contrib provider
# Caution: this one brings CRDs for all AWS services!
kubectl apply -n crossplane-system -f provider-aws.yaml

cd crossplane/aws/examples/

# create an ECR in eu-central-1
kubectl apply -f ecr/repository.yaml
aws ecr describe-repositories

# create an S3 bucket in eu-central-1
kubectl create -f s3/bucket.yaml
aws s3 ls

# use XRD to create an ECR
kubectl apply -f xrd/repository/definition.yaml
kubectl apply -f xrd/repository/composition.yaml
kubectl apply -f xrd/repository/examples/example-repository.yaml
aws ecr describe-repositories

# use XRD to create an S3 bucket
kubectl apply -f xrd/bucket/definition.yaml
kubectl apply -f xrd/bucket/composition.yaml
kubectl apply -f xrd/bucket/examples/example-bucket.yaml
aws s3 ls
```

## CAPI Demo

```bash
# see https://cluster-api-aws.sigs.k8s.io/getting-started.html

# Make sure to export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
export AWS_REGION=$(AWS_REGION)

# needs to be done once to setup cloudformation stack and permissions
clusterawsadm bootstrap iam create-cloudformation-stack --config bootstrap-config.yaml

# You may need to set a personal GITHUB_TOKEN to avoid API rate limiting
export AWS_SSH_KEY_NAME=capi-default
export AWS_CONTROL_PLANE_MACHINE_TYPE=t3.medium
export AWS_NODE_MACHINE_TYPE=t3.medium
export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)

clusterctl init --infrastructure aws

clusterctl generate cluster capi-tenant-cluster --kubernetes-version v1.22.0 \
    --kubernetes-version v1.22.0 \
    --control-plane-machine-count=3 \
    --worker-machine-count=3 \
    > cluster-api/capi-tenant-cluster.yaml

# apply the tenant cluster resources to the management cluster
kubectl apply -f cluster-api/capi-tenant-cluster.yaml
kubectl get cluster
clusterctl describe cluster capi-tenant-cluster

# wait for the control plane to be Initialized
kubectl get kubeadmcontrolplane
clusterctl get kubeconfig capi-tenant-cluster > cluster-api/capi-tenant-cluster.kubeconfig

# install CNI plugin for CAPI tenant cluster
kubectl --kubeconfig=cluster-api/capi-tenant-cluster.kubeconfig \
    apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml
kubectl --kubeconfig=cluster-api/capi-tenant-cluster.kubeconfig get nodes

# always the the cluster object for proper cleanup
kubectl delete cluster capi-tenant-cluster
```

## Pulumi Demo

```bash
kubectl create secret generic pulumi-api-secret -n pulumi-system --from-literal=accessToken=pul-4711abcExampleToken

kubectl apply -f pulumi/nginx-k8s-stack.yaml
kubectl get all -n pulumi-system
kubectl delete -f pulumi/nginx-k8s-stack.yaml
```

## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE`
file for details.

