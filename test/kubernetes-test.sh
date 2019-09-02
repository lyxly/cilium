#!/bin/bash

k8sVersionJson=$(kubectl version -o json)

KUBERNETES_MAJOR_MINOR_VER="$(echo "${k8sVersionJson}" | jq -r '.serverVersion | .major').$(echo "${k8sVersionJson}" | jq -r '.serverVersion | .minor')"

k8sDescriptorsPath="./examples/kubernetes/${KUBERNETES_MAJOR_MINOR_VER}"
k8sManifestsPath="./test/k8sT/manifests"

kubectl apply --filename="${k8sDescriptorsPath}/cilium-etcd-operator.yaml"
kubectl apply --filename="${k8sDescriptorsPath}/cilium-etcd-operator-rbac.yaml"
kubectl apply --filename="${k8sDescriptorsPath}/cilium-etcd-operator-sa.yaml"
kubectl apply --filename="${k8sDescriptorsPath}/cilium-rbac.yaml"
kubectl patch --filename="${k8sDescriptorsPath}/cilium-cm.yaml" --patch "$(cat ${k8sManifestsPath}/cilium-cm-patch.yaml)" --local -o yaml | kubectl apply -f -
kubectl patch --filename="${k8sDescriptorsPath}/cilium-ds.yaml" --patch "$(cat ${k8sManifestsPath}/cilium-ds-patch.yaml)" --local -o yaml | kubectl apply -f -

while true; do
    result=$(kubectl -n kube-system get pods -l k8s-app=cilium | grep "Running" -c)
    echo "Running pods ${result}"
    if [ "${result}" == "2" ]; then

        echo "result match, continue with kubernetes"
        break
    fi
    sleep 1
done

set -e

echo "Installing kubetest manually"

mkdir -p ${HOME}/go/src/k8s.io
cd ${HOME}/go/src/k8s.io
test -d test-infra && rm -rfv test-infra
# Last commit before vendor directory was removed
# why? see https://github.com/kubernetes/test-infra/issues/14165#issuecomment-528620301
git clone https://github.com/kubernetes/test-infra.git
cd test-infra
git reset --hard dbc2ac103595c2348322d1bac7e4743b96fca225
GO111MODULE=off go install k8s.io/test-infra/kubetest

echo "Installing kubernetes"
KUBERNETES_VERSION=$(kubectl version -o json | jq -r '.serverVersion | .gitVersion')

mkdir -p ${HOME}/go/src/k8s.io/
cd ${HOME}/go/src/k8s.io/
test -d kubernetes && rm -rfv kubernetes
git clone https://github.com/kubernetes/kubernetes.git -b ${KUBERNETES_VERSION} --depth 1
cd kubernetes

make ginkgo
make WHAT='test/e2e/e2e.test'

export KUBERNETES_PROVIDER=local
export KUBECTL_PATH=/usr/bin/kubectl
export KUBE_MASTER=192.168.36.11
export KUBE_MASTER_IP=192.168.36.11
export KUBE_MASTER_URL="https://192.168.36.11:6443"

go run hack/e2e.go -- --test --test_args="--ginkgo.focus=NetworkPolicy --e2e-verify-service-account=false --host ${KUBE_MASTER_URL} --ginkgo.skip=name ports"
