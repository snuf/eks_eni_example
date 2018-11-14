#!env bash -xe
#
# Simple EKS and nodes destroyer
#
. subs.sh
checkExec jq

PROPS=amazon-eks-props.json
CLUSTER_NAME=$(getParamFromFile ${PROPS} ClusterName)
STACK=eks-${CLUSTER_NAME}-stack
DESTROY=1

if [ "$DESTROY" == "1" ]; then
  aws cloudformation delete-stack \
      --stack-name ${STACK}
  waitForStack ${STACK}
  kubectl auth can-i get nodes
  if [ "$?" == "0" ]; then
      echo "Destroy Failed, able to communicate to EKS!?"
      exit $?
  fi
fi
echo "Done"
