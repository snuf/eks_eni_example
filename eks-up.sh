#!env bash -xe
#
# Simple EKS and nodes bootstrapper, checks some output and prepares
# some files.
#
# However, when the
#
. subs.sh
checkExec jq

PROPS=amazon-eks-props.json
YML=amazon-eks.yml
DEPLOY=1
CLUSTER_NAME=$(getParamFromFile ${PROPS} ClusterName)
STACK=eks-${CLUSTER_NAME}-stack

if [ "$DEPLOY" == "1" ]; then
  aws cloudformation create-stack \
      --stack-name ${STACK} \
      --template-body file://${YML} \
      --parameters file://${PROPS} \
      --capabilities CAPABILITY_IAM
  waitForStack ${STACK}

  # get outputs from create-stack
  aws eks update-kubeconfig --name ${CLUSTER_NAME}
  kubectl auth can-i get nodes
  if [ $? != 0 ]; then
      echo "Unable to communicate to EKS!?"
      exit $?
  fi
fi
INSTANCE_ROLE=$(getParamFromOutputCF ${STACK} NodeInstanceRole)
cat eks-combined.yml | \
  sed -e s#%NodeInstanceRole%#${INSTANCE_ROLE}#g > .eks_actual.yml
kubectl apply -f .eks_actual.yml

NODES_COUNT=$(getParamFromFile ${PROPS} NodeAutoScalingGroupMaxSize)
ready="0"
until [ "$ready" = "${NODES_COUNT}" ]; do
  ready=$(kubectl get nodes | grep -i " ready" | wc -l | awk '{ print $1 }')
  echo "Waiting for worker nodes to get ready, $ready out of ${NODES_COUNT}"
  sleep 3
done
rm .eks_actual.yml
echo "Done, $ready workers"
