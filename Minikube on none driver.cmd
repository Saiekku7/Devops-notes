#!/bin/bash
set -e

echo "🚀 Starting Full Minikube Setup on Ubuntu 24.04..."

# Step 1: Update and install dependencies
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release conntrack

# Step 2: Disable swap
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 3: Install containerd (Docker base)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 4: CNI plugins
CNI_VER="1.1.1"
curl -LO "https://github.com/containernetworking/plugins/releases/download/v${CNI_VER}/cni-plugins-linux-$(dpkg --print-architecture)-v${CNI_VER}.tgz"
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf "cni-plugins-linux-$(dpkg --print-architecture)-v${CNI_VER}.tgz"
rm "cni-plugins-linux-$(dpkg --print-architecture)-v${CNI_VER}.tgz"

# Step 5: crictl
CRICTL_VER="v1.30.0"
curl -LO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-$(dpkg --print-architecture).tar.gz"
sudo tar -C /usr/local/bin -xzf "crictl-${CRICTL_VER}-linux-$(dpkg --print-architecture).tar.gz"
rm "crictl-${CRICTL_VER}-linux-$(dpkg --print-architecture).tar.gz"

# Step 6: Enable IP forwarding
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# Step 7: Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client --short

# Step 8: Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
minikube version

# Step 9: Fix Ubuntu 24.04 protected_regular
sudo sysctl fs.protected_regular=0
echo "fs.protected_regular=0" | sudo tee -a /etc/sysctl.conf

# Step 10: Download cri-dockerd
VERSION=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep tag_name | cut -d '"' -f 4)
wget https://github.com/Mirantis/cri-dockerd/releases/download/${VERSION}/cri-dockerd-${VERSION#v}.amd64.tgz
tar xvf cri-dockerd-${VERSION#v}.amd64.tgz
sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
sudo chmod +x /usr/local/bin/cri-dockerd

# Step 11: Create systemd service for cri-dockerd
sudo wget -O /etc/systemd/system/cri-docker.service https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
sudo wget -O /etc/systemd/system/cri-docker.socket https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket

sudo sed -i 's|/usr/bin/cri-dockerd|/usr/local/bin/cri-dockerd|' /etc/systemd/system/cri-docker.service

sudo systemctl daemon-reload
sudo systemctl enable cri-docker.service
sudo systemctl enable --now cri-docker.socket
sudo systemctl status cri-docker.socket

# Step 12: Configure cri-dockerd Unix socket
sudo sed -i 's|ExecStart=.*|ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd:// --network-plugin=cni --listen unix:///var/run/cri-dockerd.sock|' /etc/systemd/system/cri-docker.service

sudo systemctl daemon-reload
sudo systemctl restart cri-docker.service
sudo systemctl restart cri-docker.socket

echo "Verifying cri-dockerd socket..."
ls -l /var/run/cri-dockerd.sock

# Step 13: Start Minikube
sudo -E minikube start --driver=none \
--container-runtime=docker \
--extra-config=kubelet.cgroup-driver=systemd \
--cri-socket=/var/run/cri-dockerd.sock

# Step 14: Fix kubeconfig permissions
sudo mv /root/.kube /home/ubuntu/.kube
sudo mv /root/.minikube /home/ubuntu/.minikube
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.minikube

# Step 15: Install Flannel CNI
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl get pods -n kube-flannel

# Step 16: Enable and install Ingress
minikube addons enable ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml

# Step 17: Deploy Retail Store Sample Application
kubectl apply -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml

# Step 18: Create Ingress YAML
cat <<EOF | tee ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: ""
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ui
            port:
              number: 80
EOF

kubectl apply -f ingress.yaml

# Step 19: Get Ingress Controller NodePort
echo "Checking Ingress Controller NodePort..."
kubectl get svc -n ingress-nginx

echo "✅ Minikube Setup Complete!"
echo "👉 Access your app at: http://<Public_EC2_IP>:<NodePort>"

# https://chatgpt.com/share/6902e19d-c738-8009-afb0-e62b3160c9d4
  

# setting up Minikube --driver=none on ec2 with sample app deployment with ingress controller 
