#
# Functions used for populating files and checking components.
#
checkExec() {
  local exec=${1}
  which -s ${exec}
  if [ "$?" != "0" ]; then
    echo "We require ${exec} executable."
    exit 1
  fi
}

getParamFromFile() {
  local file=${1}
  local param=${2}
  res=$(cat ${file} | jq --arg P ${param} '.[] |
    select(.ParameterKey|test($P)) |
      .ParameterValue' | \
    sed -e s/\"//g)
  echo $res
}

getParamFromOutputCF() {
  local stack=${1}
  local param=${2}
  res=$(aws cloudformation describe-stacks --stack-name ${stack} | \
    jq --arg P ${param} '.Stacks[].Outputs[] |
      select(.OutputKey|test($P)) |
      .OutputValue' | \
    sed -e s/\"//g)
  echo $res
}

waitForStack() {
  local stack=${1}
  stackStatus=""
  until \
    [ "$stackStatus" = "CREATE_COMPLETE" ] \
    || [ "$stackStatus" = "CREATE_FAILED" ]; do
      stackStatus=$(aws cloudformation describe-stacks --stack-name ${STACK} | \
        jq -c -r .Stacks[0].StackStatus)
      lastEvent=$(aws cloudformation describe-stack-events --stack ${STACK} \
          --query 'StackEvents[].{ ResourceType:ResourceType, LogicalResourceId:LogicalResourceId }' \
          --max-items 1 | jq -r '.[0].ResourceType + " " + .[0].LogicalResourceId')
      echo -ne "Building stack $stackStatus $lastEvent, running for ${SECONDS}s........."\\r
      if [ "$stackStatus" = "ROLLBACK_COMPLETE" ] \
        || [ "$stackStatus" = "DELETE_COMPLETE" ] \
        || [ "$stackStatus" = "" ]; then
        echo "Deployment of stack ${STACK} failed, last state: $stackStatus."
        exit 1
      fi
      sleep 5
  done
  echo -ne "Building stack $stackStatus $lastEvent, running for ${SECONDS}s"\\r
}
