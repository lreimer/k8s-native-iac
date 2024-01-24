AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text)
AWS_REGION ?= eu-north-1
GITHUB_USER ?= lreimer
GCP_PROJECT ?= cloud-native-experience-lab
GCP_REGION ?= europe-north1
GCP_ZONE ?= europe-north1-b

create-eks-cluster:
	@eksctl create cluster -f eks-cluster.yaml

bootstrap-eks-flux2:
	@flux bootstrap github \
		--owner=$(GITHUB_USER) \
  		--repository=k8s-native-iac \
  		--branch=main \
  		--path=./clusters/eks-cluster \
		--components-extra=image-reflector-controller,image-automation-controller \
		--read-write-key \
  		--personal

prepare-gke-cluster:
	@gcloud config set compute/zone europe-west1-b
	@gcloud config set container/use_client_certificate False

create-gke-cluster:
	@gcloud container clusters create gke-k8s-iac-cluster  \
		--addons HttpLoadBalancing,HorizontalPodAutoscaling,ConfigConnector \
		--workload-pool=$(GCP_PROJECT).svc.id.goog \
		--enable-autoscaling \
		--autoscaling-profile=optimize-utilization \
		--num-nodes=2 \
		--min-nodes=2 --max-nodes=5 \
		--machine-type=e2-standard-2 \
		--logging=SYSTEM \
    	--monitoring=SYSTEM \
		--region=$(GCP_REGION) \
		--release-channel=stable \
		--cluster-version=1.27
	@kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$$(gcloud config get-value core/account)
	@kubectl cluster-info

bootstrap-gke-flux2:
	@flux bootstrap github \
		--owner=$(GITHUB_USER) \
  		--repository=k8s-native-iac \
  		--branch=main \
  		--path=./clusters/gke-cluster \
		--components-extra=image-reflector-controller,image-automation-controller \
		--read-write-key \
  		--personal

prepare-capi-aws:
	# create an SSH key
	@export AWS_REGION=$(AWS_REGION)
	@export AWS_ACCESS_KEY_ID=<INSERT>
	@export AWS_SECRET_ACCESS_KEY=<INSERT>
	@clusterawsadm bootstrap iam create-cloudformation-stack --config bootstrap-config.yaml

install-capi-aws:
	# required to avoid API rate limiting
	@echo "You may need to set a personal GITHUB_TOKEN to avoid API rate limiting"
	@export AWS_REGION=$(AWS_REGION)
	@export AWS_SSH_KEY_NAME=capi-default
	@export AWS_CONTROL_PLANE_MACHINE_TYPE=t3.medium
	@export AWS_NODE_MACHINE_TYPE=t3.medium
	@export AWS_B64ENCODED_CREDENTIALS=$(shell clusterawsadm bootstrap credentials encode-as-profile)
	@clusterctl init --infrastructure aws

delete-clusters: delete-eks-cluster delete-gke-cluster

delete-eks-cluster:
	@eksctl delete cluster --region=eu-north-1 --name=eks-k8s-iac-cluster
	@aws cloudformation delete-stack --region eu-north-1 --stack-name eksctl-eks-k8s-iac-cluster-cluster

delete-gke-cluster:
	@gcloud container clusters delete gke-k8s-iac-cluster --region=$(GCP_REGION) --async --quiet
