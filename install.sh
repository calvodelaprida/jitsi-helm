### Create aks cluster
az group create --name jitsi --location westeurope
az aks create -g jitsi -n aksjitsi --enable-managed-identity --node-count 1 --enable-addons monitoring --enable-msi-auth-for-monitoring  --generate-ssh-keys
az aks get-credentials --resource-group jitsi --name aksjitsi
kubectl get nodes

# Set this variable to the name of your ACR. The name must be globally unique.
MYACR=acrjitsi
# Create an AKS cluster with ACR integration.
az aks create -n aksjitsi -g jitsi --generate-ssh-keys --attach-acr $MYACR


### Create ingress
NAMESPACE=ingress-basic

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

kubectl get services --namespace ingress-basic -o wide -w ingress-nginx-controller


### Deploy demo application
# kubectl apply -f aks-helloworld-one.yaml --namespace ingress-basic
# kubectl apply -f aks-helloworld-two.yaml --namespace ingress-basic
# kubectl apply -f hello-world-ingress.yaml --namespace ingress-basic


### set dnslabel -> http://hamaeljitsi.westeurope.cloudapp.azure.com
DNSLABEL="hamaeljitsi"
NAMESPACE="ingress-basic"

helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNSLABEL \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz


### Install cert-manager
# import cert-manager images
REGISTRY_NAME=acrjitsi
CERT_MANAGER_REGISTRY=quay.io
CERT_MANAGER_TAG=v1.8.0
CERT_MANAGER_IMAGE_CONTROLLER=jetstack/cert-manager-controller
CERT_MANAGER_IMAGE_WEBHOOK=jetstack/cert-manager-webhook
CERT_MANAGER_IMAGE_CAINJECTOR=jetstack/cert-manager-cainjector

az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG
az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG
az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG

# Set variable for ACR location to use for pulling images
ACR_URL=acrjitsi.azurecr.io

# Label the ingress-basic namespace to disable resource validation
kubectl label namespace ingress-basic cert-manager.io/disable-validation=true

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install the cert-manager Helm chart
helm install cert-manager jetstack/cert-manager \
  --namespace ingress-basic \
  --version=$CERT_MANAGER_TAG \
  --set installCRDs=true \
  --set nodeSelector."kubernetes\.io/os"=linux \
  --set image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CONTROLLER \
  --set image.tag=$CERT_MANAGER_TAG \
  --set webhook.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_WEBHOOK \
  --set webhook.image.tag=$CERT_MANAGER_TAG \
  --set cainjector.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CAINJECTOR \
  --set cainjector.image.tag=$CERT_MANAGER_TAG

# Create ClusterIssuer
kubectl apply -f cluster-issuer.yaml --namespace ingress-basic

# After including tls in hello-world-ingress.yaml
kubectl apply -f hello-world-ingress.yaml --namespace ingress-basic

# Verify certificate has been issued -> output should read "READY: true"
kubectl get certificate --namespace ingress-basic


### Install jitsi
helm repo add jitsi https://jitsi-contrib.github.io/jitsi-helm/
helm install -f jitsi-values.yaml myjitsi jitsi/jitsi-meet

