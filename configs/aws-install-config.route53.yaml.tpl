apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${AWS_REGION}
    hostedZone: ${HOSTED_ZONE_ID}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${CONTROL_REPLICAS}
  platform:
    aws:
      type: ${CONTROL_INSTANCE_TYPE}
      zones:
      - ${AWS_REGION}a
      - ${AWS_REGION}b
      - ${AWS_REGION}c
      amiID: ${CONTROL_AMI}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: ${WORKER_REPLICAS}
  platform:
    aws:
      type: ${WORKER_INSTANCE_TYPE}
      zones:
      - ${AWS_REGION}a
      - ${AWS_REGION}b
      - ${AWS_REGION}c
      amiID: ${WORKER_AMI}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
pullSecret: '${OPENSHIFT_PULL_SECRET}'
sshKey: '${SSH_PUBLIC_KEY}'