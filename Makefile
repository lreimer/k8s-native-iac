GITHUB_USER ?= lreimer

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
	@gcloud container clusters create gke-k8s-iac-cluster --num-nodes=3 --enable-autoscaling --min-nodes=3 --max-nodes=5 --cluster-version=1.21
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

delete-clusters: delete-eks-cluster delete-gke-cluster

delete-eks-cluster:
	@eksctl delete cluster -f eks-cluster.yaml

delete-gke-cluster:
	@gcloud container clusters delete gke-k8s-iac-cluster --async --quiet
