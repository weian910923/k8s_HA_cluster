
####k8s 叢集建置
# vm 需求
# master 01 2cpu 4G 10.151.30.11
# master 02 2cpu 4G 10.151.30.12
# master 03 2cpu 4G 10.151.30.13
# node 01 2cpu 4G 10.151.30.21
# 安裝以下套件
# ks8 1.17
# docker 19
# flannel
# ipvs
####

####
# A---------------以下步驟三台vm 都要執行
####

#禁用防火墙/禁用SELINUX/關閉 swap
systemctl stop firewalld;systemctl disable firewalld
setenforce 0
swapoff -a

#使用free -m確認 swap 已經關閉
echo "vm.swappiness=0" >> /etc/sysctl.d/k8s.conf
sysctl -p /etc/sysctl.d/k8s.conf

#建立/etc/sysctl.d/k8s.conf
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

modprobe br_netfilter
sysctl -p /etc/sysctl.d/k8s.conf

#安装 ipvs
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF

chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack_ipv4

#安装 ipset 套件
yum install ipset -y ;yum install ipvsadm -y ;yum install chrony -y

#同步機器時間
systemctl enable chronyd;systemctl start chronyd;chronyc sources

#安装 Docker
yum install -y ebtables ethtool
yum install -y yum-utils device-mapper-persistent-data lvm2
### Add Docker repository.
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
## Install Docker CE.
yum update -y  && yum install -y containerd.io-1.2.10 docker-ce-19.03.4 docker-ce-cli-19.03.4
## Create /etc/docker directory.
mkdir /etc/docker
# Setup daemon.
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

mkdir -p /etc/systemd/system/docker.service.d
# Restart Docker
systemctl daemon-reload;systemctl restart docker;systemctl enable docker

#############
# 增加 kubernetes.repo
#############

cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

#############
# 安裝 kubelet
#############

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
yum downgrade -y kubelet-1.17.3 kubeadm-1.17.3 kubectl-1.17.3 --disableexcludes=kubernetes
systemctl enable kubelet.service

#############
# B kubeadm init 初始化 --------- master 執行
#############

mkdir -p ~/k8s;cd ~/k8s
cat > ~/k8s/init.yml <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: stable
#apiServer:
#  certSANs:
#  - "10.151.30.11"
#  - "10.151.30.21"
#  - "10.151.30.22"

networking:
  podSubnet: 10.244.0.0/16
controlPlaneEndpoint: "10.151.30.11:6443"  ######### master IP
EOF

#kubeadm init 初始化
kubeadm init --config=init.yml --upload-certs

#############
#kubeadm 完成後 備份config文件
#############

#############################
#############################

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join 10.151.30.11:6443 --token ihkdr9.v6xjw5ste3eb4m13 \
    --discovery-token-ca-cert-hash sha256:b5769d3a81f25e4e89f41e10f21e203174c77fffd21406a7647276dd02c006f7 \
    --control-plane --certificate-key 46352eaee2eae395c987fb9a28ab320df8f20ce80696d99932781db9e3cde932

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.151.30.11:6443 --token ihkdr9.v6xjw5ste3eb4m13 \
    --discovery-token-ca-cert-hash sha256:b5769d3a81f25e4e89f41e10f21e203174c77fffd21406a7647276dd02c006f7

#############################
#############################

#############
#kubeconfig 文件 master 執行  --------- master01 執行
#############

#拷貝 kubeconfig 文件 master 執行
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#############
#kubeconfig 文件 master 執行  --------- master02/03 執行
#############
kubeadm join 10.151.30.11:6443 --token ihkdr9.v6xjw5ste3eb4m13 \
  --discovery-token-ca-cert-hash sha256:b5769d3a81f25e4e89f41e10f21e203174c77fffd21406a7647276dd02c006f7 \
  --control-plane --certificate-key 46352eaee2eae395c987fb9a28ab320df8f20ce80696d99932781db9e3cde932
#########完成後在執行下方指令

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


#############
#kubeconfig 文件 node 執行  --------- node01 執行
#############

kubeadm join 10.151.30.11:6443 --token ihkdr9.v6xjw5ste3eb4m13 \
    --discovery-token-ca-cert-hash sha256:b5769d3a81f25e4e89f41e10f21e203174c77fffd21406a7647276dd02c006f7

#############
#啟動 flannel
#############
kubectl create -f ./flannel.yml

#############
#查看狀態
#############

watch -n 1 kubectl get po --all-namespaces

#############
#查看完成狀態
#############
kubectl get nodes
#############
#結果
#############
[root@master01 k8s]# kubectl get node
NAME       STATUS   ROLES    AGE     VERSION
master01   Ready    master   13m     v1.17.0
master02   Ready    master   7m8s    v1.17.0
master03   Ready    master   7m8s    v1.17.0
node01     Ready    <none>   3m46s   v1.17.0
